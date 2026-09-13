;;; my-org-git-sync-test.el --- Tests for the Org git fetch and merge flow -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-git-sync.el.  Two rules are under test: opening an
;; Org file fetches without asking, and only a repository that actually
;; fell behind its upstream produces a merge prompt; a save leads to one
;; commit-and-push chain at a time, and a chain never blocks Emacs.
;;
;; Only the tests that call `my-org-git-sync-start-git' unstubbed run git,
;; against a temporary repository or with `git --version'.  Everywhere
;; else the command output arrives as a string, and the prompt and commit
;; tests stub `y-or-n-p', the merge call, and `my-org-git-sync-start-git'
;; with `cl-letf'.  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-org-git-sync-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-org-git-sync)

;; Declared here so that `let' binds it dynamically; org itself stays
;; unloaded in the batch run.
(defvar org-directory)

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

(ert-deftest my-org-git-sync-test-ask-merge-skips-merge-when-commit-started-during-prompt ()
  (let ((my-org-git-sync-commit-in-progress nil))
    (cl-letf (((symbol-function 'y-or-n-p)
               (lambda (&rest _) (setq my-org-git-sync-commit-in-progress t) t))
              ((symbol-function 'my-org-git-sync-merge-upstream)
               (lambda (&rest _) (error "Merged while a commit chain ran")))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-ask-merge "/org/" 2))))

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

;; The fixtures below name no zone (the trailing nil) so that they format
;; the same way as `my-org-git-sync-build-commit-steps', which stamps the
;; message in the local zone.  A UTC fixture fails everywhere but in CI.
(ert-deftest my-org-git-sync-test-build-commit-steps-ends-with-push ()
  (should (equal (car (car (last (my-org-git-sync-build-commit-steps
                                  (encode-time '(0 0 0 1 1 2026 nil -1 nil))
                                  "/org/"))))
                 "push")))

(ert-deftest my-org-git-sync-test-build-commit-steps-adds-only-the-pathspec ()
  (should (equal (car (my-org-git-sync-build-commit-steps
                       (encode-time '(0 0 0 1 1 2026 nil -1 nil)) "/org/"))
                 '("add" "--all" "--" "/org/"))))

(ert-deftest my-org-git-sync-test-build-commit-steps-stamps-commit-message ()
  (let* ((steps (my-org-git-sync-build-commit-steps
                 (encode-time '(5 4 3 2 1 2026 nil -1 nil)) "/org/"))
         (commit-step (seq-find (lambda (step) (equal (car step) "commit")) steps))
         (commit-message (car (last commit-step))))
    (should (string-match-p "2026-01-02 03:04:05" commit-message))))

(ert-deftest my-org-git-sync-test-non-interactive-environment-disables-git-prompt ()
  (should (member "GIT_TERMINAL_PROMPT=0"
                  (my-org-git-sync-make-non-interactive-environment '("HOME=/home")))))

(ert-deftest my-org-git-sync-test-non-interactive-environment-puts-ssh-in-batch-mode ()
  (should (member "GIT_SSH_COMMAND=ssh -oBatchMode=yes"
                  (my-org-git-sync-make-non-interactive-environment '("HOME=/home")))))

(ert-deftest my-org-git-sync-test-non-interactive-environment-keeps-custom-ssh-command ()
  (should (member "GIT_SSH_COMMAND=ssh -i ~/.ssh/org -oBatchMode=yes"
                  (my-org-git-sync-make-non-interactive-environment
                   '("GIT_SSH_COMMAND=ssh -i ~/.ssh/org" "HOME=/home")))))

(ert-deftest my-org-git-sync-test-non-interactive-environment-keeps-input-unchanged ()
  (let ((environment '("HOME=/home")))
    (my-org-git-sync-make-non-interactive-environment environment)
    (should (equal environment '("HOME=/home")))))

(ert-deftest my-org-git-sync-test-build-commit-pathspec-limits-commit-to-org-directory ()
  (should (equal (my-org-git-sync-build-commit-pathspec "/repo/" "/repo/org/")
                 "/repo/org/")))

(ert-deftest my-org-git-sync-test-build-commit-pathspec-accepts-org-directory-as-root ()
  (should (equal (my-org-git-sync-build-commit-pathspec "/org/" "/org") "/org/")))

(ert-deftest my-org-git-sync-test-build-commit-pathspec-covers-repository-inside-org-directory ()
  (should (equal (my-org-git-sync-build-commit-pathspec "/org/nested/" "/org/") ".")))

(ert-deftest my-org-git-sync-test-build-commit-pathspec-covers-repository-without-org-directory ()
  (should (equal (my-org-git-sync-build-commit-pathspec "/repo/" nil) ".")))

(ert-deftest my-org-git-sync-test-reset-releases-guard ()
  (let ((my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'message) #'ignore))
      (my-org-git-sync-reset)
      (should-not my-org-git-sync-commit-in-progress))))

(ert-deftest my-org-git-sync-test-reset-drops-pending-commit ()
  (let ((my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root "/org/"))
    (cl-letf (((symbol-function 'message) #'ignore))
      (my-org-git-sync-reset)
      (should-not my-org-git-sync-pending-commit-root))))

(defvar my-org-git-sync-test-recorded-arguments nil
  "Argument lists the stubbed `my-org-git-sync-start-git' received, in call order.")

(defun my-org-git-sync-test-stub-start-git (&optional failing-arguments outputs)
  "Return a `my-org-git-sync-start-git' stand-in that never runs git.
The stand-in appends each argument list to
`my-org-git-sync-test-recorded-arguments' and calls the callback at once
with exit status 1 for FAILING-ARGUMENTS and 0 for the rest.  OUTPUTS is an
alist from argument list to the output the callback receives; an argument
list missing from it yields an empty string."
  (lambda (_repository-root arguments callback)
    (setq my-org-git-sync-test-recorded-arguments
          (append my-org-git-sync-test-recorded-arguments (list arguments)))
    (funcall callback
             (if (equal arguments failing-arguments) 1 0)
             (or (cdr (assoc arguments outputs)) ""))))

(defconst my-org-git-sync-test-status-arguments
  '("status" "--porcelain" "--" "/org/")
  "Arguments of the `git status' that opens a chain for the Org directory /org/.")

(defconst my-org-git-sync-test-dirty-status-outputs
  (list (cons my-org-git-sync-test-status-arguments " M notes.org\n"))
  "Outputs that make the stubbed `git status' report a modified file.")

(ert-deftest my-org-git-sync-test-run-git-steps-runs-every-step-in-order ()
  (let ((my-org-git-sync-test-recorded-arguments nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git)))
      (my-org-git-sync-run-git-steps "/org/" '(("add") ("commit") ("push")) #'ignore)
      (should (equal my-org-git-sync-test-recorded-arguments '(("add") ("commit") ("push")))))))

(ert-deftest my-org-git-sync-test-run-git-steps-reports-nil-when-every-step-passes ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (result 'unset))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git)))
      (my-org-git-sync-run-git-steps "/org/" '(("add") ("commit") ("push"))
                                     (lambda (failed-step) (setq result failed-step)))
      (should (equal result nil)))))

(ert-deftest my-org-git-sync-test-run-git-steps-stops-after-first-failure ()
  (let ((my-org-git-sync-test-recorded-arguments nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git '("commit"))))
      (my-org-git-sync-run-git-steps "/org/" '(("add") ("commit") ("push")) #'ignore)
      (should (equal my-org-git-sync-test-recorded-arguments '(("add") ("commit")))))))

(ert-deftest my-org-git-sync-test-run-git-steps-reports-failed-step ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (result 'unset))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git '("commit"))))
      (my-org-git-sync-run-git-steps "/org/" '(("add") ("commit") ("push"))
                                     (lambda (failed-step) (setq result failed-step)))
      (should (equal result '("commit"))))))

(ert-deftest my-org-git-sync-test-commit-and-push-skips-clean-repository ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil)
        (org-directory "/org/"))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git)))
      (my-org-git-sync-commit-and-push "/org/")
      (should (equal my-org-git-sync-test-recorded-arguments
                     (list my-org-git-sync-test-status-arguments))))))

(ert-deftest my-org-git-sync-test-commit-and-push-pushes-dirty-repository ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil)
        (org-directory "/org/"))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git
                nil my-org-git-sync-test-dirty-status-outputs)))
      (my-org-git-sync-commit-and-push "/org/")
      (should (equal (car (car (last my-org-git-sync-test-recorded-arguments))) "push")))))

