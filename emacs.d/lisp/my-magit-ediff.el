;;; my-magit-ediff.el --- Multi-file ediff for Magit -*- lexical-binding: t; -*-

;;; Commentary:
;; Provides functions to ediff all changed files sequentially.
;; When you quit one ediff session, a navigation prompt lets you go
;; to the next/previous file or quit the review.

;;; Code:

(require 'magit)
(require 'ediff)

;;;; State variables

(defvar my-magit-ediff--files nil
  "All files to ediff.")

(defvar my-magit-ediff--current-index 0
  "Current file index (0-based).")

(defvar my-magit-ediff--rev-a nil
  "Revision A for comparison.")

(defvar my-magit-ediff--rev-b nil
  "Revision B for comparison. nil means working tree, `index' means staged.")

(defvar my-magit-ediff--total-count 0
  "Total number of files for progress display.")

(defvar my-magit-ediff--active nil
  "Non-nil when multi-file ediff session is running.")

(defvar my-magit-ediff--temp-buffers nil
  "Temporary revision buffers to kill on navigation or cleanup.")

;;;; Entry point functions

;;;###autoload
(defun my-magit-ediff-all-unstaged ()
  "Ediff all unstaged files against HEAD sequentially."
  (interactive)
  (let ((files (magit-unstaged-files)))
    (if (null files)
        (message "No unstaged changes.")
      (my-magit-ediff--start files "HEAD" nil))))

;;;###autoload
(defun my-magit-ediff-all-staged ()
  "Ediff all staged files against HEAD sequentially."
  (interactive)
  (let ((files (magit-staged-files)))
    (if (null files)
        (message "No staged changes.")
      (my-magit-ediff--start files "HEAD" 'index))))

;;;###autoload
(defun my-magit-ediff-all-compare (rev-a rev-b)
  "Ediff all changed files between REV-A and REV-B sequentially."
  (interactive
   (let ((rev-a (magit-read-branch-or-commit "Revision A"))
         (rev-b (magit-read-branch-or-commit "Revision B")))
     (list rev-a rev-b)))
  (let ((files (magit-changed-files rev-a rev-b)))
    (if (null files)
        (message "No changes between %s and %s." rev-a rev-b)
      (my-magit-ediff--start files rev-a rev-b))))

;;;; Core engine functions

(defun my-magit-ediff--start (files rev-a rev-b)
  "Initialize state and begin ediff session for FILES between REV-A and REV-B."
  (setq my-magit-ediff--files files
        my-magit-ediff--current-index 0
        my-magit-ediff--rev-a rev-a
        my-magit-ediff--rev-b rev-b
        my-magit-ediff--total-count (length files)
        my-magit-ediff--active t)
  (add-hook 'ediff-quit-hook #'my-magit-ediff--on-quit)
  (my-magit-ediff--open-current))

(defun my-magit-ediff--open-current ()
  "Open ediff for the file at current index."
  (let ((file (nth my-magit-ediff--current-index my-magit-ediff--files)))
    (message "Ediff [%d/%d]: %s"
             (1+ my-magit-ediff--current-index)
             my-magit-ediff--total-count
             file)
    (my-magit-ediff--open-file file)))

(defun my-magit-ediff--open-file (file)
  "Open ediff for a single FILE using current rev-a/rev-b."
  (let ((buf-a (my-magit-ediff--create-revision-buffer
                file my-magit-ediff--rev-a))
        (buf-b (my-magit-ediff--create-revision-buffer
                file my-magit-ediff--rev-b)))
    (ediff-buffers buf-a buf-b)))

(defun my-magit-ediff--create-revision-buffer (file rev)
  "Create a buffer with FILE content at REV.
If REV is nil, return the working tree file buffer.
If REV is `index', return the staged content.
If REV is a string, return that revision's content."
  (let ((default-directory (magit-toplevel)))
    (cond
     ((null rev)
      (find-file-noselect (expand-file-name file)))
     ((eq rev 'index)
      (let ((buf (generate-new-buffer
                  (format "%s (index)" file))))
        (with-current-buffer buf
          (magit-git-insert "cat-file" "-p" (concat ":0:" file))
          (let ((buffer-file-name (expand-file-name file)))
            (set-auto-mode))
          (setq buffer-read-only t)
          (goto-char (point-min)))
        (push buf my-magit-ediff--temp-buffers)
        buf))
     ((stringp rev)
      (let ((buf (generate-new-buffer
                  (format "%s (%s)" file (substring rev 0 (min 7 (length rev)))))))
        (with-current-buffer buf
          (magit-git-insert "cat-file" "-p" (concat rev ":" file))
          (let ((buffer-file-name (expand-file-name file)))
            (set-auto-mode))
          (setq buffer-read-only t)
          (goto-char (point-min)))
        (push buf my-magit-ediff--temp-buffers)
        buf)))))

(defun my-magit-ediff--kill-temp-buffers ()
  "Kill all temporary revision buffers."
  (dolist (buf my-magit-ediff--temp-buffers)
    (when (buffer-live-p buf)
      (kill-buffer buf)))
  (setq my-magit-ediff--temp-buffers nil))

(defun my-magit-ediff--on-quit ()
  "Hook called when ediff session ends. Show navigation prompt if active."
  (when my-magit-ediff--active
    ;; Delay to let ediff finish cleanup before killing temp buffers.
    (run-at-time 0.1 nil #'my-magit-ediff--after-quit)))

(defun my-magit-ediff--after-quit ()
  "Kill temp buffers from previous session, then show navigation."
  (my-magit-ediff--kill-temp-buffers)
  (my-magit-ediff--prompt-navigation))

(defun my-magit-ediff--build-file-labels ()
  "Build labeled file list for `completing-read'."
  (let ((total my-magit-ediff--total-count)
        (result nil)
        (i 0))
    (dolist (file my-magit-ediff--files (nreverse result))
      (push (format "[%d/%d] %s" (1+ i) total file) result)
      (setq i (1+ i)))))

(defun my-magit-ediff--prompt-navigation ()
  "Show file list using `completing-read' for navigation."
  (let* ((idx my-magit-ediff--current-index)
         (total my-magit-ediff--total-count)
         (quit-label "[Done] Quit review")
         (file-labels (my-magit-ediff--build-file-labels))
         (candidates (append file-labels (list quit-label)))
         (default (if (< (1+ idx) total)
                      (nth (1+ idx) file-labels)
                    quit-label))
         (selection (completing-read
                     (format "Ediff [%d/%d done]: " (1+ idx) total)
                     candidates nil t nil nil default)))
    (if (string= selection quit-label)
        (progn
          (my-magit-ediff--cleanup)
          (message "Review ended. %d/%d files reviewed." (1+ idx) total))
      (let ((pos (seq-position file-labels selection #'string=)))
        (when pos
          (setq my-magit-ediff--current-index pos)
          (my-magit-ediff--open-current))))))

(defun my-magit-ediff--cleanup ()
  "Reset state variables and remove hook."
  (my-magit-ediff--kill-temp-buffers)
  (setq my-magit-ediff--files nil
        my-magit-ediff--current-index 0
        my-magit-ediff--rev-a nil
        my-magit-ediff--rev-b nil
        my-magit-ediff--total-count 0
        my-magit-ediff--active nil)
  (remove-hook 'ediff-quit-hook #'my-magit-ediff--on-quit))

;;;; Keybindings

(with-eval-after-load 'magit-ediff
  (transient-append-suffix 'magit-ediff '(0 -1)
    ["All files"
     ("A u" "All unstaged" my-magit-ediff-all-unstaged)
     ("A s" "All staged" my-magit-ediff-all-staged)
     ("A r" "All revisions" my-magit-ediff-all-compare)]))

(provide 'my-magit-ediff)
;;; my-magit-ediff.el ends here
