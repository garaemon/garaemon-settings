;;; my-consult-sources-test.el --- Tests for the consult-buffer sources -*- lexical-binding: t; -*-

;;; Commentary:
;; Regression tests for the custom `consult-buffer' sources.
;;
;; `my-get-git-files' runs on every `C-x b'.  Over Tramp both
;; `magit-toplevel' and git ls-files turn into round trips to the remote
;; host, which stalls the completion UI, so the function must return nil
;; for a remote `default-directory' without shelling out at all.
;;
;; The tests stub `magit-toplevel' and `vc-git-command' so neither magit
;; nor a real repository is needed.  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-consult-sources-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-consult-sources)

(ert-deftest my-get-git-files-should-list-files-under-the-repository-root ()
  (cl-letf (((symbol-function 'magit-toplevel) (lambda (&rest _) "/repo/"))
            ((symbol-function 'vc-git-command)
             (lambda (buffer &rest _)
               (with-current-buffer buffer (insert "a.el\ndir/b.el\n")))))
    (should (equal (my-get-git-files) '("/repo/a.el" "/repo/dir/b.el")))))

(ert-deftest my-get-git-files-should-return-nil-outside-a-repository ()
  (cl-letf (((symbol-function 'magit-toplevel) (lambda (&rest _) nil)))
    (should (null (my-get-git-files)))))

(ert-deftest my-get-git-files-should-return-nil-for-a-remote-directory ()
  (let ((default-directory "/ssh:host:/home/user/"))
    (cl-letf (((symbol-function 'magit-toplevel)
               (lambda (&rest _) (error "magit-toplevel must not run on a remote host")))
              ((symbol-function 'vc-git-command)
               (lambda (&rest _) (error "vc-git-command must not run on a remote host"))))
      (should (null (my-get-git-files))))))

(ert-deftest my-get-ghq-repositories-should-return-nil-without-the-ghq-executable ()
  (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil)))
    (should (null (my-get-ghq-repositories)))))

(ert-deftest my-get-ghq-repositories-should-split-the-command-output-into-paths ()
  (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "/usr/bin/ghq"))
            ((symbol-function 'call-process)
             (lambda (_program _infile buffer &rest _)
               (with-current-buffer buffer (insert "/ghq/a\n/ghq/b\n"))
               0)))
    (should (equal (my-get-ghq-repositories) '("/ghq/a" "/ghq/b")))))

(ert-deftest my-git-files-source-should-declare-the-file-category ()
  (should (eq (plist-get my-git-files-source :category) 'file)))

(ert-deftest my-ghq-repositories-source-should-declare-the-file-category ()
  (should (eq (plist-get my-ghq-repositories-source :category) 'file)))

(ert-deftest my-git-files-source-should-preview-only-on-a-key-press ()
  (should (stringp (plist-get my-git-files-source :preview-key))))

(ert-deftest my-ghq-repositories-source-should-preview-only-on-a-key-press ()
  (should (stringp (plist-get my-ghq-repositories-source :preview-key))))

(provide 'my-consult-sources-test)
;;; my-consult-sources-test.el ends here
