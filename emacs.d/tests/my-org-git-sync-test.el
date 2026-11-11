;;; my-org-git-sync-test.el --- Tests for the Org git pull and push flow -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-git-sync.el.  Three rules are under test: opening
;; an Org file pulls without asking, at most once per interval; a save leads
;; to one commit, pull and push chain at a time; and a chain never blocks
;; Emacs.
;;
;; Only the tests that call `my-org-git-sync-start-git' unstubbed run git,
;; against a temporary repository or with `git --version'.  Everywhere
;; else the command output arrives as a string, and the pull and commit
;; tests stub `my-org-git-sync-start-git' with `cl-letf'.  Run with:
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

(ert-deftest my-org-git-sync-test-record-pull-time-adds-repository ()
  (should (equal (my-org-git-sync-record-pull-time "/org/" 1000.0 nil)
                 '(("/org/" . 1000.0)))))

(ert-deftest my-org-git-sync-test-record-pull-time-replaces-old-time ()
  (should (equal (my-org-git-sync-record-pull-time
                  "/org/" 1000.0 '(("/org/" . 100.0)))
                 '(("/org/" . 1000.0)))))

(ert-deftest my-org-git-sync-test-record-pull-time-keeps-input-unchanged ()
  (let ((times '(("/org/" . 100.0))))
    (my-org-git-sync-record-pull-time "/org/" 1000.0 times)
    (should (equal times '(("/org/" . 100.0))))))

(ert-deftest my-org-git-sync-test-pulled-recently-p-accepts-pull-inside-interval ()
  (should (my-org-git-sync-pulled-recently-p
           "/org/" 1000.0 '(("/org/" . 500.0)) 600)))

(ert-deftest my-org-git-sync-test-pulled-recently-p-rejects-pull-before-interval ()
  (should-not (my-org-git-sync-pulled-recently-p
               "/org/" 1000.0 '(("/org/" . 300.0)) 600)))

(ert-deftest my-org-git-sync-test-pulled-recently-p-rejects-unknown-repository ()
  (should-not (my-org-git-sync-pulled-recently-p "/org/" 1000.0 nil 600)))

(ert-deftest my-org-git-sync-test-target-file-p-accepts-org-file-in-directory ()
  (should (my-org-git-sync-target-file-p "/org/notes.org" 'org-mode "/org/")))

(ert-deftest my-org-git-sync-test-target-file-p-rejects-other-major-mode ()
  (should-not (my-org-git-sync-target-file-p "/org/notes.org" 'text-mode "/org/")))

(ert-deftest my-org-git-sync-test-target-file-p-rejects-file-outside-directory ()
  (should-not (my-org-git-sync-target-file-p "/tmp/notes.org" 'org-mode "/org/")))

(ert-deftest my-org-git-sync-test-target-file-p-rejects-buffer-without-file ()
  (should-not (my-org-git-sync-target-file-p nil 'org-mode "/org/")))

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

(ert-deftest my-org-git-sync-test-build-commit-steps-pulls-before-push ()
  (should (equal (mapcar #'car (my-org-git-sync-build-commit-steps
                                (encode-time '(0 0 0 1 1 2026 nil -1 nil))
                                "/org/"))
                 '("add" "commit" "pull" "push"))))

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

(ert-deftest my-org-git-sync-test-finish-commit-aborts-rebase-when-pull-failed ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-finish-commit "/org/" my-org-git-sync-pull-arguments)
      (should (equal my-org-git-sync-test-recorded-arguments
                     '(("rebase" "--abort")))))))

(ert-deftest my-org-git-sync-test-finish-commit-keeps-rebase-state-when-push-failed ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-finish-commit "/org/" '("push" "--quiet"))
      (should-not my-org-git-sync-test-recorded-arguments))))

(ert-deftest my-org-git-sync-test-finish-commit-releases-guard-after-rebase-abort ()
  (let ((my-org-git-sync-commit-in-progress t)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-finish-commit "/org/" my-org-git-sync-pull-arguments)
      (should-not my-org-git-sync-commit-in-progress))))

(ert-deftest my-org-git-sync-test-pull-runs-rebasing-pull ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git)))
      (my-org-git-sync-pull "/org/")
      (should (equal my-org-git-sync-test-recorded-arguments
                     '(("pull" "--rebase" "--autostash" "--quiet")))))))

(ert-deftest my-org-git-sync-test-pull-releases-guard-when-done ()
  (let ((my-org-git-sync-commit-in-progress nil)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git)))
      (my-org-git-sync-pull "/org/")
      (should-not my-org-git-sync-commit-in-progress))))

(ert-deftest my-org-git-sync-test-pull-stays-quiet-when-pull-succeeds ()
  (let ((my-org-git-sync-commit-in-progress nil)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git))
              ((symbol-function 'message)
               (lambda (&rest _) (error "Reported a pull that brought no news"))))
      (my-org-git-sync-pull "/org/"))))

(ert-deftest my-org-git-sync-test-pull-aborts-rebase-when-pull-fails ()
  (let ((my-org-git-sync-test-recorded-arguments nil)
        (my-org-git-sync-commit-in-progress nil)
        (my-org-git-sync-pending-commit-root nil))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (my-org-git-sync-test-stub-start-git my-org-git-sync-pull-arguments))
              ((symbol-function 'message) #'ignore))
      (my-org-git-sync-pull "/org/")
      (should (equal (car (last my-org-git-sync-test-recorded-arguments))
                     '("rebase" "--abort"))))))

(ert-deftest my-org-git-sync-test-pull-skips-while-chain-runs ()
  (let ((my-org-git-sync-commit-in-progress t))
    (cl-letf (((symbol-function 'my-org-git-sync-start-git)
               (lambda (&rest _) (error "Pulled during another chain"))))
      (my-org-git-sync-pull "/org/"))))

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
  "Create a git repository whose remote hangs, and return its root.
The remote uses ssh, and the returned root holds a `hang-ssh' script that
sleeps instead of connecting.  Pointing GIT_SSH_COMMAND at that script makes
`git pull' hang the way it does on a network that is down."
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
  "Commit a dirty repository whose pull hangs, with a one-second watchdog.
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

(ert-deftest my-org-git-sync-test-commit-and-push-returns-while-pull-hangs ()
  (skip-unless (executable-find "git"))
  (should (< (plist-get (my-org-git-sync-test-run-commit-against-hanging-remote)
                        :call-seconds)
             1.0)))

(ert-deftest my-org-git-sync-test-commit-and-push-releases-guard-after-pull-timeout ()
  (skip-unless (executable-find "git"))
  (should-not (plist-get (my-org-git-sync-test-run-commit-against-hanging-remote)
                         :in-progress)))

(ert-deftest my-org-git-sync-test-commit-and-push-reports-pull-failure-after-timeout ()
  (skip-unless (executable-find "git"))
  (should (seq-find (lambda (line) (string-match-p "git pull failed" line))
                    (plist-get (my-org-git-sync-test-run-commit-against-hanging-remote)
                               :messages))))

(defun my-org-git-sync-test-run-git-in (directory &rest arguments)
  "Run `git ARGUMENTS' in DIRECTORY and return its output."
  (let ((default-directory (file-name-as-directory directory)))
    (with-temp-buffer
      (apply #'call-process "git" nil t nil
             "-c" "user.email=test@example.com" "-c" "user.name=Test"
             "-c" "commit.gpgsign=false" arguments)
      (buffer-string))))

(defun my-org-git-sync-test-make-clone-behind-remote (sandbox)
  "Create a bare remote and a clone one commit behind it under SANDBOX.
Returns the root of the clone.  The remote is SANDBOX/remote.git."
  (let ((remote (concat sandbox "remote.git"))
        (clone (concat sandbox "org/"))
        (other-clone (concat sandbox "other/")))
    (my-org-git-sync-test-run-git-in sandbox "init" "--quiet" "--bare" "-b" "main" remote)
    (my-org-git-sync-test-run-git-in sandbox "clone" "--quiet" remote clone)
    (dolist (key-value '(("user.email" "test@example.com") ("user.name" "Test")
                         ("commit.gpgsign" "false")))
      (apply #'my-org-git-sync-test-run-git-in clone "config" key-value))
    (with-temp-file (concat clone "seed.org") (insert "* Seed\n"))
    (my-org-git-sync-test-run-git-in clone "add" "seed.org")
    (my-org-git-sync-test-run-git-in clone "commit" "--quiet" "-m" "Seed")
    (my-org-git-sync-test-run-git-in clone "push" "--quiet" "-u" "origin" "main")
    (my-org-git-sync-test-run-git-in sandbox "clone" "--quiet" remote other-clone)
    (with-temp-file (concat other-clone "other.org") (insert "* Other machine\n"))
    (my-org-git-sync-test-run-git-in other-clone "add" "other.org")
    (my-org-git-sync-test-run-git-in other-clone "commit" "--quiet" "-m" "Other")
    (my-org-git-sync-test-run-git-in other-clone "push" "--quiet")
    clone))

(defun my-org-git-sync-test-list-remote-files-after-commit ()
  "Commit a new note in a clone that trails its remote, and wait for the chain.
Returns the files on the main branch of the remote, one per line."
  (let* ((sandbox (file-name-as-directory (make-temp-file "org-git-sync" t)))
         (clone (my-org-git-sync-test-make-clone-behind-remote sandbox))
         (my-org-git-sync-commit-in-progress nil)
         (my-org-git-sync-pending-commit-root nil)
         (org-directory clone))
    (unwind-protect
        (my-org-git-sync-test-with-log-buffer
          (with-temp-file (concat clone "notes.org") (insert "* Note\n"))
          (cl-letf (((symbol-function 'message) #'ignore))
            (my-org-git-sync-commit-and-push clone)
            (my-org-git-sync-test-wait-until
             (lambda () (not my-org-git-sync-commit-in-progress)) 30))
          (my-org-git-sync-test-run-git-in
           (concat sandbox "remote.git") "ls-tree" "--name-only" "main"))
      (my-org-git-sync-test-delete-git-processes)
      (delete-directory sandbox t))))

(ert-deftest my-org-git-sync-test-commit-and-push-rebases-onto-moved-remote ()
  (skip-unless (executable-find "git"))
  (should (equal (my-org-git-sync-test-list-remote-files-after-commit)
                 "notes.org\nother.org\nseed.org\n")))

(provide 'my-org-git-sync-test)
;;; my-org-git-sync-test.el ends here
