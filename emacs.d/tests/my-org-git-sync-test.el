;;; my-org-git-sync-test.el --- Tests for the Org git fetch and merge flow -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-git-sync.el.  The rule under test: opening an Org
;; file fetches without asking, and only a repository that actually fell
;; behind its upstream produces a merge prompt.
;;
;; No test runs git.  The command output arrives as a string, and the
;; prompt tests stub `y-or-n-p' and the merge call with `cl-letf'.  Run
;; with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-org-git-sync-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-org-git-sync)

(ert-deftest my-org-git-sync-test-parse-behind-count-reads-number ()
  (should (equal (my-org-git-sync-parse-behind-count "3\n") 3)))

(ert-deftest my-org-git-sync-test-parse-behind-count-reads-zero ()
  (should (equal (my-org-git-sync-parse-behind-count "0\n") 0)))

(ert-deftest my-org-git-sync-test-parse-behind-count-rejects-error-output ()
  (should (equal (my-org-git-sync-parse-behind-count
                  "fatal: no upstream configured for branch 'main'\n")
                 nil)))

(ert-deftest my-org-git-sync-test-parse-behind-count-rejects-empty-output ()
  (should (equal (my-org-git-sync-parse-behind-count "") nil)))

(ert-deftest my-org-git-sync-test-record-fetch-date-adds-repository ()
  (should (equal (my-org-git-sync-record-fetch-date "/org/" "2026-09-11" nil)
                 '(("/org/" . "2026-09-11")))))

(ert-deftest my-org-git-sync-test-record-fetch-date-replaces-old-date ()
  (should (equal (my-org-git-sync-record-fetch-date
                  "/org/" "2026-09-11" '(("/org/" . "2026-09-10")))
                 '(("/org/" . "2026-09-11")))))

(ert-deftest my-org-git-sync-test-record-fetch-date-keeps-input-unchanged ()
  (let ((dates '(("/org/" . "2026-09-10"))))
    (my-org-git-sync-record-fetch-date "/org/" "2026-09-11" dates)
    (should (equal dates '(("/org/" . "2026-09-10"))))))

(ert-deftest my-org-git-sync-test-fetched-today-p-accepts-same-date ()
  (should (my-org-git-sync-fetched-today-p
           "/org/" "2026-09-11" '(("/org/" . "2026-09-11")))))

(ert-deftest my-org-git-sync-test-fetched-today-p-rejects-older-date ()
  (should-not (my-org-git-sync-fetched-today-p
               "/org/" "2026-09-11" '(("/org/" . "2026-09-10")))))

(ert-deftest my-org-git-sync-test-fetched-today-p-rejects-unknown-repository ()
  (should-not (my-org-git-sync-fetched-today-p "/org/" "2026-09-11" nil)))

(ert-deftest my-org-git-sync-test-target-file-p-accepts-org-file-in-directory ()
  (should (my-org-git-sync-target-file-p "/org/notes.org" 'org-mode "/org/")))

(ert-deftest my-org-git-sync-test-target-file-p-rejects-other-major-mode ()
  (should-not (my-org-git-sync-target-file-p "/org/notes.org" 'text-mode "/org/")))

(ert-deftest my-org-git-sync-test-target-file-p-rejects-file-outside-directory ()
  (should-not (my-org-git-sync-target-file-p "/tmp/notes.org" 'org-mode "/org/")))

(ert-deftest my-org-git-sync-test-target-file-p-rejects-buffer-without-file ()
  (should-not (my-org-git-sync-target-file-p nil 'org-mode "/org/")))

(ert-deftest my-org-git-sync-test-ask-merge-skips-prompt-when-up-to-date ()
  (let ((prompted nil))
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (&rest _) (setq prompted t) t))
              ((symbol-function 'my-org-git-sync-merge-upstream)
               (lambda (&rest _) (error "Merged an up-to-date repository"))))
      (my-org-git-sync-ask-merge "/org/" 0)
      (should-not prompted))))

(ert-deftest my-org-git-sync-test-ask-merge-skips-prompt-without-upstream ()
  (let ((prompted nil))
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (&rest _) (setq prompted t) t))
              ((symbol-function 'my-org-git-sync-merge-upstream)
               (lambda (&rest _) (error "Merged a repository without upstream"))))
      (my-org-git-sync-ask-merge "/org/" nil)
      (should-not prompted))))

(ert-deftest my-org-git-sync-test-ask-merge-merges-on-yes ()
  (let ((merged-repositories nil))
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t))
              ((symbol-function 'my-org-git-sync-merge-upstream)
               (lambda (repo-root) (push repo-root merged-repositories))))
      (my-org-git-sync-ask-merge "/org/" 2)
      (should (equal merged-repositories '("/org/"))))))

(ert-deftest my-org-git-sync-test-ask-merge-keeps-repository-on-no ()
  (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil))
            ((symbol-function 'my-org-git-sync-merge-upstream)
             (lambda (&rest _) (error "Merged after a declined prompt"))))
    (my-org-git-sync-ask-merge "/org/" 2)))

(ert-deftest my-org-git-sync-test-ask-merge-reports-commit-count ()
  (let ((prompt nil))
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (message) (setq prompt message) nil)))
      (my-org-git-sync-ask-merge "/org/" 2)
      (should (string-match-p "2" prompt))
      (should (string-match-p "/org/" prompt)))))

(provide 'my-org-git-sync-test)
;;; my-org-git-sync-test.el ends here
