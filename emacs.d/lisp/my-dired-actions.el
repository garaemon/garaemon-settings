;;; my-dired-actions.el --- Run per-extension actions on dired files -*- lexical-binding: t; -*-

;;; Commentary:
;; A context menu for dired, keyed by file extension.  Register an action
;; with `my-dired-actions-add', then pick it with `my-dired-actions-dispatch'
;; (keyboard) or `my-dired-actions-mouse-menu' (right click).  Both
;; choose through `completing-read', so Vertico and Orderless narrow the
;; list.  Only the actions whose extensions match every target file appear.
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

(cl-defstruct (my-dired-action (:constructor my-dired-action-create))
  "An entry of the dired context menu."
  (name nil :documentation "Label shown in the menu; unique key.")
  (extensions nil :documentation "Lowercase extensions, or t for any file.")
  (command nil :documentation "Shell template string, or a function of FILES."))

(defvar my-dired-actions nil
  "Registered `my-dired-action' entries, in menu order.")

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

(defun my-dired-actions--applicable-or-error (files)
  "Return the actions for FILES, or signal `user-error' when there is none."
  (or (my-dired-actions-for-files files)
      (user-error "No dired action for %s"
                  (mapconcat #'file-name-nondirectory files ", "))))

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
  (let ((names (mapcar #'my-dired-action-name actions)))
    (lambda (string predicate completion-action)
      (if (eq completion-action 'metadata)
          '(metadata (category . my-dired-action)
                     (annotation-function . my-dired-actions--annotate))
        (complete-with-action completion-action names string predicate)))))

(defun my-dired-actions--choose-and-run (files)
  "Narrow the actions for FILES with `completing-read' and run the choice."
  (let* ((actions (my-dired-actions--applicable-or-error files))
         (chosen-name (completing-read
                       "Action: " (my-dired-actions--completion-table actions)
                       nil t)))
    (my-dired-actions-run
     (cl-find chosen-name actions :key #'my-dired-action-name :test #'equal)
     files)))

;;;###autoload
(defun my-dired-actions-dispatch ()
  "Choose and run an action for the marked files, or the file at point."
  (interactive)
  (my-dired-actions--choose-and-run (dired-get-marked-files)))

;;;###autoload
(defun my-dired-actions-mouse-menu (event)
  "Choose and run an action for the file under the mouse EVENT.
The choice goes through `completing-read' rather than a popup menu, so
Vertico and Orderless narrow the actions as in `my-dired-actions-dispatch'."
  (interactive "e")
  (mouse-set-point event)
  (my-dired-actions--choose-and-run (dired-get-marked-files)))

(provide 'my-dired-actions)

;;; my-dired-actions.el ends here