(ert-deftest my-org-git-sync-test-commit-and-push-releases-guard-when-done ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil)
        (org-directory "/org/"))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git
                nil my-org-git-sync-test-dirty-status-outputs)))
      (my-org-git-sync-commit-and-push "/org/")
      (should-not my-org-git-sync-commit-in-progress))))

(defmacro my-org-git-sync-test-with-log-buffer (&rest body)
  "Run BODY with the module logging into a throwaway buffer.
Keeps the `*org-git-sync*' buffer of an interactive Emacs clean."
  (declare (indent 0))
  `(let ((my-org-git-sync-buffer-name " *org-git-sync-test-log*"))
     (unwind-protect (progn ,@body)
       (when (get-buffer my-org-git-sync-buffer-name)
         (kill-buffer my-org-git-sync-buffer-name)))))

(defun my-org-git-sync-test-fail-make-process (&rest _)
  "Signal the error of `make-process' for a git missing from variable `exec-path'."
  (signal 'file-missing '("Searching for program" "No such file or directory" "git")))

(defun my-org-git-sync-test-count-command-buffers ()
  "Return how many private command buffers of the module exist."
  (seq-count (lambda (buffer)
               (string-prefix-p " *org-git-sync-command*" (buffer-name buffer)))
             (buffer-list)))

