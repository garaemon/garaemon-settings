;;; my-keybind-stats.el --- Log command and key usage for later analysis -*- lexical-binding: t; -*-

;;; Commentary:
;; Records which commands run, through which keys, in which major mode,
;; so that `scripts/keybind_stats.py' can report which bindings are used,
;; which are forgotten, and which commands deserve a shorter key.
;;
;; The recorder runs on `post-command-hook' and only increments an
;; in-memory counter keyed by (command, keys, mode, via-M-x, existing
;; binding).  A timer flushes the counters to
;; `my-keybind-stats-directory' as JSON lines, one file per month:
;;
;;   {"ts":"2026-09-11T10:05:00+0900","command":"forward-char","keys":"C-f",
;;    "mode":"python-mode","mx":false,"bound":null,"count":12}
;;
;; A command invoked through M-x is logged with keys "M-x" and, in
;; "bound", the key that would have run the same command directly.  The
;; global keymap and the local keymap of every major mode seen in a
;; session are written to `bindings/<scope>.jsonl', so the report can
;; list bindings that never appear in the event log.

;;; Code:

(defgroup my-keybind-stats nil
  "Log command and key usage for later analysis."
  :group 'convenience)

(defcustom my-keybind-stats-directory
  (expand-file-name "keybind-stats" user-emacs-directory)
  "Directory that receives the event log and the binding snapshots."
  :type 'directory)

(defcustom my-keybind-stats-flush-interval 300
  "Seconds between two writes of the in-memory counters to disk."
  :type 'integer)

(defcustom my-keybind-stats-ignored-commands
  '(self-insert-command
    org-self-insert-command
    vterm--self-insert
    mwheel-scroll
    pixel-scroll-precision
    handle-switch-frame
    handle-select-window
    ignore
    undefined)
  "Commands that the recorder drops.
Typing and scrolling would dominate the log without saying anything
about key bindings."
  :type '(repeat symbol))

(defcustom my-keybind-stats-python-program "python3"
  "Interpreter that runs scripts/keybind_stats.py for `my-keybind-stats-report'."
  :type 'string)

(defconst my-keybind-stats--script-file
  (expand-file-name "../scripts/keybind_stats.py"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The report script, located relative to this file.")

(defvar my-keybind-stats--counts (make-hash-table :test #'equal)
  "Pending counts keyed by (COMMAND KEYS MODE VIA-M-X BOUND).")

(defvar my-keybind-stats--m-x-depth nil
  "Recursion depth at which `execute-extended-command' was entered.
Non-nil until the recorder consumes it.  The depth tells the M-x
command apart from the minibuffer commands that run one level deeper
while the command name is being typed.")

(defvar my-keybind-stats--flush-timer nil)

(defvar my-keybind-stats--snapshotted-modes nil
  "Major modes whose local keymap was written during this session.")

;;; Recording.

(defun my-keybind-stats--via-m-x-p ()
  "Return non-nil when the command that just ran was chosen through M-x."
  (and my-keybind-stats--m-x-depth
       (= my-keybind-stats--m-x-depth (recursion-depth))))

(defun my-keybind-stats--prefix-argument-event-p (event in-prefix)
  "Return non-nil when EVENT belongs to a prefix argument.
IN-PREFIX is non-nil once an earlier event started one, which makes a
plain digit or minus part of the argument as well."
  (or (memq (key-binding (vector event))
            '(universal-argument digit-argument negative-argument))
      (and in-prefix
           (characterp event)
           (or (<= ?0 event ?9) (= event ?-)))))

(defun my-keybind-stats--strip-prefix-argument (keys)
  "Return KEYS without the leading C-u, M-digit, or digit events.
`this-command-keys-vector' includes the keys that produced the prefix
argument, which would otherwise split \"C-f\" and \"C-u C-f\" into
separate rows."
  (let ((index 0)
        (in-prefix nil))
    (while (and (< index (length keys))
                (my-keybind-stats--prefix-argument-event-p (aref keys index)
                                                           in-prefix))
      (setq in-prefix t)
      (setq index (1+ index)))
    (substring keys index)))

(defun my-keybind-stats--describe-keys (keys)
  "Return `key-description' of KEYS with raw bytes written as octal escapes.
A raw-byte event comes out of `key-description' as a raw-byte character,
which JSON cannot carry and which makes saving the log prompt for a
coding system.  Such an event becomes text like \\302 instead."
  (mapconcat (lambda (char)
               (if (>= char #x3fff80)
                   (format "\\%o" (logand char #xff))
                 (string char)))
             (key-description keys)
             ""))

(defun my-keybind-stats--first-binding (command)
  "Return the description of the first key bound to COMMAND, or nil."
  (let ((keys (where-is-internal command nil t)))
    (and keys (my-keybind-stats--describe-keys keys))))

(defun my-keybind-stats--event-key ()
  "Return the counter key for the command that just ran, or nil to skip it."
  (let ((command real-this-command)
        (via-m-x (my-keybind-stats--via-m-x-p)))
    (when (and (symbolp command)
               command
               (not (memq command my-keybind-stats-ignored-commands)))
      (let ((keys (if via-m-x
                      "M-x"
                    (my-keybind-stats--describe-keys
                     (my-keybind-stats--strip-prefix-argument
                      (this-command-keys-vector))))))
        (unless (string-empty-p keys)
          (list (symbol-name command)
                keys
                (symbol-name major-mode)
                via-m-x
                (and via-m-x (my-keybind-stats--first-binding command))))))))

(defun my-keybind-stats--record-command ()
  "Count the command that just ran.  Runs on `post-command-hook'."
  (condition-case nil
      (let ((key (my-keybind-stats--event-key)))
        (when key
          (puthash key (1+ (gethash key my-keybind-stats--counts 0))
                   my-keybind-stats--counts))
        (my-keybind-stats--snapshot-local-map-once))
    (error nil))
  ;; Consume the flag even when the M-x command was skipped, so it never
  ;; leaks onto the next command.
  (when (my-keybind-stats--via-m-x-p)
    (setq my-keybind-stats--m-x-depth nil)))

(defun my-keybind-stats--note-m-x (orig-fun &rest args)
  "Advice for `execute-extended-command' that flags the chosen command.
ORIG-FUN and ARGS are the advised function and its arguments.  A quit
while typing the command name clears the flag again, otherwise the next
key-driven command would be reported as an M-x invocation."
  (setq my-keybind-stats--m-x-depth (recursion-depth))
  (condition-case err
      (apply orig-fun args)
    (quit
     (setq my-keybind-stats--m-x-depth nil)
     (signal (car err) (cdr err)))))

;;; Writing.

(defun my-keybind-stats--timestamp ()
  "Return the current time as an ISO 8601 string with a numeric zone."
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))

(defun my-keybind-stats--serialize (plist)
  "Return PLIST as one line of JSON text.
Emacs 30 `json-serialize' returns UTF-8 bytes.  Inserted into a
multibyte buffer, the bytes of a key such as C-\u00a5 become raw-byte
characters, and saving the buffer then prompts for a coding system.
Decode the bytes so the text carries the characters themselves."
  (let ((json (json-serialize plist)))
    (if (multibyte-string-p json)
        json
      (decode-coding-string json 'utf-8))))

(defun my-keybind-stats--serialize-event (key count timestamp)
  "Return one JSON line for the counter KEY seen COUNT times at TIMESTAMP."
  (pcase-let ((`(,command ,keys ,mode ,via-m-x ,bound) key))
    (my-keybind-stats--serialize (list :ts timestamp
                          :command command
                          :keys keys
                          :mode mode
                          :mx (if via-m-x t :false)
                          :bound (or bound :null)
                          :count count))))

(defun my-keybind-stats--event-file ()
  "Return the event log file for the current month."
  (expand-file-name (format-time-string "events-%Y-%m.jsonl")
                    my-keybind-stats-directory))

(defun my-keybind-stats--append-lines (file lines)
  "Append LINES to FILE, creating the parent directory when missing."
  (when lines
    (make-directory (file-name-directory file) t)
    (with-temp-buffer
      (dolist (line lines)
        (insert line "\n"))
      (let ((coding-system-for-write 'utf-8))
        (append-to-file (point-min) (point-max) file)))))

(defun my-keybind-stats-flush ()
  "Write the pending counters to the event log and reset them."
  (interactive)
  (let ((timestamp (my-keybind-stats--timestamp))
        (lines '()))
    (maphash (lambda (key count)
               (push (my-keybind-stats--serialize-event key count timestamp)
                     lines))
             my-keybind-stats--counts)
    (clrhash my-keybind-stats--counts)
    (my-keybind-stats--append-lines (my-keybind-stats--event-file)
                                    (nreverse lines))))

;;; Binding snapshots.

(defun my-keybind-stats--binding-target (definition)
  "Return the command or keymap behind DEFINITION, unwrapping menu items."
  (pcase definition
    (`(menu-item ,_ ,target . ,_) target)
    (`(,(pred stringp) . ,target) (my-keybind-stats--binding-target target))
    (_ definition)))

(defun my-keybind-stats--collect-bindings (keymap &optional prefix depth)
  "Return an alist of (KEY-DESCRIPTION . COMMAND-NAME) for KEYMAP.
PREFIX is the key vector that leads to KEYMAP.  DEPTH bounds the
recursion, because a keymap can reach itself through a symbol."
  (let ((bindings '())
        (depth (or depth 0)))
    (when (< depth 8)
      (map-keymap
       (lambda (event definition)
         (unless (consp event)
           (let ((keys (vconcat prefix (vector event)))
                 (target (my-keybind-stats--binding-target definition)))
             (cond
              ((keymapp target)
               (setq bindings
                     (nconc (my-keybind-stats--collect-bindings target keys
                                                                (1+ depth))
                            bindings)))
              ((and target (symbolp target) (commandp target))
               (push (cons (my-keybind-stats--describe-keys keys)
                           (symbol-name target))
                     bindings))))))
       keymap))
    bindings))

(defun my-keybind-stats-snapshot-bindings (scope keymap)
  "Write every command bound in KEYMAP to bindings/SCOPE.jsonl.
SCOPE is \"global\" or a major mode name.  The file is replaced, so it
always describes the bindings of the most recent session."
  (let ((file (expand-file-name (format "bindings/%s.jsonl" scope)
                                my-keybind-stats-directory))
        (timestamp (my-keybind-stats--timestamp)))
    (make-directory (file-name-directory file) t)
    ;; Name the coding system so that `write-region' never asks for one.
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file file
        (dolist (binding (my-keybind-stats--collect-bindings keymap))
        (insert (my-keybind-stats--serialize (list :ts timestamp
                                                   :scope scope
                                                   :keys (car binding)
                                                   :command (cdr binding)))
                  "\n"))))))

(defun my-keybind-stats--snapshot-local-map-once ()
  "Write the local keymap of the current major mode on its first use."
  (unless (or (memq major-mode my-keybind-stats--snapshotted-modes)
              (null (current-local-map)))
    (push major-mode my-keybind-stats--snapshotted-modes)
    (my-keybind-stats-snapshot-bindings (symbol-name major-mode)
                                        (current-local-map))))

(defun my-keybind-stats-snapshot-global-map ()
  "Write the global keymap to bindings/global.jsonl."
  (interactive)
  (my-keybind-stats-snapshot-bindings "global" (current-global-map)))

;;; Report.

(defun my-keybind-stats--run-script (args)
  "Run the report script with ARGS and return its standard output.
Signal an error with the script output when the script fails."
  (with-temp-buffer
    (let ((status (apply #'call-process my-keybind-stats-python-program nil t nil
                         my-keybind-stats--script-file
                         "--dir" my-keybind-stats-directory
                         args)))
      (unless (eq status 0)
        (error "keybind_stats.py failed (%s): %s" status (buffer-string)))
      (buffer-string))))

(defun my-keybind-stats--show-text-report ()
  "Show the plain-text report in the *keybind-stats* buffer."
  (let ((output (my-keybind-stats--run-script nil)))
    (with-current-buffer (get-buffer-create "*keybind-stats*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert output))
      (special-mode)
      (goto-char (point-min))
      (pop-to-buffer (current-buffer)))))

(defun my-keybind-stats--open-html-report ()
  "Write the HTML report next to the log and open it in the browser."
  (let ((file (expand-file-name "report.html" my-keybind-stats-directory)))
    (my-keybind-stats--run-script (list "--html" file))
    (browse-url (concat "file://" file))))

;;;###autoload
(defun my-keybind-stats-report (&optional as-text)
  "Flush the counters and open the usage report in the browser.
With prefix argument AS-TEXT, show the plain-text report in a buffer."
  (interactive "P")
  (my-keybind-stats-flush)
  (if as-text
      (my-keybind-stats--show-text-report)
    (my-keybind-stats--open-html-report)))

;;; Minor mode.

(defun my-keybind-stats--start ()
  "Install the hook, the M-x advice, and the flush timer."
  (add-hook 'post-command-hook #'my-keybind-stats--record-command)
  (add-hook 'kill-emacs-hook #'my-keybind-stats-flush)
  (advice-add 'execute-extended-command :around #'my-keybind-stats--note-m-x)
  (setq my-keybind-stats--flush-timer
        (run-with-timer my-keybind-stats-flush-interval
                        my-keybind-stats-flush-interval
                        #'my-keybind-stats-flush))
  ;; Snapshot after startup so that every init file has installed its keys.
  (if after-init-time
      (my-keybind-stats-snapshot-global-map)
    (add-hook 'emacs-startup-hook #'my-keybind-stats-snapshot-global-map)))

(defun my-keybind-stats--stop ()
  "Remove the hook, the M-x advice, and the flush timer."
  (remove-hook 'post-command-hook #'my-keybind-stats--record-command)
  (remove-hook 'kill-emacs-hook #'my-keybind-stats-flush)
  (remove-hook 'emacs-startup-hook #'my-keybind-stats-snapshot-global-map)
  (advice-remove 'execute-extended-command #'my-keybind-stats--note-m-x)
  (when my-keybind-stats--flush-timer
    (cancel-timer my-keybind-stats--flush-timer)
    (setq my-keybind-stats--flush-timer nil))
  (my-keybind-stats-flush))

;;;###autoload
(define-minor-mode my-keybind-stats-mode
  "Record every command and the keys that ran it."
  :global t
  :lighter ""
  (if my-keybind-stats-mode
      (my-keybind-stats--start)
    (my-keybind-stats--stop)))

(provide 'my-keybind-stats)
;;; my-keybind-stats.el ends here
