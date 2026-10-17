;;; my-dired-open.el --- Open dired files with the macOS open command -*- lexical-binding: t; -*-

;;; Commentary:
;; `my-dired-open-externally' hands the marked files of a dired buffer, or
;; the file at point, to the macOS `open' command.  `open' picks the
;; default application of each file, as a double click in Finder does.

;;; Code:

(require 'dired)

(defun my-dired-open-files (files)
  "Open FILES with the macOS `open' command without blocking Emacs."
  (let ((absolute-files (mapcar #'expand-file-name files)))
    ;; "--" keeps a file name that starts with "-" from being read as an
    ;; option of `open'.
    (apply #'start-process "dired-open" nil "open" "--" absolute-files)))

;;;###autoload
(defun my-dired-open-externally ()
  "Open the marked files, or the file at point, with the macOS `open' command."
  (interactive)
  (my-dired-open-files (dired-get-marked-files)))

(provide 'my-dired-open)

;;; my-dired-open.el ends here