(ert-deftest my-org-git-sync-test-start-git-reports-status-127-when-git-cannot-start ()
  (my-org-git-sync-test-with-log-buffer
    (let ((reported-status nil))
      (cl-letf (((symbol-function 'make-process) #'my-org-git-sync-test-fail-make-process))
        (my-org-git-sync-start-git "/org/" '("status")
                                   (lambda (status _output) (setq reported-status status)))
        (should (equal reported-status 127))))))

(ert-deftest my-org-git-sync-test-start-git-passes-error-as-output-when-git-cannot-start ()
  (my-org-git-sync-test-with-log-buffer
    (let ((reported-output nil))
      (cl-letf (((symbol-function 'make-process) #'my-org-git-sync-test-fail-make-process))
        (my-org-git-sync-start-git "/org/" '("status")
                                   (lambda (_status output) (setq reported-output output)))
        (should (string-match-p "git" reported-output))))))

(ert-deftest my-org-git-sync-test-start-git-leaves-no-buffer-when-git-cannot-start ()
  (my-org-git-sync-test-with-log-buffer
    (let ((buffers-before (my-org-git-sync-test-count-command-buffers)))
      (cl-letf (((symbol-function 'make-process) #'my-org-git-sync-test-fail-make-process))
        (my-org-git-sync-start-git "/org/" '("status") #'ignore)
        (should (equal (my-org-git-sync-test-count-command-buffers) buffers-before))))))

(ert-deftest my-org-git-sync-test-commit-and-push-releases-guard-when-git-cannot-start ()
  (my-org-git-sync-test-with-log-buffer
    (let ((my-org-git-sync-commit-in-progress nil))
      (cl-letf (((symbol-function 'make-process) #'my-org-git-sync-test-fail-make-process)
                ((symbol-function 'message) #'ignore))
        (my-org-git-sync-commit-and-push "/org/")
        (should-not my-org-git-sync-commit-in-progress)))))

(ert-deftest my-org-git-sync-test-commit-and-push-releases-guard-when-status-fails ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil)
        (org-directory "/org/"))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git my-org-git-sync-test-status-arguments))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-commit-and-push "/org/")
      (should-not my-org-git-sync-commit-in-progress))))

(ert-deftest my-org-git-sync-test-commit-and-push-reports-status-failure ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil)
        (org-directory "/org/")
        (messages nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git my-org-git-sync-test-status-arguments))
              ((symbol-function 'message)
               (lambda (format-string &rest arguments)
                 (push (apply #'format format-string arguments) messages))))
      (my-org-git-sync-commit-and-push "/org/")
      (should (seq-find (lambda (line) (string-match-p "git status failed" line))
                        messages)))))

(ert-deftest my-org-git-sync-test-commit-and-push-records-pending-repository-while-in-progress ()
  (let ((my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (lambda (&rest _) (error "Started git during another run"))))
      (my-org-git-sync-commit-and-push "/org/")
      (should (equal my-org-git-sync-pending-commit-root "/org/")))))

(ert-deftest my-org-git-sync-test-finish-commit-starts-pending-commit ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root "/org/")
        (org-directory "/org/"))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-finish-commit "/org/" nil)
      (should (equal my-org-git-sync-test-recorded-arguments
                     (list my-org-git-sync-test-status-arguments))))))

