;;; my-dired-actions.el --- Run per-extension actions on dired files -*- lexical-binding: t; -*-

;;; Commentary:
;; A context menu for dired, keyed by file extension.
;; `my-dired-actions-dispatch' lists the actions whose extensions match
;; every target file, through `completing-read' so Vertico and Orderless
;; narrow the list.  The last entry of the list adds a new action.
;;
;; Add an action in one of two ways:
;;
;; - Pick "[Add a new action...]" in the menu, or run `my-dired-actions-new'.
;;   The action goes to `my-dired-actions-file' and loads at startup.
;; - Call `my-dired-actions-add' from the init files:
;;
;;   (my-dired-actions-add '("mp4" "mov") "Speed up 2x"
;;     "ffmpeg -i %i -vf setpts=PTS/2 -af atempo=2 %d/%b-2x.%e")
;;
;; A string command is a shell template that runs once per file:
;;
;; - %i: the absolute path of the file.
;; - %d: the directory of the file, without the trailing slash.
;; - %b: the file name without the directory and the extension.
;; - %e: the extension, without the dot.
;; - %%: a literal percent sign.
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
  (extensions nil :documentation "Lowercase extensions, or t for any file.")
  (command nil :documentation "Shell template string, or a function of FILES."))

(defvar my-dired-actions nil
  "Registered `my-dired-action' entries, in menu order.")

(defvar my-dired-actions-file (locate-user-emacs-file "dired-actions.eld")
  "File that holds the actions added with `my-dired-actions-new'.")

(defconst my-dired-actions-new-candidate "[Add a new action...]"
  "Menu entry that runs `my-dired-actions-new' instead of an action.")

(defconst my-dired-actions-output-buffer-name "*Dired Action*"
  "Buffer that receives the output of shell actions.")

