;;; my-dired-open.el --- Open dired files with the OS default application -*- lexical-binding: t; -*-

;;; Commentary:
;; `my-dired-open-externally' hands the marked files of a dired buffer, or
;; the file at point, to the opener of the OS: `open' on macOS and
;; `xdg-open' elsewhere.  Both pick the default application of each file,
;; as a double click in a file manager does.

;;; Code:

(require 'dired)

(defun my-dired-open-command ()
  "Return the name of the OS command that opens a file with its default app."
  (if (eq system-type 'darwin) "open" "xdg-open"))

(defun my-dired-open-files (files)
  "Open FILES with the OS opener without blocking Emacs."
  (dolist (file files)
    ;; `xdg-open' takes one file per call, so each file gets its own process.
    ;; The absolute path also keeps a name that starts with "-" from being
    ;; read as an option.
    (start-process "dired-open" nil (my-dired-open-command)
                   (expand-file-name file))))

;;;###autoload
(defun my-dired-open-externally ()
  "Open the marked files, or the file at point, with the OS opener."
  (interactive)
  (my-dired-open-files (dired-get-marked-files)))

(provide 'my-dired-open)

;;; my-dired-open.el ends here
