;;; my-consult-sources.el --- Extra consult-buffer sources -*- lexical-binding: t; -*-

;;; Commentary:
;; Candidate collectors for the custom `consult-buffer' sources: the files
;; tracked in the current git repository, and the repositories ghq knows
;; about.  They live here rather than inside the `use-package consult'
;; body so that tests/my-consult-sources-test.el can exercise them without
;; consult installed.

;;; Code:

(declare-function consult--file-state "consult" ())
(declare-function magit-toplevel "magit-git" (&optional directory))
(declare-function vc-git-command "vc-git" (buffer okstatus file-or-list &rest flags))

(defun my-get-git-files ()
  "Return the absolute paths of the files tracked in the current repository.

Return nil outside a repository, and nil when `default-directory' is
remote: this runs on every `C-x b', and over Tramp both `magit-toplevel'
and git ls-files become round trips that stall the completion UI."
  (let ((root-dir (unless (file-remote-p default-directory)
                    (magit-toplevel ""))))
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

;; Opening a file for preview costs about 840 ms here, almost all of it spent
;; rebuilding `major-mode-remap-alist' inside the `set-auto-mode-0' advice of
;; `global-treesit-auto-mode'.  Previewing a buffer costs 0 ms in comparison,
;; so only the file sources wait for an explicit key.
(defconst my-consult-file-preview-key "M-."
  "Key that triggers the preview of a candidate that consult must open.")

(defvar my-git-files-source
  `( :name "Git Files"
     :narrow ?g
     :category file
     :preview-key ,my-consult-file-preview-key
     :items ,#'my-get-git-files
     :state ,#'consult--file-state)
  "`consult-buffer' source listing the files tracked in the current repository.")

(defvar my-ghq-repositories-source
  `( :name "Ghq Repositories"
     :narrow ?q
     :category file
     :preview-key ,my-consult-file-preview-key
     :items ,#'my-get-ghq-repositories
     :state ,#'consult--file-state)
  "`consult-buffer' source listing the repositories managed by ghq.")

(provide 'my-consult-sources)
;;; my-consult-sources.el ends here