(defun my-dired-actions-add (extensions name command)
  "Register an action NAME that runs COMMAND on files with EXTENSIONS.
EXTENSIONS is a list of extension strings without the dot, or t to match
every file.  COMMAND is a shell template (see the commentary) or a
function that takes the list of files.  A second call with the same NAME
replaces the earlier action."
  (let ((new-action (my-dired-action-create
                     :name name
                     :extensions (if (eq extensions t) t
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
        (and file-extension
             (member (downcase file-extension) extensions)))))

(defun my-dired-actions-for-files (files)
  "Return the registered actions that apply to every file in FILES."
  (cl-remove-if-not
   (lambda (action)
     (cl-every (lambda (file) (my-dired-actions--matches-file-p action file))
               files))
   my-dired-actions))

(defun my-dired-actions-expand-command (template file)
  "Return TEMPLATE with its placeholders replaced by parts of FILE."
  (let ((absolute-file (expand-file-name file)))
    (format-spec template
                 `((?i . ,(shell-quote-argument absolute-file))
                   (?d . ,(shell-quote-argument
                           (directory-file-name
                            (file-name-directory absolute-file))))
                   (?b . ,(shell-quote-argument
                           (file-name-base absolute-file)))
                   (?e . ,(shell-quote-argument
                           (or (file-name-extension absolute-file) "")))))))

(defun my-dired-actions--run-shell-command (command dired-buffer)
  "Run shell COMMAND asynchronously and revert DIRED-BUFFER when it ends."
  (let ((output-buffer (get-buffer-create my-dired-actions-output-buffer-name)))
    (with-current-buffer output-buffer
      (goto-char (point-max))
      (insert (format "$ %s\n" command)))
    (display-buffer output-buffer)
    (make-process
     :name "dired-action"
     :buffer output-buffer
     :command (list shell-file-name shell-command-switch command)
     :sentinel
     (lambda (process event)
       (when (memq (process-status process) '(exit signal))
         (message "Dired action %s: %s" (string-trim event) command)
         (when (buffer-live-p dired-buffer)
           (with-current-buffer dired-buffer
             (revert-buffer))))))))

(defun my-dired-actions-run (action files)
  "Run ACTION on FILES.
A shell template runs as one process that handles FILES in turn, so a heavy
command such as ffmpeg does not start once per file in parallel."
  (let ((command (my-dired-action-command action)))
    (if (functionp command)
        (funcall command files)
      (my-dired-actions--run-shell-command
       (mapconcat (lambda (file) (my-dired-actions-expand-command command file))
                  files " && ")
       (current-buffer)))))

;; Annotations read the global list because `completing-read' passes only
;; the candidate string; names are unique, so the lookup is unambiguous.
(defun my-dired-actions--annotate (candidate)
  "Return the command of the action named CANDIDATE, for the completion UI."
  (let* ((action (cl-find candidate my-dired-actions
                          :key #'my-dired-action-name :test #'equal))
         (command (and action (my-dired-action-command action))))
    (when command
      (concat "  " (propertize (if (stringp command) command "(function)")
                               'face 'completions-annotations)))))

(defun my-dired-actions--completion-table (actions)
  "Return a completion table of ACTIONS names with a category and annotations.
The `my-dired-action' category lets Marginalia and Embark recognize the
candidates, and the annotation shows the command beside each name."
  (let ((names (append (mapcar #'my-dired-action-name actions)
                       (list my-dired-actions-new-candidate))))
    (lambda (string predicate completion-action)
      (if (eq completion-action 'metadata)
          '(metadata (category . my-dired-action)
                     (annotation-function . my-dired-actions--annotate))
        (complete-with-action completion-action names string predicate)))))

(defun my-dired-actions--read-file ()
  "Return the (EXTENSIONS NAME COMMAND) entries in `my-dired-actions-file'."
  (when (file-exists-p my-dired-actions-file)
    (with-temp-buffer
      (insert-file-contents my-dired-actions-file)
      (read (current-buffer)))))

(defun my-dired-actions--write-file (entries)
  "Replace the contents of `my-dired-actions-file' with ENTRIES."
  (with-temp-file my-dired-actions-file
    (insert ";; Dired actions saved by `my-dired-actions-new'.  -*- mode: lisp-data -*-\n")
    (pp entries (current-buffer))))

;;;###autoload
(defun my-dired-actions-load-file ()
  "Register every action saved in `my-dired-actions-file'."
  (dolist (entry (my-dired-actions--read-file))
    (apply #'my-dired-actions-add entry)))

(defun my-dired-actions-save (extensions name command)
  "Register the action NAME and save it to `my-dired-actions-file'.
EXTENSIONS and COMMAND are as in `my-dired-actions-add', except that
COMMAND must be a string so that the file can hold it.  A saved action
with the same NAME is overwritten."
  (my-dired-actions-add extensions name command)
  (my-dired-actions--write-file
   (append (cl-remove name (my-dired-actions--read-file)
                      :key #'cadr :test #'equal)
           (list (list extensions name command)))))

(defun my-dired-actions--parse-extensions (text)
  "Return the extensions typed in TEXT, or t when TEXT is \"*\".
Extensions are separated by spaces or commas; a leading dot is dropped."
  (let ((words (split-string text "[ ,]+" t)))
    (if (equal words '("*")) t
      (mapcar (lambda (word) (downcase (string-remove-prefix "." word)))
              words))))

;;;###autoload
(defun my-dired-actions-new ()
  "Ask for a new action, then register and save it.
The extension prompt starts with the extension of the file at point."
  (interactive)
  (let* ((default-extension
          (or (file-name-extension (car (dired-get-marked-files))) ""))
         (extensions (my-dired-actions--parse-extensions
                      (read-string "Extensions (space separated, * for any): "
                                   (downcase default-extension))))
         (name (read-string "Action name: "))
         (command (read-string
                   "Command (%i path, %d dir, %b base name, %e extension): ")))
    (my-dired-actions-save extensions name command)
    (message "Saved dired action \"%s\" to %s" name my-dired-actions-file)))

;;;###autoload
(defun my-dired-actions-edit-file ()
  "Visit `my-dired-actions-file' to edit or delete saved actions.
Run `my-dired-actions-load-file' after editing to register the changes."
  (interactive)
  (find-file my-dired-actions-file))

;;;###autoload
(defun my-dired-actions-dispatch ()
  "Choose and run an action for the marked files, or the file at point.
The menu also offers `my-dired-actions-new-candidate', which adds an action."
  (interactive)
  (let* ((files (dired-get-marked-files))
         (actions (my-dired-actions-for-files files))
         (chosen-name (completing-read
                       "Action: " (my-dired-actions--completion-table actions)
                       nil t)))
    (if (equal chosen-name my-dired-actions-new-candidate)
        (my-dired-actions-new)
      (my-dired-actions-run
       (cl-find chosen-name actions :key #'my-dired-action-name :test #'equal)
       files))))

(provide 'my-dired-actions)

;;; my-dired-actions.el ends here