(ert-deftest my-org-git-sync-test-finish-commit-starts-pending-commit-in-its-own-repository ()
  (let ((my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root "/second-org/")
        (started-in nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (lambda (repository-root _arguments _callback)
                 (setq started-in repository-root)))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-finish-commit "/org/" nil)
      (should (equal started-in "/second-org/")))))

(ert-deftest my-org-git-sync-test-finish-commit-clears-pending-repository ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root "/org/")
        (org-directory "/org/"))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-finish-commit "/org/" nil)
      (should-not my-org-git-sync-pending-commit-root))))

(ert-deftest my-org-git-sync-test-prompt-merge-skips-prompt-while-commit-runs ()
  (let ((my-org-git-sync-commit-in-progress t))
    (cl-letf (((symbol-function 'my-org-git-sync-count-behind-commits)
               (lambda (&rest _) (error "Counted commits during a commit chain")))
              ((symbol-function 'y-or-n-p)
               (lambda (&rest _) (error "Prompted during a commit chain")))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-prompt-merge "/org/"))))

(ert-deftest my-org-git-sync-test-append-log-ends-output-with-newline ()
  (my-org-git-sync-test-with-log-buffer
    (my-org-git-sync-append-log '("push") "partial line")
    (should (string-suffix-p "partial line\n"
                             (with-current-buffer my-org-git-sync-buffer-name
                               (buffer-string))))))

(ert-deftest my-org-git-sync-test-append-log-adds-no-newline-to-empty-output ()
  (my-org-git-sync-test-with-log-buffer
    (my-org-git-sync-append-log '("push") "")
    (should (equal (with-current-buffer my-org-git-sync-buffer-name
                     (buffer-string))
                   "$ git push\n"))))

(defun my-org-git-sync-test-make-repository-with-hanging-remote ()
  "Create a git repository whose push hangs, and return its root.
The remote uses ssh, and the returned root holds a `hang-ssh' script that
sleeps instead of connecting.  Pointing GIT_SSH_COMMAND at that script makes
`git push' hang the way it does on a network that is down."
  (let ((root (file-name-as-directory (make-temp-file "org-git-sync" t))))
    (let ((default-directory root))
      (call-process "git" nil nil nil "init" "--quiet" "-b" "main")
      (call-process "git" nil nil nil "config" "user.email" "test@example.com")
      (call-process "git" nil nil nil "config" "user.name" "Test")
      (call-process "git" nil nil nil "remote" "add" "origin"
                    "git@example.invalid:org.git")
      (with-temp-file (concat root "notes.org") (insert "* Note\n"))
      (with-temp-file (concat root "hang-ssh") (insert "#!/bin/sh\nsleep 30\n"))
      (set-file-modes (concat root "hang-ssh") #o755))
    root))

(defun my-org-git-sync-test-wait-until (predicate timeout)
  "Run process output and timers until PREDICATE holds or TIMEOUT seconds pass."
  (let ((deadline (+ (float-time) timeout)))
    (while (and (not (funcall predicate))
                (< (float-time) deadline))
      (accept-process-output nil 0.1))))

(defun my-org-git-sync-test-run-git-version ()
  "Run `git --version' through the module into a test log buffer and wait for it.
Returns the content of the log buffer."
  (my-org-git-sync-test-with-log-buffer
    (let ((done nil))
      (my-org-git-sync-start-git default-directory '("--version")
                                 (lambda (&rest _) (setq done t)))
      (my-org-git-sync-test-wait-until (lambda () done) 10)
      (with-current-buffer my-org-git-sync-buffer-name (buffer-string)))))

(ert-deftest my-org-git-sync-test-start-git-logs-command-header ()
  (skip-unless (executable-find "git"))
  (should (string-prefix-p "$ git --version\n" (my-org-git-sync-test-run-git-version))))

(ert-deftest my-org-git-sync-test-start-git-logs-command-output ()
  (skip-unless (executable-find "git"))
  (should (string-match-p "git version" (my-org-git-sync-test-run-git-version))))

(defun my-org-git-sync-test-run-git-version-with-broken-callback ()
  "Run `git --version' with a callback that signals, and wait for it.
Returns the content of the log buffer."
  (my-org-git-sync-test-with-log-buffer
    (let ((done nil))
      (cl-letf (((symbol-function 'message) #'ignore))
        (my-org-git-sync-start-git default-directory '("--version")
                                   (lambda (&rest _)
                                     (setq done t)
                                     (error "Broken callback")))
        (my-org-git-sync-test-wait-until (lambda () done) 10)
        (with-current-buffer my-org-git-sync-buffer-name (buffer-string))))))

(ert-deftest my-org-git-sync-test-start-git-releases-guard-when-callback-signals ()
  (skip-unless (executable-find "git"))
  (let ((my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root nil))
    (my-org-git-sync-test-run-git-version-with-broken-callback)
    (should-not my-org-git-sync-commit-in-progress)))

(ert-deftest my-org-git-sync-test-start-git-logs-callback-error ()
  (skip-unless (executable-find "git"))
  (let ((my-org-git-sync-commit-in-progress nil)
        (my-org-git-sync-pending-commit-root nil))
    (should (string-match-p "Broken callback"
                            (my-org-git-sync-test-run-git-version-with-broken-callback)))))

(ert-deftest my-org-git-sync-test-start-git-kills-private-buffer-when-done ()
  (skip-unless (executable-find "git"))
  (let ((buffers-before (my-org-git-sync-test-count-command-buffers)))
    (my-org-git-sync-test-run-git-version)
    (should (equal (my-org-git-sync-test-count-command-buffers) buffers-before))))

(defun my-org-git-sync-test-delete-git-processes ()
  "Kill every process this module started, so a test leaves nothing behind."
  (dolist (process (process-list))
    (when (string-prefix-p "my-org-git-sync" (process-name process))
      (delete-process process))))

(defun my-org-git-sync-test-run-commit-against-hanging-remote ()
  "Commit a dirty repository whose push hangs, with a one-second watchdog.
Returns a plist with :call-seconds (how long `my-org-git-sync-commit-and-push'
took to return), :in-progress (the guard after the chain settled or ten
seconds passed) and :messages (what the chain reported, newest first)."
  (let* ((root (my-org-git-sync-test-make-repository-with-hanging-remote))
         (process-environment
          (cons (concat "GIT_SSH_COMMAND=" root "hang-ssh") process-environment))
         (my-org-git-sync-command-timeout 1)
         (my-org-git-sync-kill-grace-period 1)
         (my-org-git-sync-commit-in-progress nil)
         (org-directory root)
         (messages nil)
         (started-at (float-time))
         (call-seconds nil))
    (unwind-protect
        (my-org-git-sync-test-with-log-buffer
          (cl-letf (((symbol-function 'message)
                     (lambda (format-string &rest arguments)
                       (push (apply #'format format-string arguments) messages))))
            (my-org-git-sync-commit-and-push root)
            (setq call-seconds (- (float-time) started-at))
            (my-org-git-sync-test-wait-until
             (lambda () (not my-org-git-sync-commit-in-progress)) 10)
            (list :call-seconds call-seconds
                  :in-progress my-org-git-sync-commit-in-progress
                  :messages messages)))
      (my-org-git-sync-test-delete-git-processes)
      (delete-directory root t))))

(ert-deftest my-org-git-sync-test-commit-and-push-returns-while-push-hangs ()
  (skip-unless (executable-find "git"))
  (should (< (plist-get (my-org-git-sync-test-run-commit-against-hanging-remote)
                        :call-seconds)
             1.0)))

(ert-deftest my-org-git-sync-test-commit-and-push-releases-guard-after-push-timeout ()
  (skip-unless (executable-find "git"))
  (should-not (plist-get (my-org-git-sync-test-run-commit-against-hanging-remote)
                         :in-progress)))

(ert-deftest my-org-git-sync-test-commit-and-push-reports-push-failure-after-timeout ()
  (skip-unless (executable-find "git"))
  (should (seq-find (lambda (line) (string-match-p "git push failed" line))
                    (plist-get (my-org-git-sync-test-run-commit-against-hanging-remote)
                               :messages))))

(provide 'my-org-git-sync-test)
;;; my-org-git-sync-test.el ends here
