;;; my-consult-sources.el --- Extra consult-buffer sources -*- lexical-binding: t; -*-

;;; Commentary:
;; Candidate collectors for the custom `consult-buffer' sources: the files
;; tracked in the current git repository, and the repositories ghq knows
;; about.  They live here rather than inside the `use-package consult'
;; body so that tests/my-consult-sources-test.el can exercise them without
;; consult installed.

;;; Code:

(declare-function magit-toplevel "magit-git" (&optional directory))
(declare-function vc-git-command "vc-git" (buffer okstatus file-or-list &rest flags))

(defun my-get-git-files ()
  "Return the absolute paths of the files tracked in the current repository.

Return nil outside a repository."
  (let ((root-dir (magit-toplevel "")))
    (when root-dir
      (with-temp-buffer
        (let ((default-directory root-dir))
          ;; git ls-files reports paths relative to the current working
          ;; directory, so run it from the repository root.
          (vc-git-command (current-buffer) t nil "ls-files"))
        (mapcar (lambda (local-file) (file-name-concat root-dir local-file))
                (split-string (buffer-string) "\n" t))))))

(defun my-get-ghq-repositories ()
  "Return the absolute paths of the repositories managed by ghq."
  (when (executable-find "ghq")
    (with-temp-buffer
      (call-process "ghq" nil (current-buffer) nil "list" "-p")
      (split-string (buffer-string) "\n" t))))

(provide 'my-consult-sources)
;;; my-consult-sources.el ends here
