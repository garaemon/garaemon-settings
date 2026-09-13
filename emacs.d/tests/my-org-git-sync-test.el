;;; my-org-git-sync-test.el --- Tests for the Org git fetch and merge flow -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-git-sync.el.  The rule under test: opening an Org
;; file fetches without asking, and only a repository that actually fell
;; behind its upstream produces a merge prompt.
;;
;; Only the hanging-push test runs git.  Everywhere else the command output
;; arrives as a string, and the prompt and commit tests stub `y-or-n-p',
;; the merge call, and `my-org-git-sync-start-git' with `cl-letf'.  Run
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

(ert-deftest my-org-git-sync-test-changes-p-accepts-modified-file ()
  (should (my-org-git-sync-changes-p " M notes.org\n")))

(ert-deftest my-org-git-sync-test-changes-p-rejects-empty-output ()
  (should-not (my-org-git-sync-changes-p "")))

(ert-deftest my-org-git-sync-test-changes-p-rejects-blank-output ()
  (should-not (my-org-git-sync-changes-p "\n")))

(ert-deftest my-org-git-sync-test-build-commit-steps-ends-with-push ()
  (should (equal (car (car (last (my-org-git-sync-build-commit-steps
                                  (encode-time '(0 0 0 1 1 2026 nil nil t))))))
                 "push")))

(ert-deftest my-org-git-sync-test-build-commit-steps-stamps-commit-message ()
  (let* ((steps (my-org-git-sync-build-commit-steps
                 (encode-time '(5 4 3 2 1 2026 nil nil t))))
         (commit-step (seq-find (lambda (step) (equal (car step) "commit")) steps))
         (commit-message (car (last commit-step))))
    (should (string-match-p "2026-01-02 03:04:05" commit-message))))

(ert-deftest my-org-git-sync-test-non-interactive-environment-disables-prompt ()
  (should (member "GIT_TERMINAL_PROMPT=0"
                  (my-org-git-sync-make-non-interactive-environment '("HOME=/home")))))

(ert-deftest my-org-git-sync-test-non-interactive-environment-keeps-input-unchanged ()
  (let ((environment '("HOME=/home")))
    (my-org-git-sync-make-non-interactive-environment environment)
    (should (equal environment '("HOME=/home")))))

(defvar my-org-git-sync-test-recorded-arguments nil
  "Argument lists the stubbed `my-org-git-sync-start-git' received, in order.")

(defun my-org-git-sync-test-stub-start-git (recorded-arguments failing-arguments)
  "Return a `my-org-git-sync-start-git' stand-in that never runs git.
The stand-in pushes each argument list onto RECORDED-ARGUMENTS, a symbol,
and reports exit status 1 for FAILING-ARGUMENTS and 0 for the rest."
  (lambda (_repository-root arguments callback)
    (set recorded-arguments (append (symbol-value recorded-arguments)
                                    (list arguments)))
    (funcall callback (if (equal arguments failing-arguments) 1 0) "")))

(ert-deftest my-org-git-sync-test-run-git-steps-runs-every-step-in-order ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (result 'unset))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git 'my-org-git-sync-test-recorded-arguments nil)))
      (my-org-git-sync-run-git-steps "/org/" '(("add") ("commit") ("push"))
                                     (lambda (failed-step) (setq result failed-step)))
      (should (equal my-org-git-sync-test-recorded-arguments '(("add") ("commit") ("push"))))
      (should (equal result nil)))))

(ert-deftest my-org-git-sync-test-run-git-steps-stops-after-first-failure ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (result 'unset))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git 'my-org-git-sync-test-recorded-arguments
                                                    '("commit"))))
      (my-org-git-sync-run-git-steps "/org/" '(("add") ("commit") ("push"))
                                     (lambda (failed-step) (setq result failed-step)))
      (should (equal my-org-git-sync-test-recorded-arguments '(("add") ("commit"))))
      (should (equal result '("commit"))))))

(ert-deftest my-org-git-sync-test-commit-and-push-skips-clean-repository ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git 'my-org-git-sync-test-recorded-arguments nil)))
      (my-org-git-sync-commit-and-push "/org/")
      (should (equal my-org-git-sync-test-recorded-arguments '(("status" "--porcelain")))))))

(ert-deftest my-org-git-sync-test-commit-and-push-pushes-dirty-repository ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (lambda (_repository-root arguments callback)
                 (push arguments my-org-git-sync-test-recorded-arguments)
                 (funcall callback 0 (if (equal arguments '("status" "--porcelain"))
                                         " M notes.org\n"
                                       "")))))
      (my-org-git-sync-commit-and-push "/org/")
      (should (equal (car (car my-org-git-sync-test-recorded-arguments)) "push")))))

(ert-deftest my-org-git-sync-test-commit-and-push-releases-guard-when-done ()
  (let ((my-org-git-sync-commit-in-progress nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (lambda (_repository-root _arguments callback)
                 (funcall callback 0 " M notes.org\n"))))
      (my-org-git-sync-commit-and-push "/org/")
      (should-not my-org-git-sync-commit-in-progress))))

(ert-deftest my-org-git-sync-test-commit-and-push-skips-while-in-progress ()
  (let ((my-org-git-sync-commit-in-progress t))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (lambda (&rest _) (error "Started git during another run"))))
      (my-org-git-sync-commit-and-push "/org/"))))

(defun my-org-git-sync-test-make-repository-with-hanging-remote ()
  "Create a git repository whose push blocks, and return its root.
The remote uses ssh, and `GIT_SSH_COMMAND' sleeps instead of connecting,
so `git push' hangs the way it does on a network that is down."
  (let ((root (file-name-as-directory (make-temp-file "org-git-sync" t))))
    (let ((default-directory root))
      (call-process "git" nil nil nil "init" "--quiet" "-b" "main")
      (call-process "git" nil nil nil "config" "user.email" "test@example.com")
      (call-process "git" nil nil nil "config" "user.name" "Test")
      (call-process "git" nil nil nil "remote" "add" "origin"
                    "git@example.invalid:org.git")
      (with-temp-file (concat root "notes.org") (insert "* Note\n")))
    root))

(ert-deftest my-org-git-sync-test-commit-and-push-returns-while-push-hangs ()
  (skip-unless (executable-find "git"))
  (let* ((root (my-org-git-sync-test-make-repository-with-hanging-remote))
         (process-environment (cons "GIT_SSH_COMMAND=sleep 30" process-environment))
         (my-org-git-sync-commit-in-progress nil)
         (started-at (float-time)))
    (unwind-protect
        (progn
          (my-org-git-sync-commit-and-push root)
          (should (< (- (float-time) started-at) 1.0)))
      (dolist (process (process-list))
        (when (string-prefix-p "my-org-git-sync" (process-name process))
          (delete-process process)))
      (delete-directory root t))))

(provide 'my-org-git-sync-test)
;;; my-org-git-sync-test.el ends here
