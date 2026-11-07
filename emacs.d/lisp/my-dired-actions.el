;;; my-dired-actions.el --- Run per-extension actions on dired files -*- lexical-binding: t; -*-

;;; Commentary:
;; A context menu for dired, keyed by file extension.
;; `my-dired-actions-dispatch' lists the actions whose extensions match
;; every target file, through `completing-read' so Vertico and Orderless
;; narrow the list.  Register an action from the init files:
;;
;;   (my-dired-actions-add '("mp4" "mov") "Change speed"
;;     (concat "ffmpeg -i %i -vf setpts=PTS/%{Speed:2} -af atempo=%{Speed:2}"
;;             " %d/%b-%{Speed:2}x.%e"))
;;
;; A string command is a shell template, expanded once per file and run
;; as one "&&" chain, so a failing file stops the files after it:
;;
;; - %i: the absolute path of the file.
;; - %d: the directory of the file, without the trailing slash.
;; - %b: the file name without the directory and the extension.
;; - %e: the extension, without the dot.
;; - %%: a literal percent sign.
;; - %{PROMPT:DEFAULT}: a value typed after the action is chosen, such as
;;   %{Speed:2}.  The same PROMPT is asked once, and ":DEFAULT" is optional.
;;
;; Every placeholder expands shell-quoted, so names with spaces are safe.
;; A function command receives the list of absolute file paths instead.

;;; Code:

