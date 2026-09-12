;;; my-keybind-stats-test.el --- Tests for the keybinding usage logger -*- lexical-binding: t; -*-

;;; Commentary:
;; The logger sits on `post-command-hook', so the tests feed it synthetic
;; command-loop state instead of real key presses: they bind
;; `real-this-command' and stub `this-command-keys-vector', then check the
;; rows the logger writes.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-keybind-stats-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'my-keybind-stats)

(defmacro my-keybind-stats-test--with-directory (&rest body)
  "Run BODY with an empty temporary stats directory and a fresh counter table."
  (declare (indent 0))
  `(let ((my-keybind-stats-directory (make-temp-file "keybind-stats-" t))
         (my-keybind-stats--counts (make-hash-table :test #'equal))
         (my-keybind-stats--m-x-depth nil))
     (unwind-protect
         (progn ,@body)
       (delete-directory my-keybind-stats-directory t))))

(defun my-keybind-stats-test--read-rows (file)
  "Return the JSON objects in FILE, one per line, as alists."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((rows '()))
      (goto-char (point-min))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (unless (string-empty-p line)
            (push (json-parse-string line :object-type 'alist :null-object nil
                                     :false-object nil)
                  rows)))
        (forward-line 1))
      (nreverse rows))))

(defun my-keybind-stats-test--simulate (command keys &optional mode)
  "Run the post-command recorder as if COMMAND had just run from KEYS.
KEYS is a string for `kbd'.  MODE is the major mode symbol to report."
  (let ((real-this-command command)
        (this-command command)
        (major-mode (or mode 'fundamental-mode)))
    (cl-letf (((symbol-function 'this-command-keys-vector)
               (lambda () (kbd keys))))
      (my-keybind-stats--record-command))))

(defun my-keybind-stats-test--event-rows ()
  "Return every row written to the event log, flushing first."
  (my-keybind-stats-flush)
  (let ((files (directory-files my-keybind-stats-directory t "^events-.*\\.jsonl$")))
    (apply #'append (mapcar #'my-keybind-stats-test--read-rows files))))

;;; Recording commands.

(ert-deftest my-keybind-stats-should-record-command-and-keys ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "C-f" 'python-mode)
    (let ((row (car (my-keybind-stats-test--event-rows))))
      (should (equal (alist-get 'command row) "forward-char"))
      (should (equal (alist-get 'keys row) "C-f"))
      (should (equal (alist-get 'mode row) "python-mode"))
      (should (equal (alist-get 'count row) 1)))))

(ert-deftest my-keybind-stats-should-aggregate-repeated-commands ()
  (my-keybind-stats-test--with-directory
    (dotimes (_ 3)
      (my-keybind-stats-test--simulate 'forward-char "C-f"))
    (let ((rows (my-keybind-stats-test--event-rows)))
      (should (equal (length rows) 1))
      (should (equal (alist-get 'count (car rows)) 3)))))

(ert-deftest my-keybind-stats-should-keep-different-keys-apart ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "C-f")
    (my-keybind-stats-test--simulate 'forward-char "<right>")
    (should (equal (length (my-keybind-stats-test--event-rows)) 2))))

(ert-deftest my-keybind-stats-should-skip-ignored-commands ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'self-insert-command "a")
    (should-not (my-keybind-stats-test--event-rows))))

(ert-deftest my-keybind-stats-should-skip-non-symbol-commands ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate (lambda () (interactive)) "C-f")
    (should-not (my-keybind-stats-test--event-rows))))

(ert-deftest my-keybind-stats-should-skip-commands-without-keys ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "")
    (should-not (my-keybind-stats-test--event-rows))))

(ert-deftest my-keybind-stats-should-strip-universal-argument-prefix ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "C-u 5 C-f")
    (should (equal (alist-get 'keys (car (my-keybind-stats-test--event-rows)))
                   "C-f"))))

(ert-deftest my-keybind-stats-should-strip-digit-argument-prefix ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "M-5 C-f")
    (should (equal (alist-get 'keys (car (my-keybind-stats-test--event-rows)))
                   "C-f"))))

(ert-deftest my-keybind-stats-should-mark-m-x-invocations ()
  (my-keybind-stats-test--with-directory
    (setq my-keybind-stats--m-x-depth (recursion-depth))
    (my-keybind-stats-test--simulate 'forward-char "M-x f o r w a r d RET")
    (let ((row (car (my-keybind-stats-test--event-rows))))
      (should (equal (alist-get 'mx row) t))
      (should (equal (alist-get 'keys row) "M-x")))))

(ert-deftest my-keybind-stats-should-report-existing-binding-for-m-x-command ()
  (my-keybind-stats-test--with-directory
    (setq my-keybind-stats--m-x-depth (recursion-depth))
    (my-keybind-stats-test--simulate 'forward-char "M-x")
    (should (equal (alist-get 'bound (car (my-keybind-stats-test--event-rows)))
                   "C-f"))))

(ert-deftest my-keybind-stats-should-report-no-binding-for-unbound-m-x-command ()
  (my-keybind-stats-test--with-directory
    (setq my-keybind-stats--m-x-depth (recursion-depth))
    (my-keybind-stats-test--simulate 'my-keybind-stats-test--unbound "M-x")
    (should-not (alist-get 'bound (car (my-keybind-stats-test--event-rows))))))

(defun my-keybind-stats-test--unbound ()
  "Command with no key binding, for the M-x tests."
  (interactive))

(ert-deftest my-keybind-stats-should-clear-m-x-flag-after-recording ()
  (my-keybind-stats-test--with-directory
    (setq my-keybind-stats--m-x-depth (recursion-depth))
    (my-keybind-stats-test--simulate 'forward-char "M-x")
    (my-keybind-stats-test--simulate 'forward-char "C-f")
    (let ((rows (my-keybind-stats-test--event-rows)))
      (should (equal (length rows) 2))
      (should (equal (cl-count-if (lambda (row) (alist-get 'mx row)) rows) 1)))))

(ert-deftest my-keybind-stats-should-not-mark-deeper-recursion-as-m-x ()
  ;; Minibuffer commands during M-x run one recursion level deeper.
  (my-keybind-stats-test--with-directory
    (setq my-keybind-stats--m-x-depth (1- (recursion-depth)))
    (my-keybind-stats-test--simulate 'vertico-next "C-s")
    (let ((row (car (my-keybind-stats-test--event-rows))))
      (should-not (alist-get 'mx row))
      (should (equal (alist-get 'keys row) "C-s")))))

(ert-deftest my-keybind-stats-should-set-m-x-flag-from-advice ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats--note-m-x (lambda (&rest _) nil))
    (should (equal my-keybind-stats--m-x-depth (recursion-depth)))))

(ert-deftest my-keybind-stats-should-clear-m-x-flag-when-m-x-quits ()
  (my-keybind-stats-test--with-directory
    ;; `quit' is not an `error', so `should-error' cannot catch it.
    (should (eq (condition-case nil
                    (my-keybind-stats--note-m-x
                     (lambda (&rest _) (signal 'quit nil)))
                  (quit 'quit))
                'quit))
    (should-not my-keybind-stats--m-x-depth)))

(ert-deftest my-keybind-stats-should-survive-errors-in-the-recorder ()
  (my-keybind-stats-test--with-directory
    (cl-letf (((symbol-function 'this-command-keys-vector)
               (lambda () (error "Boom"))))
      (let ((real-this-command 'forward-char))
        (my-keybind-stats--record-command)))
    (should-not (my-keybind-stats-test--event-rows))))

;;; Flushing.

(ert-deftest my-keybind-stats-should-write-nothing-when-no-events ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-flush)
    (should-not (directory-files my-keybind-stats-directory nil "\\.jsonl$"))))

(ert-deftest my-keybind-stats-should-clear-counts-after-flush ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "C-f")
    (my-keybind-stats-flush)
    (should (equal (hash-table-count my-keybind-stats--counts) 0))))

(ert-deftest my-keybind-stats-should-append-across-flushes ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "C-f")
    (my-keybind-stats-flush)
    (my-keybind-stats-test--simulate 'backward-char "C-b")
    (should (equal (length (my-keybind-stats-test--event-rows)) 2))))

(ert-deftest my-keybind-stats-should-stamp-rows-with-iso-timestamp ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "C-f")
    (should (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9:]\\{8\\}[+-][0-9]\\{4\\}\\'"
                            (alist-get 'ts (car (my-keybind-stats-test--event-rows)))))))

;;; Binding snapshots.

(ert-deftest my-keybind-stats-collect-bindings-should-list-simple-bindings ()
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c a") #'forward-char)
    (should (equal (my-keybind-stats--collect-bindings map)
                   '(("C-c a" . "forward-char"))))))

(ert-deftest my-keybind-stats-collect-bindings-should-describe-meta-keys ()
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "M-g") #'goto-line)
    (should (equal (my-keybind-stats--collect-bindings map)
                   '(("M-g" . "goto-line"))))))

(ert-deftest my-keybind-stats-collect-bindings-should-unwrap-menu-items ()
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c b") '(menu-item "Back" backward-char))
    (define-key map (kbd "C-c c") '("Forward" . forward-char))
    (should (equal (sort (my-keybind-stats--collect-bindings map)
                         (lambda (a b) (string< (car a) (car b))))
                   '(("C-c b" . "backward-char") ("C-c c" . "forward-char"))))))

(ert-deftest my-keybind-stats-collect-bindings-should-skip-non-commands ()
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c a") 'my-keybind-stats-test--not-a-command)
    (define-key map (kbd "C-c b") "macro")
    (should-not (my-keybind-stats--collect-bindings map))))

(ert-deftest my-keybind-stats-collect-bindings-should-follow-parent-keymaps ()
  (let ((parent (make-sparse-keymap))
        (child (make-sparse-keymap)))
    (define-key parent (kbd "C-c p") #'forward-char)
    (set-keymap-parent child parent)
    (should (equal (my-keybind-stats--collect-bindings child)
                   '(("C-c p" . "forward-char"))))))

(ert-deftest my-keybind-stats-snapshot-should-write-one-row-per-binding ()
  (my-keybind-stats-test--with-directory
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "C-c a") #'forward-char)
      (define-key map (kbd "C-c b") #'backward-char)
      (my-keybind-stats-snapshot-bindings "python-mode" map)
      (let ((rows (my-keybind-stats-test--read-rows
                   (expand-file-name "bindings/python-mode.jsonl"
                                     my-keybind-stats-directory))))
        (should (equal (length rows) 2))
        (should (equal (alist-get 'scope (car rows)) "python-mode"))
        (should (member (alist-get 'keys (car rows)) '("C-c a" "C-c b")))))))

(ert-deftest my-keybind-stats-snapshot-should-overwrite-previous-snapshot ()
  (my-keybind-stats-test--with-directory
    (let ((map (make-sparse-keymap)))
      (define-key map (kbd "C-c a") #'forward-char)
      (my-keybind-stats-snapshot-bindings "global" map)
      (my-keybind-stats-snapshot-bindings "global" map)
      (should (equal (length (my-keybind-stats-test--read-rows
                              (expand-file-name "bindings/global.jsonl"
                                                my-keybind-stats-directory)))
                     1)))))

(defun my-keybind-stats-test--refuse-coding-prompt (&rest _)
  "Stand in for `select-safe-coding-system' and fail instead of prompting."
  (error "Coding system prompt"))

(ert-deftest my-keybind-stats-collect-bindings-should-escape-raw-byte-keys ()
  ;; `key-description' keeps raw-byte events as raw-byte characters, which
  ;; no JSON serializer or file coding system accepts.
  (let ((map (make-sparse-keymap)))
    (define-key map (vector #x3fffc2 #x3fffa5) #'forward-char)
    (should (equal (my-keybind-stats--collect-bindings map)
                   '(("\\302 \\245" . "forward-char"))))))

(ert-deftest my-keybind-stats-snapshot-should-not-prompt-for-a-coding-system ()
  (my-keybind-stats-test--with-directory
    (let ((map (make-sparse-keymap))
          (coding-system-for-write nil)
          (select-safe-coding-system-function
           #'my-keybind-stats-test--refuse-coding-prompt))
      (define-key map (vector #x3fffc2) #'forward-char)
      (define-key map (vector ?\u00a5) #'backward-char)
      (my-keybind-stats-snapshot-bindings "global" map)
      (should (equal (sort (mapcar (lambda (row) (alist-get 'keys row))
                                   (my-keybind-stats-test--read-rows
                                    (expand-file-name "bindings/global.jsonl"
                                                      my-keybind-stats-directory)))
                           #'string<)
                     '("\\302" "\u00a5"))))))

(ert-deftest my-keybind-stats-should-escape-raw-byte-keys-in-events ()
  (my-keybind-stats-test--with-directory
    (let ((real-this-command 'forward-char)
          (this-command 'forward-char))
      (cl-letf (((symbol-function 'this-command-keys-vector)
                 (lambda () (vector #x3fffc2))))
        (my-keybind-stats--record-command)))
    (should (equal (alist-get 'keys (car (my-keybind-stats-test--event-rows)))
                   "\\302"))))

(defmacro my-keybind-stats-test--with-unibyte-json (&rest body)
  "Run BODY with `json-serialize' returning UTF-8 bytes, as Emacs 30 does."
  (declare (indent 0))
  `(let ((original (symbol-function 'json-serialize)))
     (cl-letf (((symbol-function 'json-serialize)
                (lambda (&rest args)
                  (encode-coding-string (apply original args) 'utf-8))))
       ,@body)))

(defun my-keybind-stats-test--raw-byte-free-p (string)
  "Return non-nil when STRING is multibyte text without raw-byte characters."
  (and (multibyte-string-p string)
       (not (string-match-p "[\x3fff80-\x3fffff]" string))))

(ert-deftest my-keybind-stats-serialize-should-decode-unibyte-json ()
  ;; Emacs 30 `json-serialize' returns UTF-8 bytes. Inserted as-is into a
  ;; multibyte buffer they become raw bytes, which no coding system encodes
  ;; without asking.
  (my-keybind-stats-test--with-unibyte-json
    (let ((line (my-keybind-stats--serialize (list :keys "\u00a5"))))
      (should (my-keybind-stats-test--raw-byte-free-p line))
      (should (string-search "\u00a5" line)))))

(ert-deftest my-keybind-stats-serialize-should-accept-multibyte-json ()
  (let ((line (my-keybind-stats--serialize (list :keys "\u00a5"))))
    (should (my-keybind-stats-test--raw-byte-free-p line))
    (should (string-search "\u00a5" line))))

(ert-deftest my-keybind-stats-should-write-non-ascii-keys-as-utf-8 ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--with-unibyte-json
      (let ((coding-system-for-write nil)
            (select-safe-coding-system-function
             #'my-keybind-stats-test--refuse-coding-prompt))
        (my-keybind-stats-test--simulate 'forward-char "\u00a5")
        (should (equal (alist-get 'keys (car (my-keybind-stats-test--event-rows)))
                       "\u00a5"))))))

(ert-deftest my-keybind-stats-should-snapshot-a-mode-once-per-session ()
  (my-keybind-stats-test--with-directory
    (let ((my-keybind-stats--snapshotted-modes nil)
          (snapshots 0))
      (cl-letf (((symbol-function 'my-keybind-stats-snapshot-bindings)
                 (lambda (&rest _) (cl-incf snapshots))))
        (with-temp-buffer
          (use-local-map (make-sparse-keymap))
          (let ((major-mode 'python-mode))
            (my-keybind-stats--snapshot-local-map-once)
            (my-keybind-stats--snapshot-local-map-once))))
      (should (equal snapshots 1)))))

;;; Report.

(defmacro my-keybind-stats-test--with-script-stub (status output &rest body)
  "Run BODY with the report script stubbed to exit with STATUS printing OUTPUT.
BODY can read the script arguments in `script-args' and the URL passed
to `browse-url' in `opened-url'."
  (declare (indent 2))
  `(let ((script-args nil)
         (opened-url nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (_program _infile _destination _display &rest args)
                  (setq script-args args)
                  (insert ,output)
                  ,status))
               ((symbol-function 'browse-url)
                (lambda (url &rest _) (setq opened-url url)))
               ((symbol-function 'pop-to-buffer)
                (lambda (&rest _) nil)))
       ,@body)))

(ert-deftest my-keybind-stats-report-should-open-the-html-report ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--with-script-stub 0 ""
      (my-keybind-stats-report)
      (should (member "--html" script-args))
      (should (string-prefix-p "file://" opened-url))
      (should (string-suffix-p "report.html" opened-url)))))

(ert-deftest my-keybind-stats-report-should-pass-the-stats-directory ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--with-script-stub 0 ""
      (my-keybind-stats-report)
      (should (member my-keybind-stats-directory script-args)))))

(ert-deftest my-keybind-stats-report-should-show-text-in-a-buffer ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--with-script-stub 0 "# Emacs keybinding stats"
      (my-keybind-stats-report '(4))
      (should-not opened-url)
      (with-current-buffer "*keybind-stats*"
        (should (string-prefix-p "# Emacs keybinding stats" (buffer-string)))))))

(ert-deftest my-keybind-stats-report-should-flush-before-running-the-script ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--simulate 'forward-char "C-f")
    (my-keybind-stats-test--with-script-stub 0 ""
      (my-keybind-stats-report)
      (should (equal (hash-table-count my-keybind-stats--counts) 0)))))

(ert-deftest my-keybind-stats-report-should-signal-when-the-script-fails ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-test--with-script-stub 1 "Traceback"
      (should-error (my-keybind-stats-report)))))

;;; Minor mode.

(ert-deftest my-keybind-stats-mode-should-install-and-remove-the-hook ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-mode 1)
    (unwind-protect
        (should (memq #'my-keybind-stats--record-command post-command-hook))
      (my-keybind-stats-mode -1))
    (should-not (memq #'my-keybind-stats--record-command post-command-hook))))

(ert-deftest my-keybind-stats-mode-should-remove-the-m-x-advice-when-disabled ()
  (my-keybind-stats-test--with-directory
    (my-keybind-stats-mode 1)
    (my-keybind-stats-mode -1)
    (should-not (advice-member-p #'my-keybind-stats--note-m-x
                                 'execute-extended-command))))

(provide 'my-keybind-stats-test)
;;; my-keybind-stats-test.el ends here
