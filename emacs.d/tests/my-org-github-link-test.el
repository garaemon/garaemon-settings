;;; my-org-github-link-test.el --- Tests for GitHub link formatting on yank -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-github-link.el.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-org-github-link-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'org)
(require 'my-org-github-link)

(ert-deftest my-org-github-link-test-formats-issue-url ()
  (should (equal (my-org-github-link-format
                  "https://github.com/garaemon/garaemon-settings/issues/20")
                 (concat "[[https://github.com/garaemon/garaemon-settings/issues/20]"
                         "[garaemon/garaemon-settings#20]]"))))

(ert-deftest my-org-github-link-test-formats-pull-request-url ()
  (should (equal (my-org-github-link-format
                  "https://github.com/garaemon/garaemon-settings/pull/21")
                 (concat "[[https://github.com/garaemon/garaemon-settings/pull/21]"
                         "[garaemon/garaemon-settings#21]]"))))

(ert-deftest my-org-github-link-test-keeps-url-with-comment-anchor ()
  (should (equal (my-org-github-link-format
                  "https://github.com/a/b/issues/3#issuecomment-99")
                 "[[https://github.com/a/b/issues/3#issuecomment-99][a/b#3]]")))

(ert-deftest my-org-github-link-test-formats-pull-request-subpage ()
  (should (equal (my-org-github-link-format
                  "https://github.com/a/b/pull/4/files")
                 "[[https://github.com/a/b/pull/4/files][a/b#4]]")))

(ert-deftest my-org-github-link-test-formats-repository-url ()
  (should (equal (my-org-github-link-format "https://github.com/a/b")
                 "[[https://github.com/a/b][a/b]]")))

(ert-deftest my-org-github-link-test-formats-repository-url-with-slash ()
  (should (equal (my-org-github-link-format "https://github.com/a/b/")
                 "[[https://github.com/a/b/][a/b]]")))

(ert-deftest my-org-github-link-test-strips-git-suffix-from-label ()
  (should (equal (my-org-github-link-format "https://github.com/a/b.git")
                 "[[https://github.com/a/b.git][a/b]]")))

(ert-deftest my-org-github-link-test-trims-surrounding-whitespace ()
  (should (equal (my-org-github-link-format "  https://github.com/a/b\n")
                 "[[https://github.com/a/b][a/b]]")))

(ert-deftest my-org-github-link-test-ignores-file-url ()
  (should-not (my-org-github-link-format
               "https://github.com/a/b/blob/main/README.md")))

(ert-deftest my-org-github-link-test-ignores-reserved-path ()
  (should-not (my-org-github-link-format
               "https://github.com/settings/profile")))

(ert-deftest my-org-github-link-test-ignores-other-host ()
  (should-not (my-org-github-link-format "https://gitlab.com/a/b")))

(ert-deftest my-org-github-link-test-ignores-url-inside-prose ()
  (should-not (my-org-github-link-format
               "see https://github.com/a/b/issues/1 for details")))

(ert-deftest my-org-github-link-test-transform-formats-in-org-buffer ()
  (with-temp-buffer
    (org-mode)
    (should (equal (my-org-github-link-transform-yank
                    "https://github.com/a/b/issues/1")
                   "[[https://github.com/a/b/issues/1][a/b#1]]"))))

(ert-deftest my-org-github-link-test-transform-keeps-text-unchanged ()
  (with-temp-buffer
    (org-mode)
    (should (equal (my-org-github-link-transform-yank "plain text")
                   "plain text"))))

(ert-deftest my-org-github-link-test-transform-skips-inside-link ()
  (with-temp-buffer
    (org-mode)
    (insert "[[]]")
    (goto-char 3)
    (should (equal (my-org-github-link-transform-yank
                    "https://github.com/a/b")
                   "https://github.com/a/b"))))

(ert-deftest my-org-github-link-test-transform-formats-after-link ()
  (with-temp-buffer
    (org-mode)
    (insert "[[https://example.com][ex]] ")
    (should (equal (my-org-github-link-transform-yank
                    "https://github.com/a/b")
                   "[[https://github.com/a/b][a/b]]"))))

(ert-deftest my-org-github-link-test-yank-inserts-org-link ()
  (with-temp-buffer
    (org-mode)
    (my-org-github-link-mode 1)
    (let ((kill-ring (list "https://github.com/a/b/issues/7")))
      (yank))
    (should (equal (buffer-string)
                   "[[https://github.com/a/b/issues/7][a/b#7]]"))))

(provide 'my-org-github-link-test)

;;; my-org-github-link-test.el ends here
