;;; my-org-git-sync.el --- Fetch Org repositories without prompting -*- lexical-binding: t; -*-

;;; Commentary:
;; Opening an Org file once asked before every `git pull', even when the
;; upstream carried nothing new, so the answer was almost always the same
;; keystroke.  This module splits the pull in two: `git fetch' runs on its
;; own, once per repository per day, and a prompt appears only when the
;; branch actually fell behind its upstream.
;;
;; The fetch runs asynchronously because a slow network would otherwise
;; freeze `find-file'.  The decision logic lives in small functions that
;; take their inputs as arguments so tests/my-org-git-sync-test.el can
;; exercise it without a repository.

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
  (let ((repository-root
         (and (my-org-git-sync-target-file-p
               buffer-file-name major-mode
               (and (boundp 'org-directory) org-directory))
              (my-org-git-sync-locate-repository-root buffer-file-name)))
        (today (format-time-string "%Y-%m-%d")))
    (when (and repository-root
               (not (my-org-git-sync-fetched-today-p
                     repository-root today my-org-git-sync-fetch-dates)))
      (setq my-org-git-sync-fetch-dates
            (my-org-git-sync-record-fetch-date
             repository-root today my-org-git-sync-fetch-dates))
      (my-org-git-sync-start-fetch repository-root))))

(provide 'my-org-git-sync)
;;; my-org-git-sync.el ends here