(require 'cl-lib)
(require 'dired)
(require 'format-spec)
(require 'subr-x)

(cl-defstruct (my-dired-action (:constructor my-dired-action-create))
  "An entry of the dired context menu."
  (name nil :documentation "Label shown in the menu; unique key.")
  (extensions nil :documentation
              "Lowercase extensions, t for anything, or `file' for non-dirs.")
  (command nil :documentation "Shell template string, or a function of FILES."))

(defvar my-dired-actions nil
  "Registered `my-dired-action' entries, in menu order.")

(defconst my-dired-actions-output-buffer-name "*Dired Action*"
  "Buffer that receives the output of shell actions.")

(defun my-dired-actions-add (extensions name command)
  "Register an action NAME that runs COMMAND on files with EXTENSIONS.
EXTENSIONS is a list of extension strings without the dot, t to match
every entry, or the symbol `file' to match every entry but a directory.
COMMAND is a shell template (see the commentary) or a function that takes
the list of files.  A second call with the same NAME replaces the earlier
action."
  (let ((new-action (my-dired-action-create
                     :name name
                     :extensions (if (memq extensions '(t file)) extensions
                                   (mapcar #'downcase extensions))
                     :command command)))
    (setq my-dired-actions
          (append (cl-remove name my-dired-actions
                             :key #'my-dired-action-name :test #'equal)
                  (list new-action)))))

(defun my-dired-actions--matches-file-p (action file)
  "Return non-nil when ACTION applies to FILE."
  (let ((extensions (my-dired-action-extensions action))
        (file-extension (file-name-extension file)))
    (or (eq extensions t)
        (and (eq extensions 'file) (not (file-directory-p file)))
        (and (listp extensions)
             file-extension
             (member (downcase file-extension) extensions)))))

(defun my-dired-actions-find-for-files (files)
  "Return the registered actions that apply to every file in FILES."
  (cl-remove-if-not
   (lambda (action)
     (cl-every (lambda (file) (my-dired-actions--matches-file-p action file))
               files))
   my-dired-actions))

(defun my-dired-actions-expand-command (template file)
  "Return TEMPLATE with its placeholders replaced by parts of FILE.
A remote FILE expands to its path on the remote host, where the command
runs."
  (let ((absolute-file (file-local-name (expand-file-name file))))
    (format-spec template
                 `((?i . ,(shell-quote-argument absolute-file))
                   (?d . ,(shell-quote-argument
                           (directory-file-name
                            (file-name-directory absolute-file))))
                   (?b . ,(shell-quote-argument
                           (file-name-base absolute-file)))
                   (?e . ,(shell-quote-argument
                           (or (file-name-extension absolute-file) "")))))))

(defun my-dired-actions--make-shell-command-line (command)
  "Return the argument list that runs shell COMMAND in `default-directory'.
A remote directory picks the shell of its TRAMP connection, such as
/bin/sh, instead of the local `shell-file-name'."
  (with-connection-local-variables
   (list shell-file-name shell-command-switch command)))

(defun my-dired-actions--run-shell-command (command action-name dired-buffer)
  "Run shell COMMAND asynchronously and revert DIRED-BUFFER when it ends.
ACTION-NAME labels the message shown when the process ends.  Return the
process, whose standard input is already closed."
  (let ((output-buffer (get-buffer-create my-dired-actions-output-buffer-name)))
    (with-current-buffer output-buffer
      (goto-char (point-max))
      (insert (format "$ %s\n" command)))
    (display-buffer output-buffer)
    ;; `:file-handler' runs the command on the TRAMP host of
    ;; `default-directory', which is the remote directory in a remote dired.
    (let ((process
           (make-process
            :name "dired-action"
            :buffer output-buffer
            :connection-type 'pipe
            :file-handler t
            :command (my-dired-actions--make-shell-command-line command)
            :sentinel
            (lambda (process event)
              (when (memq (process-status process) '(exit signal))
                (message "Dired action %s: %s" action-name (string-trim event))
                (when (buffer-live-p dired-buffer)
                  (with-current-buffer dired-buffer
                    (revert-buffer))))))))
      ;; Close stdin so that a prompt, such as ffmpeg asking to overwrite an
      ;; existing output, reads EOF and fails instead of waiting forever.
      (process-send-eof process)
      process)))

(defconst my-dired-actions--prompt-regexp
  "%%\\|%{\\([^}:]*\\)\\(?::\\([^}]*\\)\\)?}"
  "Match a literal \"%%\" or a prompt such as \"%{Speed:2}\".
Matching \"%%\" too keeps \"%%{...}\" from being read as a prompt.")

(defun my-dired-actions--collect-prompt-specs (template)
  "Return the (PROMPT . DEFAULT) pairs in TEMPLATE, first occurrence only.
DEFAULT is nil for a prompt written without one, such as \"%{Name}\"."
  (let ((specs nil)
        (start 0))
    (while (string-match my-dired-actions--prompt-regexp template start)
      (let ((prompt (match-string 1 template)))
        (when (and prompt (not (assoc prompt specs)))
          (push (cons prompt (match-string 2 template)) specs)))
      (setq start (match-end 0)))
    (nreverse specs)))

(defun my-dired-actions--fill-prompts (template answers)
  "Return TEMPLATE with each prompt replaced by its value in ANSWERS.
ANSWERS maps a prompt to its typed value.  Each value is shell-quoted,
and its \"%\" doubled so that `format-spec' later keeps it literal."
  (replace-regexp-in-string
   my-dired-actions--prompt-regexp
   (lambda (matched)
     (let ((prompt (match-string 1 matched)))
       (if (null prompt) "%%"
         (string-replace "%" "%%" (shell-quote-argument
                                   (cdr (assoc prompt answers)))))))
   template t t))

(defun my-dired-actions--read-answers (template)
  "Ask for the value of each prompt in TEMPLATE and return the answers."
  (mapcar (lambda (spec)
            (let ((default (cdr spec)))
              (cons (car spec)
                    (read-string (format-prompt (car spec) default)
                                 nil nil default))))
          (my-dired-actions--collect-prompt-specs template)))

(defun my-dired-actions-run (action files)
  "Run ACTION on FILES.
A shell template asks its prompts once, then runs as one process that
handles FILES in turn, so a heavy command such as ffmpeg does not start
once per file in parallel."
  (let ((command (my-dired-action-command action)))
    (if (functionp command)
        (funcall command files)
      (let* ((answers (my-dired-actions--read-answers command))
             (filled-template (my-dired-actions--fill-prompts command answers)))
        (my-dired-actions--run-shell-command
         ;; Group each expansion so that a ";" or "||" in the template
         ;; cannot escape the "&&" chain.
         (mapconcat (lambda (file)
                      (format "(%s)" (my-dired-actions-expand-command
                                      filled-template file)))
                    files " && ")
         (my-dired-action-name action)
         (current-buffer))))))

;; Annotations read the global list because `completing-read' passes only
;; the candidate string; names are unique, so the lookup is unambiguous.
(defun my-dired-actions--annotate (candidate)
  "Return the command of the action named CANDIDATE, for the completion UI."
  (let* ((action (cl-find candidate my-dired-actions
                          :key #'my-dired-action-name :test #'equal))
         (command (and action (my-dired-action-command action))))
    (when command
      (concat "  " (propertize (cond ((stringp command) command)
                                     ((symbolp command) (symbol-name command))
                                     (t "(function)"))
                               'face 'completions-annotations)))))

(defun my-dired-actions--make-completion-table (actions)
  "Return a completion table of ACTIONS names with a category and annotations.
The `my-dired-action' category lets Marginalia and Embark recognize the
candidates, and the annotation shows the command beside each name."
  (let ((names (mapcar #'my-dired-action-name actions)))
    (lambda (string predicate completion-action)
      (if (eq completion-action 'metadata)
          '(metadata (category . my-dired-action)
                     (annotation-function . my-dired-actions--annotate))
        (complete-with-action completion-action names string predicate)))))

(defun my-dired-actions--require-applicable (files)
  "Return the actions for FILES, or signal `user-error' when there is none.
An empty FILES also signals, because every action matches an empty list."
  (unless files
    (user-error "No file at point"))
  (or (my-dired-actions-find-for-files files)
      (user-error "No dired action for %s"
                  (mapconcat #'file-name-nondirectory files ", "))))

;;;###autoload
(defun my-dired-actions-dispatch ()
  "Choose and run an action for the marked files, or the file at point."
  (interactive)
  (let* ((files (dired-get-marked-files))
         (actions (my-dired-actions--require-applicable files))
         (chosen-name (completing-read
                       "Action: "
                       (my-dired-actions--make-completion-table actions)
                       nil t nil nil (my-dired-action-name (car actions)))))
    (my-dired-actions-run
     (cl-find chosen-name actions :key #'my-dired-action-name :test #'equal)
     files)))

(provide 'my-dired-actions)

;;; my-dired-actions.el ends here
