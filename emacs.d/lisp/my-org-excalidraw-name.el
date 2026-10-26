;;; my-org-excalidraw-name.el --- Name excalidraw drawings after the Org file -*- lexical-binding: t; -*-

;;; Commentary:
;; `my-org-excalidraw-name-create-drawing' replaces the file name prompt of
;; `org-excalidraw-create-drawing'.  The drawing for 2026-10-25.org lands in
;; `org-excalidraw-default-directory' as 2026-10-25-1.excalidraw, then
;; 2026-10-25-2.excalidraw, and so on.  With a prefix argument, the command
;; asks for a label instead and names the drawing 2026-10-25-LABEL.excalidraw.

;;; Code:

(defvar org-excalidraw-default-directory)
(defvar org-excalidraw-default-template)
(declare-function org-excalidraw-link-open "org-excalidraw" (link))
(declare-function org-excalidraw-create-drawing "org-excalidraw" ())

(defun my-org-excalidraw-name-source-file ()
  "Return the file that the current buffer edits, or nil.
An `org-capture' buffer is an indirect buffer without a file of its own,
so the file of its base buffer counts."
  (or buffer-file-name
      (and (buffer-base-buffer)
           (buffer-file-name (buffer-base-buffer)))))

(defun my-org-excalidraw-name-stem (source-file label)
  "Return the drawing name for SOURCE-FILE without the number or extension.
LABEL, when not blank, follows the base name of SOURCE-FILE.  Runs of
characters other than letters, digits, `_' and `-' in LABEL become `-'."
  (let* ((base-name (file-name-base source-file))
         (safe-label (and label
                          (string-trim
                           (replace-regexp-in-string
                            "[^[:alnum:]_-]+" "-" (string-trim label))
                           "-+" "-+"))))
    (if (and safe-label (not (string-empty-p safe-label)))
        (concat base-name "-" safe-label)
      base-name)))

(defun my-org-excalidraw-name-unused-path (directory stem bare-first)
  "Return the first path under DIRECTORY for STEM that no file takes.
The candidates are STEM-1.excalidraw, STEM-2.excalidraw, and so on.  When
BARE-FIRST is non-nil, STEM.excalidraw replaces STEM-1.excalidraw."
  (let ((index 1)
        (found-path nil))
    (while (not found-path)
      (let ((candidate (expand-file-name
                        (if (and bare-first (= index 1))
                            (concat stem ".excalidraw")
                          (format "%s-%d.excalidraw" stem index))
                        directory)))
        (if (file-exists-p candidate)
            (setq index (1+ index))
          (setq found-path candidate))))
    found-path))

;;;###autoload
(defun my-org-excalidraw-name-create-drawing (label)
  "Create a drawing named after the current Org file and link it at point.
Interactively, a prefix argument reads LABEL.  A buffer without a file
falls back to the file name prompt of `org-excalidraw-create-drawing'."
  (interactive
   (list (and current-prefix-arg (read-string "Drawing label: "))))
  (let ((source-file (my-org-excalidraw-name-source-file)))
    (if (not source-file)
        (call-interactively #'org-excalidraw-create-drawing)
      (let* ((stem (my-org-excalidraw-name-stem source-file label))
             (path (my-org-excalidraw-name-unused-path
                    (expand-file-name org-excalidraw-default-directory)
                    stem
                    (not (equal stem (file-name-base source-file))))))
        (with-temp-file path
          (insert org-excalidraw-default-template))
        (insert (format "[[excalidraw:%s]]" path))
        (org-excalidraw-link-open path)))))

(provide 'my-org-excalidraw-name)

;;; my-org-excalidraw-name.el ends here
