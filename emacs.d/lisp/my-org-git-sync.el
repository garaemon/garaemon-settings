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
;; Every git command runs asynchronously because a slow network would
;; otherwise freeze `find-file' or, for the push, the first keystroke after
;; the idle period.  The decision logic lives in
;; small functions that take their inputs as arguments so
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

(defvar my-org-git-sync-auto-commit-timer nil
  "Idle timer that runs the next auto commit, or nil when none is pending.")

(defvar my-org-git-sync-commit-in-progress nil
  "Non-nil while a commit-and-push chain runs.
A second chain started meanwhile would race the first one for the index.")

(defvar my-org-git-sync-command-timeout 120
  "Seconds a single git command may run before it is killed.
Bounds a push that waits on a network that never comes back.")

(defun my-org-git-sync-target-file-p (file mode directory)
  "Return non-nil when FILE opened in MODE is an Org file under DIRECTORY."
  (and file
       (eq mode 'org-mode)
       directory
       (string-prefix-p (expand-file-name directory) (expand-file-name file))))

(defun my-org-git-sync-locate-repository-root (file)
  "Return the Git repository root that holds FILE, or nil when FILE has none."
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

(defun my-org-git-sync-parse-behind-count (output)
  "Return the commit count OUTPUT holds, or nil when OUTPUT holds no count.
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
  (let ((default-directory repository-root)
        (buffer (get-buffer-create my-org-git-sync-buffer-name)))
    (with-current-buffer buffer
      (erase-buffer))
    (if (eq (process-file "git" nil buffer nil "merge" "--ff-only" "@{u}") 0)
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
    (my-org-git-sync-merge-upstream repository-root)))

(defun my-org-git-sync-prompt-merge (repository-root)
  "Count the commits REPOSITORY-ROOT trails by, then offer to merge them."
  (my-org-git-sync-ask-merge repository-root
                             (my-org-git-sync-count-behind-commits repository-root)))

(defun my-org-git-sync-handle-fetch-result (process _event)
  "Offer to merge the repository PROCESS fetched, once the fetch succeeded."
  (when (eq (process-status process) 'exit)
    (let ((repository-root (process-get process 'my-org-git-sync-repository-root)))
      (if (zerop (process-exit-status process))
          ;; Ask from an idle timer.  A sentinel runs in the middle of
          ;; whatever command is active, and a prompt there eats the keys
          ;; meant for that command.
          (run-with-idle-timer my-org-git-sync-prompt-idle-delay nil
                               #'my-org-git-sync-prompt-merge repository-root)
        (message "Org git sync: git fetch failed in %s, see %s"
                 repository-root my-org-git-sync-buffer-name)))))

(defun my-org-git-sync-start-fetch (repository-root)
  "Start a background `git fetch' in REPOSITORY-ROOT."
  (let* ((default-directory repository-root)
         (process (make-process
                   :name "my-org-git-sync-fetch"
                   :command '("git" "fetch" "--quiet")
                   :buffer (get-buffer-create my-org-git-sync-buffer-name)
                   :noquery t
                   :sentinel #'my-org-git-sync-handle-fetch-result)))
    (process-put process 'my-org-git-sync-repository-root repository-root)
    process))

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

(defun my-org-git-sync-build-commit-steps (time)
  "Return the git argument lists that commit and push the changes as of TIME."
  (list '("add" "--all" "--" ".")
        (list "commit" "--quiet" "-m"
              (format-time-string "Auto-commit org changes at %Y-%m-%d %H:%M:%S" time))
        '("push" "--quiet")))

(defun my-org-git-sync-make-non-interactive-environment (environment)
  "Return ENVIRONMENT with git told to fail instead of asking for input.
Without this, a credential or passphrase prompt reads from /dev/tty and
a background command waits there forever.  ENVIRONMENT stays unchanged."
  (cons "GIT_TERMINAL_PROMPT=0" environment))

(defun my-org-git-sync-report-git-exit (process callback)
  "Pass the exit status and the output of PROCESS to CALLBACK."
  (let ((output-start (process-get process 'my-org-git-sync-output-start))
        (buffer (process-buffer process)))
    (funcall callback
             (process-exit-status process)
             (if (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (buffer-substring-no-properties output-start (point-max)))
               ""))))

(defun my-org-git-sync-start-git (repository-root arguments callback)
  "Start `git ARGUMENTS' in REPOSITORY-ROOT and hand its result to CALLBACK.
CALLBACK receives the exit status and the output as a string once the
command ends.  A command still running after
`my-org-git-sync-command-timeout' seconds is killed, which reaches CALLBACK
as a non-zero status."
  (let* ((default-directory repository-root)
         (process-environment
          (my-org-git-sync-make-non-interactive-environment process-environment))
         (buffer (get-buffer-create my-org-git-sync-buffer-name))
         (output-start (with-current-buffer buffer
                         (goto-char (point-max))
                         (insert "$ git " (string-join arguments " ") "\n")
                         (point-max)))
         (process (make-process
                   :name "my-org-git-sync-git"
                   :command (cons "git" arguments)
                   :buffer buffer
                   :noquery t
                   :sentinel #'my-org-git-sync-handle-git-exit))
         (watchdog (run-at-time my-org-git-sync-command-timeout nil
                                #'my-org-git-sync-kill-stuck-git process)))
    (process-put process 'my-org-git-sync-output-start output-start)
    (process-put process 'my-org-git-sync-callback callback)
    (process-put process 'my-org-git-sync-watchdog watchdog)
    process))

(defun my-org-git-sync-kill-stuck-git (process)
  "Kill PROCESS when the command it runs is still going."
  (when (process-live-p process)
    (message "Org git sync: killed a git command after %d seconds"
             my-org-git-sync-command-timeout)
    (delete-process process)))

(defun my-org-git-sync-handle-git-exit (process _event)
  "Run the callback stored on PROCESS once the command is over."
  (when (memq (process-status process) '(exit signal))
    (cancel-timer (process-get process 'my-org-git-sync-watchdog))
    (my-org-git-sync-report-git-exit
     process (process-get process 'my-org-git-sync-callback))))

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

(defun my-org-git-sync-finish-commit (repository-root failed-step)
  "Release the guard and report how the commit of REPOSITORY-ROOT went.
FAILED-STEP is the git argument list that broke the chain, or nil."
  (setq my-org-git-sync-commit-in-progress nil)
  (if failed-step
      (message "Org git sync: git %s failed in %s, see %s"
               (car failed-step) repository-root my-org-git-sync-buffer-name)
    (message "Org git sync: committed and pushed %s" repository-root)))

(defun my-org-git-sync-commit-and-push (repository-root)
  "Commit every change in REPOSITORY-ROOT and push, without blocking Emacs.
Does nothing while an earlier chain still runs or when the tree is clean."
  (unless my-org-git-sync-commit-in-progress
    (setq my-org-git-sync-commit-in-progress t)
    (my-org-git-sync-start-git
     repository-root '("status" "--porcelain")
     (lambda (status output)
       (if (and (zerop status) (my-org-git-sync-changes-p output))
           (my-org-git-sync-run-git-steps
            repository-root
            (my-org-git-sync-build-commit-steps (current-time))
            (lambda (failed-step)
              (my-org-git-sync-finish-commit repository-root failed-step)))
         (setq my-org-git-sync-commit-in-progress nil))))))

(defun my-org-git-sync-schedule-auto-commit ()
  "Commit the repository of the Org file just saved once Emacs goes idle.
A save before the idle delay passes moves the commit further out, so a
burst of edits ends up in one commit."
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
