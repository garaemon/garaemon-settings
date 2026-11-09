;;; my-org-drawing-name.el --- Name drawing files after the Org file -*- lexical-binding: t; -*-

;;; Commentary:
;; Helpers that name a drawing file after the Org file that links to it.
;; The drawing for 2026-10-25.org becomes 2026-10-25-1.EXT, then
;; 2026-10-25-2.EXT, and so on.  A label turns the name into
;; 2026-10-25-LABEL.EXT.  The Excalidraw and draw.io commands share these
;; helpers and differ only in the extension.

;;; Code:

(require 'subr-x)

(defun my-org-drawing-name-source-file ()
  "Return the file that the current buffer edits, or nil.
An `org-capture' buffer is an indirect buffer without a file of its own,
so the file of its base buffer counts."
  (or buffer-file-name
      (and (buffer-base-buffer)
           (buffer-file-name (buffer-base-buffer)))))

(defun my-org-drawing-name-stem (source-file label)
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

(defun my-org-drawing-name-unused-path (directory stem bare-first extension)
  "Return the first path under DIRECTORY for STEM that no file takes.
The candidates are STEM-1EXTENSION, STEM-2EXTENSION, and so on.
EXTENSION includes its leading dot, such as \".excalidraw\".  When
BARE-FIRST is non-nil, STEMEXTENSION replaces STEM-1EXTENSION."
  (let ((index 1)
        (found-path nil))
    (while (not found-path)
      (let ((candidate (expand-file-name
                        (if (and bare-first (= index 1))
                            (concat stem extension)
                          (format "%s-%d%s" stem index extension))
                        directory)))
        (if (file-exists-p candidate)
            (setq index (1+ index))
          (setq found-path candidate))))
    found-path))

(defun my-org-drawing-name-new-path (source-file label directory extension)
  "Return an unused drawing path under DIRECTORY named after SOURCE-FILE.
LABEL and EXTENSION are as in `my-org-drawing-name-stem' and
`my-org-drawing-name-unused-path'.  A labeled drawing tries the name
without a number first."
  (let ((stem (my-org-drawing-name-stem source-file label)))
    (my-org-drawing-name-unused-path
     (expand-file-name directory)
     stem
     (not (equal stem (file-name-base source-file)))
     extension)))

(provide 'my-org-drawing-name)

;;; my-org-drawing-name.el ends here
