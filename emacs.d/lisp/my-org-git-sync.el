;;; my-org-git-sync.el --- Fetch Org repositories without prompting -*- lexical-binding: t; -*-

;;; Commentary:
;; Opening an Org file once asked before every `git pull', even when the
;; upstream carried nothing new, so the answer was almost always the same
;; keystroke.  This module splits the pull in two: `git fetch' runs on its
;; own, once per repository per day, and a prompt appears only when the
;; branch actually fell behind its upstream.
;;
;; The same module commits and pushes the repository once Emacs has been
;; idle for a while after a save, so the notes reach the other machines
;; without a manual Magit round.
;;
;; Every command that can wait on the network (the fetch, and the add,
;; commit and push chain) goes through `my-org-git-sync-start-git', which
;; runs git asynchronously with a watchdog, because a slow network would
;; otherwise freeze `find-file' or the first keystroke after the idle
;; period.  The two local commands behind the merge prompt, `git rev-list'
;; and `git merge --ff-only', run synchronously: they never touch the
;; network, and the prompt they lead to blocks anyway.  The decision logic
;; lives in small functions that take their inputs as arguments so
;; tests/my-org-git-sync-test.el can exercise it without a repository.

;;; Code:

(require 'subr-x)
(require 'vc-git)

(defvar my-org-git-sync-fetch-dates nil
  "Alist of (REPOSITORY-ROOT . DATE) recording the last fetch per repository.
DATE is a YYYY-MM-DD string.")

(defvar my-org-git-sync-prompt-idle-delay 1
  "Seconds of idle time to wait before asking about a merge.")

(defconst my-org-git-sync-buffer-name "*org-git-sync*"
  "Buffer that collects the output of the git commands this module runs.")

(defvar my-org-git-sync-auto-commit-idle-delay 300
  "Seconds of idle time after a save before the repository is committed.")

(defvar my-org-git-sync-pending-commit-root nil
  "Root of the repository saved while a chain ran, so another chain must follow.
Nil when no save is waiting.  An idle timer would not do here: one armed
from inside an idle timer fires at once while Emacs stays idle, which turns
the wait into a busy loop.")

(defvar my-org-git-sync-auto-commit-timer nil
  "Idle timer of the last scheduled auto commit, or nil before the first save.
The timer stays here after it fired; cancelling a fired timer is harmless.
One timer serves every repository, so a save in a second repository under
`org-directory' replaces the pending commit of the first.")

(defvar my-org-git-sync-commit-in-progress nil
  "Non-nil while a commit-and-push chain runs, in any repository.
A second chain started meanwhile would race the first one for the index.")

(defvar my-org-git-sync-command-timeout 120
  "Seconds a single git command may run before the watchdog interrupts it.
Bounds a push that waits on a network that never comes back.")

(defvar my-org-git-sync-kill-grace-period 5
  "Seconds between the SIGINT the watchdog sends and the SIGKILL that follows.
Git removes .git/index.lock on SIGINT but not on SIGKILL, and a leftover
lock makes every later `git add' fail.")

(defun my-org-git-sync-target-file-p (file mode directory)
  "Return non-nil when FILE opened in MODE is an Org file under DIRECTORY."
  (and file
       (eq mode 'org-mode)
       directory
       (string-prefix-p (expand-file-name directory) (expand-file-name file))))

(defun my-org-git-sync-locate-repository-root (file)
  "Return the Git repository root of FILE, or nil when FILE has none."
  (when file
    (vc-git-root file)))

(defun my-org-git-sync-locate-current-org-repository ()
  "Return the repository root of the Org file in the current buffer.
Returns nil for a buffer without a file, a non-Org file, a file outside
`org-directory', or a file that no Git repository holds."
  (and (my-org-git-sync-target-file-p
        buffer-file-name major-mode
        (and (boundp 'org-directory) org-directory))
       (my-org-git-sync-locate-repository-root buffer-file-name)))

(defun my-org-git-sync-fetched-today-p (repository-root today dates)
  "Return non-nil when DATES records a fetch of REPOSITORY-ROOT on TODAY."
  (equal (cdr (assoc repository-root dates)) today))

(defun my-org-git-sync-record-fetch-date (repository-root today dates)
  "Return DATES with REPOSITORY-ROOT recorded as fetched on TODAY.
DATES stays unchanged."
  (cons (cons repository-root today)
        (assoc-delete-all repository-root (copy-alist dates))))

(defun my-org-git-sync-append-log (arguments output)
  "Append a `$ git ARGUMENTS' header and OUTPUT to the sync buffer.
OUTPUT gets a final newline when it lacks one, so that the header of the
next command starts on its own line even after an interrupted command."
  (with-current-buffer (get-buffer-create my-org-git-sync-buffer-name)
    (goto-char (point-max))
    (insert "$ git " (string-join arguments " ") "\n" output)
    (unless (or (string-empty-p output) (string-suffix-p "\n" output))
      (insert "\n"))))

(defun my-org-git-sync-find-ssh-command (environment)
  "Return the ssh command ENVIRONMENT names in GIT_SSH_COMMAND, or \"ssh\"."
  (let ((entry (seq-find (lambda (item) (string-prefix-p "GIT_SSH_COMMAND=" item))
                         environment)))
    (if entry
        (substring entry (length "GIT_SSH_COMMAND="))
      "ssh")))

(defun my-org-git-sync-make-non-interactive-environment (environment)
  "Return ENVIRONMENT with git and ssh told to fail instead of asking for input.
Without this, a credential prompt from git, or a passphrase or host-key
prompt from ssh, waits for an answer that never comes.  An ssh command
already set in ENVIRONMENT keeps its options.  Git prefers GIT_SSH_COMMAND
over GIT_SSH and `core.sshCommand', so a key chosen through either of
those is ignored here; choose it in ~/.ssh/config instead.  ENVIRONMENT
stays unchanged."
  (append (list "GIT_TERMINAL_PROMPT=0"
                (concat "GIT_SSH_COMMAND="
                        (my-org-git-sync-find-ssh-command environment)
                        " -oBatchMode=yes"))
          environment))

(defun my-org-git-sync-recover-from-callback-error (arguments err)
  "Log ERR, raised by the callback of `git ARGUMENTS', and unblock the module.
The commit guard is the only state a lost callback can leave behind, so
the guard is released whatever command the callback belonged to.  A
chain that then starts beside one still running fails on .git/index.lock,
which beats a guard that stays set until Emacs restarts."
  (let ((description (error-message-string err)))
    (my-org-git-sync-append-log arguments (concat "callback error: " description))
    (message "Org git sync: the callback of git %s failed: %s, see %s"
             (car arguments) description my-org-git-sync-buffer-name)
    (when my-org-git-sync-commit-in-progress
      (my-org-git-sync-release-commit-guard))))

(defun my-org-git-sync-report-git-exit (process callback)
  "Pass the exit status and the output of PROCESS to CALLBACK.
The output moves from the private buffer of PROCESS to the sync buffer.
An error CALLBACK signals is logged instead of escaping the sentinel."
  (let* ((buffer (process-buffer process))
         (arguments (process-get process 'my-org-git-sync-arguments))
         (output (if (buffer-live-p buffer)
                     (with-current-buffer buffer (buffer-string))
                   "")))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))
    (my-org-git-sync-append-log arguments output)
    (condition-case err
        (funcall callback (process-exit-status process) output)
      (error (my-org-git-sync-recover-from-callback-error arguments err)))))

(defun my-org-git-sync-start-git-process (repository-root arguments callback)
  "Start `git ARGUMENTS' in REPOSITORY-ROOT and return the process.
CALLBACK is stored on the process for `my-org-git-sync-handle-git-exit'.
Signals `file-missing' when git is not on the variable `exec-path'."
  (let* ((default-directory repository-root)
         (process-environment
          (my-org-git-sync-make-non-interactive-environment process-environment))
         ;; A private buffer keeps the output of concurrent commands apart;
         ;; the sentinel copies it to the sync buffer once the command ends.
         (buffer (generate-new-buffer " *org-git-sync-command*"))
         (process (condition-case err
                      (make-process
                       :name "my-org-git-sync-git"
                       :command (cons "git" arguments)
                       :buffer buffer
                       :noquery t
                       ;; On a pty, ssh opens its passphrase prompt on that
                       ;; pty and waits; a pipe leaves ssh no terminal to
                       ;; ask on.
                       :connection-type 'pipe
                       :sentinel #'my-org-git-sync-handle-git-exit)
                    (error
                     (kill-buffer buffer)
                     (signal (car err) (cdr err)))))
         (watchdog (run-at-time my-org-git-sync-command-timeout nil
                                #'my-org-git-sync-interrupt-stuck-git process)))
    (process-put process 'my-org-git-sync-arguments arguments)
    (process-put process 'my-org-git-sync-callback callback)
    (process-put process 'my-org-git-sync-watchdog watchdog)
    process))

(defun my-org-git-sync-start-git (repository-root arguments callback)
  "Start `git ARGUMENTS' in REPOSITORY-ROOT and hand its result to CALLBACK.
CALLBACK receives the exit status and the output as a string once the
command ends.  A command still running after
`my-org-git-sync-command-timeout' seconds is interrupted, which reaches
CALLBACK as a non-zero status.  When git cannot start at all, such as
when git is missing from the variable `exec-path', CALLBACK runs at once
with status 127 (the shell code for a missing command) and the error
message as output, so that a chain never loses its callback."
  (condition-case err
      (my-org-git-sync-start-git-process repository-root arguments callback)
    (error
     (let ((description (error-message-string err)))
       (my-org-git-sync-append-log arguments description)
       (funcall callback 127 description)
       nil))))

(defun my-org-git-sync-interrupt-stuck-git (process)
  "Send SIGINT to a still-running PROCESS, and SIGKILL after the grace period."
  (when (process-live-p process)
    (message "Org git sync: interrupted a git command after %d seconds"
             my-org-git-sync-command-timeout)
    (interrupt-process process)
    (run-at-time my-org-git-sync-kill-grace-period nil
                 #'my-org-git-sync-kill-stuck-git process)))

(defun my-org-git-sync-kill-stuck-git (process)
  "Kill PROCESS when it survived the SIGINT of the watchdog."
  (when (process-live-p process)
    (delete-process process)))

(defun my-org-git-sync-handle-git-exit (process _event)
  "Run the callback stored on PROCESS once the command is over."
  (when (memq (process-status process) '(exit signal))
    (cancel-timer (process-get process 'my-org-git-sync-watchdog))
    (my-org-git-sync-report-git-exit
     process (process-get process 'my-org-git-sync-callback))))

(defun my-org-git-sync-parse-behind-count (output)
  "Return the commit count in OUTPUT, or nil when OUTPUT has no count.
OUTPUT is the whole output of `git rev-list --count', which prints an error
message instead of a number when the branch tracks no upstream."
  (let ((trimmed (string-trim (or output ""))))
    (when (string-match-p "\\`[0-9]+\\'" trimmed)
      (string-to-number trimmed))))

(defun my-org-git-sync-count-behind-commits (repository-root)
  "Return how many commits REPOSITORY-ROOT trails its upstream by.
Returns nil when the branch tracks no upstream."
  (let ((default-directory repository-root))
    (with-temp-buffer
      (let ((status (process-file "git" nil t nil
                                  "rev-list" "--count" "HEAD..@{u}")))
        (when (eq status 0)
          (my-org-git-sync-parse-behind-count (buffer-string)))))))

(defun my-org-git-sync-merge-upstream (repository-root)
  "Merge the upstream branch into REPOSITORY-ROOT, fast-forward only.
A diverged branch is left alone rather than turned into a conflict in the
middle of `find-file'; Magit handles that case better."
  (let* ((default-directory repository-root)
         (arguments '("merge" "--ff-only" "@{u}"))
         (status (with-temp-buffer
                   (prog1 (apply #'process-file "git" nil t nil arguments)
                     (my-org-git-sync-append-log arguments (buffer-string))))))
    (if (eq status 0)
        (message "Org git sync: merged the upstream of %s" repository-root)
      (message "Org git sync: merge failed in %s, see %s"
               repository-root my-org-git-sync-buffer-name))))

(defun my-org-git-sync-ask-merge (repository-root behind-count)
  "Offer to merge REPOSITORY-ROOT when BEHIND-COUNT counts waiting commits.
BEHIND-COUNT is nil when the branch tracks no upstream.  A branch that is
up to date raises no prompt, which is the reason the fetch runs on its own."
  (when (and behind-count
             (> behind-count 0)
             (y-or-n-p (format "Org repository %s is %d commit(s) behind.  Merge? "
                               repository-root behind-count)))
    ;; Idle timers keep running while the prompt waits, so a commit chain
    ;; may have started meanwhile; a merge now would race it for the index.
    (if my-org-git-sync-commit-in-progress
        (my-org-git-sync-report-merge-deferred repository-root)
      (my-org-git-sync-merge-upstream repository-root))))

(defun my-org-git-sync-report-merge-deferred (repository-root)
  "Tell the user that REPOSITORY-ROOT was not merged because a commit runs."
  (message "Org git sync: a commit is running in %s, merge later from Magit"
           repository-root))

(defun my-org-git-sync-prompt-merge (repository-root)
  "Count the commits REPOSITORY-ROOT trails by, then offer to merge them.
While a commit chain runs, the merge would fight it for .git/index.lock,
so the prompt is skipped and the merge left to Magit."
  (if my-org-git-sync-commit-in-progress
      (my-org-git-sync-report-merge-deferred repository-root)
    (my-org-git-sync-ask-merge repository-root
                               (my-org-git-sync-count-behind-commits repository-root))))

(defun my-org-git-sync-handle-fetch-result (repository-root status)
  "Offer to merge REPOSITORY-ROOT once its fetch ended with exit STATUS."
  (if (zerop status)
      ;; Ask from an idle timer.  The result arrives in a process sentinel,
      ;; in the middle of whatever command is active, and a prompt there
      ;; eats the keys meant for that command.
      (run-with-idle-timer my-org-git-sync-prompt-idle-delay nil
                           #'my-org-git-sync-prompt-merge repository-root)
    (message "Org git sync: git fetch failed in %s, see %s"
             repository-root my-org-git-sync-buffer-name)))

(defun my-org-git-sync-start-fetch (repository-root)
  "Start a background `git fetch' in REPOSITORY-ROOT."
  (my-org-git-sync-start-git
   repository-root '("fetch" "--quiet")
   (lambda (status _output)
     (my-org-git-sync-handle-fetch-result repository-root status))))

(defun my-org-git-sync-fetch-on-find-file ()
  "Fetch the repository of the Org file being opened, at most once a day."
  (let ((repository-root (my-org-git-sync-locate-current-org-repository))
        (today (format-time-string "%Y-%m-%d")))
    (when (and repository-root
               (not (my-org-git-sync-fetched-today-p
                     repository-root today my-org-git-sync-fetch-dates)))
      (setq my-org-git-sync-fetch-dates
            (my-org-git-sync-record-fetch-date
             repository-root today my-org-git-sync-fetch-dates))
      (my-org-git-sync-start-fetch repository-root))))

(defun my-org-git-sync-changes-p (status-output)
  "Return non-nil when STATUS-OUTPUT lists a change.
STATUS-OUTPUT is the whole output of `git status --porcelain'."
  (not (string-blank-p (or status-output ""))))

(defun my-org-git-sync-build-commit-pathspec (repository-root directory)
  "Return the pathspec that limits a commit of REPOSITORY-ROOT to DIRECTORY.
DIRECTORY is `org-directory'.  When the Org directory sits inside a larger
repository, the pathspec keeps the unrelated files of that repository out
of the auto commit.  Returns \".\" when DIRECTORY is nil or holds the
repository itself, because git rejects a pathspec outside its work tree."
  (let ((root (file-name-as-directory (expand-file-name repository-root)))
        (org-root (and directory
                       (file-name-as-directory (expand-file-name directory)))))
    (if (and org-root (string-prefix-p root org-root))
        org-root
      ".")))

(defun my-org-git-sync-build-status-arguments (pathspec)
  "Return the `git status' arguments that list the changes under PATHSPEC."
  (list "status" "--porcelain" "--" pathspec))

(defun my-org-git-sync-build-commit-steps (time pathspec)
  "Return the git argument lists that commit and push PATHSPEC as of TIME.
The commit message carries TIME in the local zone."
  (list (list "add" "--all" "--" pathspec)
        (list "commit" "--quiet" "-m"
              (format-time-string "Auto-commit org changes at %Y-%m-%d %H:%M:%S" time))
        '("push" "--quiet")))

(defun my-org-git-sync-run-git-steps (repository-root steps on-finish)
  "Run the git argument lists in STEPS one after another in REPOSITORY-ROOT.
The chain stops at the first command that exits with a non-zero status.
ON-FINISH receives that command's argument list, or nil when every step
succeeded."
  (if (null steps)
      (funcall on-finish nil)
    (my-org-git-sync-start-git
     repository-root (car steps)
     (lambda (status _output)
       (if (zerop status)
           (my-org-git-sync-run-git-steps repository-root (cdr steps) on-finish)
         (funcall on-finish (car steps)))))))

(defun my-org-git-sync-release-commit-guard ()
  "Let the next chain run.
The chain of the repository saved while the last chain was busy, if any,
starts at once."
  (setq my-org-git-sync-commit-in-progress nil)
  (when my-org-git-sync-pending-commit-root
    (let ((pending-repository-root my-org-git-sync-pending-commit-root))
      (setq my-org-git-sync-pending-commit-root nil)
      (my-org-git-sync-commit-and-push pending-repository-root))))

(defun my-org-git-sync-finish-commit (repository-root failed-step)
  "Release the guard and report how the commit of REPOSITORY-ROOT went.
FAILED-STEP is the git argument list that broke the chain, or nil."
  (if failed-step
      (message "Org git sync: git %s failed in %s, see %s"
               (car failed-step) repository-root my-org-git-sync-buffer-name)
    (message "Org git sync: committed and pushed %s" repository-root))
  (my-org-git-sync-release-commit-guard))

(defun my-org-git-sync-commit-changes (repository-root pathspec status output)
  "Commit and push PATHSPEC in REPOSITORY-ROOT after `git status' ended.
STATUS and OUTPUT are the exit status and the output of that status
command.  A clean tree ends the chain here quietly; a status command that
failed ends it with a message, since a stale .git/index.lock would
otherwise stop every auto commit without a word."
  (cond
   ((not (zerop status))
    (message "Org git sync: git status failed in %s, see %s"
             repository-root my-org-git-sync-buffer-name)
    (my-org-git-sync-release-commit-guard))
   ((my-org-git-sync-changes-p output)
    (my-org-git-sync-run-git-steps
     repository-root
     (my-org-git-sync-build-commit-steps (current-time) pathspec)
     (lambda (failed-step)
       (my-org-git-sync-finish-commit repository-root failed-step))))
   (t
    (my-org-git-sync-release-commit-guard))))

(defun my-org-git-sync-commit-and-push (repository-root)
  "Commit every change in REPOSITORY-ROOT and push, without blocking Emacs.
While an earlier chain still runs, the request is kept as pending and the
chain that ends starts the next one, so a save made during a slow push
still reaches the remote."
  (if my-org-git-sync-commit-in-progress
      (setq my-org-git-sync-pending-commit-root repository-root)
    (setq my-org-git-sync-commit-in-progress t)
    (let ((pathspec (my-org-git-sync-build-commit-pathspec
                     repository-root
                     (and (boundp 'org-directory) org-directory))))
      (my-org-git-sync-start-git
       repository-root (my-org-git-sync-build-status-arguments pathspec)
       (lambda (status output)
         (my-org-git-sync-commit-changes repository-root pathspec status output))))))

(defun my-org-git-sync-reset ()
  "Forget a commit chain that never reported back, so auto commits resume.
For the case no code path foresaw; `my-org-git-sync-recover-from-callback-error'
covers the ones this module knows about."
  (interactive)
  (setq my-org-git-sync-commit-in-progress nil)
  (setq my-org-git-sync-pending-commit-root nil)
  (message "Org git sync: reset, the next save schedules a commit again"))

(defun my-org-git-sync-schedule-auto-commit ()
  "Commit the repository of the Org file just saved once Emacs goes idle.
A timer still pending is replaced, so a burst of saves ends up in one commit."
  (let ((repository-root (my-org-git-sync-locate-current-org-repository)))
    (when repository-root
      (when my-org-git-sync-auto-commit-timer
        (cancel-timer my-org-git-sync-auto-commit-timer))
      (setq my-org-git-sync-auto-commit-timer
            (run-with-idle-timer my-org-git-sync-auto-commit-idle-delay nil
                                 #'my-org-git-sync-commit-and-push
                                 repository-root)))))

(provide 'my-org-git-sync)
;;; my-org-git-sync.el ends here
