;;; init-git.el --- Git, magit and forge integration -*- lexical-binding: t -*-

;;; Commentary:
;; magit, forge, the AI commit-message and diff-hl review helpers, git-commit
;; and browse-at-remote.

;;; Code:

(use-package magit :ensure t
  ;; (magit-refresh-status-buffer nil)
  :bind (("\C-cl" . 'magit-status)
         ("\C-cL" . 'my-magit-status-side-window)
         ("\C-cm" . 'magit-dispatch))
  :custom
  ;; When we visit a file from magit diff view, open the files on the disk rather than the read-only
  ;; buffers.
  (magit-diff-visit-prefer-worktree t)
  :config
  ;; homebrew's git is faster than apple's git.
  ;; https://gregnewman.io/blog/speed-up-magit-on-macos/
  (if (file-exists-p "/opt/homebrew/bin/git")
      (setq magit-git-executable "/opt/homebrew/bin/git"))

  ;; Function to check if we're in a TRAMP environment
  (defun my-is-tramp-directory-p ()
    "Return t if the current directory is accessed via TRAMP."
    (and (fboundp 'file-remote-p)
         (file-remote-p default-directory)))

  ;; Function to disable magit features for TRAMP environments
  (defun my-disable-magit-features-for-tramp ()
    "Disable expensive magit features when in TRAMP environment."
    (when (my-is-tramp-directory-p)
      (message "Disable some magit features for TRAMP environment")
      ;; don't show the diff by default in the commit buffer. Use `C-c C-d' to display it
      (setq-local magit-commit-show-diff nil)
      ;; don't show git variables in magit branch
      (setq-local magit-branch-direct-configure nil)
      ;; don't automatically refresh the status buffer after running a git command
      (setq-local magit-refresh-status-buffer nil)))

  ;; Hook to apply TRAMP-specific settings
  (add-hook 'magit-mode-hook 'my-disable-magit-features-for-tramp)

  ;; The following configuration is recommended to improve the performance of magit.
  ;; Only remove hooks when in TRAMP environment
  (defun my-remove-magit-hooks-for-tramp ()
    "Remove expensive magit hooks when in TRAMP environment."
    (when (my-is-tramp-directory-p)
      (message "Disable some magit features for TRAMP environment")
      (remove-hook 'magit-status-sections-hook 'magit-insert-tags-header)
      ;;(remove-hook 'magit-status-sections-hook 'magit-insert-status-headers)
      (remove-hook 'magit-status-sections-hook 'magit-insert-unpushed-to-pushremote)
      (remove-hook 'magit-status-sections-hook 'magit-insert-unpulled-from-pushremote)
      (remove-hook 'magit-status-sections-hook 'magit-insert-unpulled-from-upstream)
      (remove-hook 'magit-status-sections-hook 'magit-insert-unpushed-to-upstream-or-recent)))

  ;; Apply hook removal when magit status is opened
  (add-hook 'magit-status-mode-hook 'my-remove-magit-hooks-for-tramp)
  ;; Rewrite magit-branch-read-args to automatically insert YYYY.MM.DD- as prefix
  ;; of new branch names.
  (defun magit-branch-read-args (prompt &optional default-start)
    (if magit-branch-read-upstream-first
        (let ((choice (magit-read-starting-point prompt nil default-start)))
          (cond
           ((magit-rev-verify choice)
            (list (magit-read-string-ns
                   (if magit-completing-read--silent-default
                       (format "%s (starting at `%s')" prompt choice)
                     "Name for new branch")
                   (or
                    ;; Original implementation
                    (let ((def (string-join (cdr (split-string choice "/")) "/")))
                      (and (member choice (magit-list-remote-branch-names))
                           (not (member def (magit-list-local-branch-names)))
                           def))
                    ;; Patch zone. If the original implementation returns nil, we use
                    ;; YYYY.MM.DD- prefix as default.
                    (format-time-string "%Y.%m.%d-")
                    ))
                  choice))
           ((eq magit-branch-read-upstream-first 'fallback)
            (list choice
                  (magit-read-starting-point prompt choice default-start)))
           ((user-error "Not a valid starting-point: %s" choice))))
      (let ((branch (magit-read-string-ns (concat prompt " named"))))
        (if (magit-branch-p branch)
            (magit-branch-read-args
             (format "Branch `%s' already exists; pick another name" branch)
             default-start)
          (list branch (magit-read-starting-point prompt branch default-start))))))

  (let ((socket-dir (expand-file-name "~/.ssh/sockets")))
    ;; Make a socket directory if it does not exist
    (unless (file-directory-p socket-dir)
      (make-directory socket-dir t))

    ;; 1Password's SSH agent requires per-process authentication, which means every git command
    ;; magit runs (pull, push, fetch, etc.) triggers a separate 1Password auth prompt. This happens
    ;; because 1Password cannot recognize multiple git processes spawned by Emacs as coming from the
    ;; same application. To work around this, we enable SSH connection multiplexing with a short
    ;; ControlPersist timeout (45s) so that subsequent git commands reuse the already-authenticated
    ;; SSH connection.
    (setq magit-git-global-arguments
          (append magit-git-global-arguments
                  `("-c" ,(concat "core.sshCommand=ssh "
                                  "-o ControlMaster=auto "
                                  "-o ControlPath=" socket-dir "/%r@%h:%p "
                                  "-o ControlPersist=45s")))))
  (require 'my-magit-ediff)

  (with-eval-after-load 'magit-log
    (define-key magit-log-mode-map (kbd "C-c r")
                #'my-diff-hl-set-reference-from-magit))

  (defun my--git-commit-llm-after-setup ()
    "One-shot git-commit-setup-hook that prepends git-commit-llm output to the
commit buffer being set up."
    (remove-hook 'git-commit-setup-hook #'my--git-commit-llm-after-setup)
    (let ((commit-buffer (current-buffer)))
      (message "git-commit-llm: generating...")
      (with-temp-buffer
        (let ((exit-code (call-process "git-commit-llm" nil t nil "--print-only")))
          (unless (zerop exit-code)
            (error "git-commit-llm failed (exit %d): %s"
                   exit-code (buffer-string)))
          (let ((generated (string-trim (buffer-string))))
            (when (buffer-live-p commit-buffer)
              (with-current-buffer commit-buffer
                (save-excursion
                  (goto-char (point-min))
                  (insert generated "\n")))))))
      ;; git-commit-setup calls (set-buffer-modified-p nil) right after the
      ;; setup hook returns, which would cause C-c C-c to skip save-buffer.
      ;; Restore the modified flag once setup is done.
      (run-at-time 0 nil
                   (lambda ()
                     (when (buffer-live-p commit-buffer)
                       (with-current-buffer commit-buffer
                         (set-buffer-modified-p t)))))))

  (defun my-run-git-commit-llm ()
    "Start a commit and auto-prepend a git-commit-llm-generated message."
    (interactive)
    (add-hook 'git-commit-setup-hook #'my--git-commit-llm-after-setup)
    (magit-commit-create))

  (with-eval-after-load 'magit-commit
    (transient-append-suffix 'magit-commit '(0 -1)
      '("L" "Generate with git-commit-llm" my-run-git-commit-llm)))
  )

(use-package gptel-magit
  :ensure t
  :custom
  (gptel-magit-model 'gemma3:4b)
  (gptel-magit-backend (gptel-make-ollama "Ollama (gemmma3:4b)"
                         :host "localhost:11434"
                         :stream t
                         :models '(gemma3:4b)))
  (gptel-magit-commit-prompt
   "You are a programmer. Based on the Git diff provided below, generate a concise and clear English commit message.
You reply the commit message only.

The first line should be a brief summary (recommended < 50 characters), followed by an empty line, and then a more detailed description from the third line onwards.
Use bullet points in the detailed description of the commit message.

The detailed description should include:
- What changes were made
- Why the changes were made (purpose, background)
- Any impact of the changes (if applicable)
- Use imperative mood in the subject line
- Wrap the body at 72 characters
- Use hanging indent in the bullet points

<example>
Fix typo: landry -> laundry
</example>
<example>
Fix symlink paths to work in CI environment

Use playbook_dir in CI environments instead of ghq_root_path to ensure
symlinks work correctly during PR tests where the repository is checked
out to a different location.

- Add CI environment detection in ghq role
- Introduce ghq_settings_root variable that uses playbook_dir in CI
- Replace all ghq_root_path-based symlink paths with ghq_settings_root
- Ensure compatibility with local, remote, and CI execution environments
</example>
<example>
Add keyd role for keyboard remapping

- Add keyd role to manage keyboard remapping daemon
- Install keyd package via apt
- Deploy default configuration for key mappings
- Add systemd service management with restart handler
- Enable keyd role for Debian-based systems
</example>
")
  :config
  ;; Override to prevent fill-region from breaking bullet point formatting.
  ;; The LLM prompt already specifies 72-char wrapping and hanging indent.
  (defun gptel-magit--format-commit-message (message)
    "Format commit message MESSAGE.
Only truncate the title line to `git-commit-summary-max-length'."
    (if (not (stringp message))
        (or message "")
      (with-temp-buffer
        (insert message)
        (goto-char (point-min))
        (let ((title-end (line-end-position)))
          (when (> (- title-end (point-min)) git-commit-summary-max-length)
            (let ((fill-column git-commit-summary-max-length))
              (fill-region (point-min) title-end))))
        (buffer-string))))
  ;; Override to show a user-friendly error when LLM is unreachable.
  (defun gptel-magit--generate (callback)
    "Generate a commit message for current magit repo.
Invokes CALLBACK with the generated message when done."
    (let ((diff (magit-git-output "diff" "--cached")))
      (gptel-magit--request diff
                            :system gptel-magit-commit-prompt
                            :context nil
                            :callback (lambda (response info)
                                        (if (not (stringp response))
                                            (let ((status (plist-get info :status)))
                                              (message "gptel-magit: Failed to generate commit message. \
Is Ollama running? (ollama serve) Status: %s" status))
                                          (let ((msg (gptel-magit--format-commit-message response)))
                                            (funcall callback msg)))))))
  :hook (magit-mode . gptel-magit-install))

(use-package forge
  :after magit
  ;; Demand-load forge as soon as magit loads.  The auto forge-pull hook below
  ;; lives in this :config block, so forge must be loaded for the hook to be
  ;; registered before the first magit-status buffer is created.  With plain
  ;; :after (deferred) forge would not load until a forge command runs, so the
  ;; hook would be missing on the first magit-status of the session.
  :demand t
  :ensure t
  ;; How to setup forge:
  ;;   1. configure github.user by following command:
  ;;     git config --global github.user garaemon
  ;;   2. Create ~/.authinfo file and write an entry like:
  ;;     machine api.github.com login garaemon^forge password {token}
  ;;     Alternatively, create a 1Password item with hostname=api.github.com and a field named
  ;;     garaemon-forge containing the key.
  ;;     The scope of token to be enabled are
  ;;       1. repo
  ;;       2. user
  ;;       3. read:org
  :custom
  (forge-owned-accounts '(("garaemon")))
  :bind (("C-c M r" . my-diff-hl-review-enable)
         ("C-c M s" . my-diff-hl-review-disable)
         ("C-c M d" . my-diff-hl-set-reference)
         ("C-c M e" . my-forge-ediff-pullreq-at-point)
         ("C-c M c" . my-forge-ediff-review-add-comment)
         ("C-c M m" . my-forge-ediff-review-add-memo)
         ("C-c M f" . my-forge-ediff-review-toggle-reviewed)
         ("C-c M l" . my-forge-ediff-review-list-comments)
         ("C-c M C" . my-forge-ediff-review-submit))
  :config
  (require 'my-forge-ediff-review)

  (defun my-forge-ediff-pullreq-at-point ()
    "Open the forge PR at point in a side-by-side ediff review session.
Compares the PR's base commit against its head commit and lets you
collect inline comments via `my-forge-ediff-review-add-comment'."
    (interactive)
    (let ((pullreq (or (forge-pullreq-at-point)
                       (and (fboundp 'forge-current-topic)
                            (forge-current-topic)))))
      (unless (and pullreq (forge-pullreq-p pullreq))
        (user-error "No forge pull request at point"))
      (my-forge-ediff-review-start pullreq)))

  (defun my-forge-create-pullreq ()
    (interactive)
    (call-interactively 'forge-create-pullreq)
    ;; Insert the last commit to the current buffer.
    ;; After calling forge-create-pullreq, the current buffer should be a buffer to edit the title
    ;; and the description of the new pull request.
    (magit-git-insert "log" "-1" "--pretty=%B")
    )
  (remove-hook 'forge-post-mode-hook 'turn-on-flyspell)

  ;; Automatically run forge-pull when pulling via magit so that
  ;; PR/issue data stays in sync with the git history.
  (defun my-forge-pull-after-magit-pull (&rest _)
    "Run `forge-pull' after magit pull if the repository is tracked by forge."
    (when (ignore-errors (forge-get-repository :tracked))
      (forge-pull)))
  (advice-add 'magit-pull-from-upstream :after #'my-forge-pull-after-magit-pull)
  (advice-add 'magit-pull-from-pushremote :after #'my-forge-pull-after-magit-pull)

  ;; Forge does not refresh its data on its own, so opening magit-status shows
  ;; stale (or empty) PR/issue sections until a manual `forge-pull'.  Pull once
  ;; per repository per Emacs session the first time its status buffer is
  ;; opened.  The pull is asynchronous and refreshes the buffer when it
  ;; finishes, and the per-session guard keeps it from hammering the GitHub API.
  (defvar my-forge--session-pulled-repos (make-hash-table :test 'equal)
    "Repository roots already forge-pulled during this Emacs session.")

  (defun my-forge-pull-once-per-session ()
    "Run `forge-pull' the first time a tracked repository's status is shown."
    (when (ignore-errors (forge-get-repository :tracked))
      (let ((repository-root (magit-toplevel)))
        (when (and repository-root
                   (not (gethash repository-root my-forge--session-pulled-repos)))
          (puthash repository-root t my-forge--session-pulled-repos)
          (forge-pull)))))

  (add-hook 'magit-status-mode-hook #'my-forge-pull-once-per-session)

  ;; PR review mode using diff-hl:
  ;;   Overrides `diff-hl-reference-revision' to show PR changes (vs base branch) in fringe.
  ;;   Usage:
  ;;     1. Checkout the PR branch and run `forge-pull'
  ;;     2. M-x my-diff-hl-review-enable (C-c M r)
  ;;        -> Automatically detects base branch from forge DB
  ;;        -> Mode-line shows " Review" in all project buffers
  ;;     3. M-x my-diff-hl-review-disable (C-c M s) to stop
  (defvar my-diff-hl-review--project nil
    "Project root currently in review mode.")
  (defvar my-diff-hl-review--revision nil
    "Reference revision for review mode.")

  (define-minor-mode my-diff-hl-review-mode
    "Minor mode indicating diff-hl review is active in this buffer."
    :lighter (:eval (if my-diff-hl-review--revision
                        (format " Diff[%s]"
                                (truncate-string-to-width
                                 my-diff-hl-review--revision 12))
                      " Diff[?]")))

  (defun my-diff-hl-review--apply-to-buffer ()
    "Apply review mode to the current buffer if it belongs to the review project."
    (when (and my-diff-hl-review--project
               buffer-file-name
               (string-prefix-p my-diff-hl-review--project
                                (expand-file-name buffer-file-name)))
      (setq-local diff-hl-reference-revision my-diff-hl-review--revision)
      (my-diff-hl-review-mode 1)
      (when (bound-and-true-p diff-hl-mode)
        (diff-hl-update))))

  (defun my-diff-hl-review--update-all-buffers (revision)
    "Set diff-hl reference to REVISION in all project buffers and toggle review mode."
    (let ((root (expand-file-name (project-root (project-current t)))))
      (dolist (buf (buffer-list))
        (with-current-buffer buf
          (when (and buffer-file-name
                     (string-prefix-p root (expand-file-name buffer-file-name)))
            (setq-local diff-hl-reference-revision revision)
            (if revision
                (my-diff-hl-review-mode 1)
              (my-diff-hl-review-mode -1))
            (when (bound-and-true-p diff-hl-mode)
              (diff-hl-update)))))))

  (defun my-diff-hl-review--find-base-ref ()
    "Find base-ref for the current branch from forge DB, or ask user."
    (let* ((branch (magit-get-current-branch))
           ;; Try forge git config first, then search by head-ref in DB
           (pullreq (or (forge-get-pullreq :branch branch)
                        (let* ((repo (forge-get-repository :tracked))
                               (rows (forge-sql [:select [number]
                                                         :from pullreq
                                                         :where (and (= repository $s1)
                                                                     (= head-ref $s2))]
                                                (oref repo id)
                                                branch)))
                          (when rows
                            (forge-get-pullreq repo (caar rows)))))))
      (if pullreq
          (oref pullreq base-ref)
        (magit-read-branch "Base branch for review"))))

  (defun my-diff-hl-review-enable ()
    "Enable review mode using the current branch's PR base as reference."
    (interactive)
    (let* ((base-ref (my-diff-hl-review--find-base-ref))
           (revision (concat "origin/" base-ref)))
      (my-diff-hl--apply-revision revision)))

  (defun my-diff-hl-review-disable ()
    "Disable review mode and restore normal diff-hl behavior."
    (interactive)
    (my-diff-hl-review--update-all-buffers nil)
    (remove-hook 'find-file-hook #'my-diff-hl-review--apply-to-buffer)
    (setq my-diff-hl-review--project nil)
    (setq my-diff-hl-review--revision nil)
    (message "Review mode disabled"))

  ;; General-purpose diff-hl reference selector using consult.
  ;; Select any commit or branch as baseline; changes after it are shown in fringe.
  (defun my-diff-hl--build-candidates ()
    "Build candidate list: reset option, then commits, then branches."
    (let* ((default-directory (if buffer-file-name
                                  (file-name-directory buffer-file-name)
                                default-directory))
           (default-directory (or (magit-toplevel) default-directory))
           (branches (magit-list-branch-names))
           (commits (magit-git-lines "log" "--oneline" "-50")))
      (append '("HEAD (reset to default)")
              commits
              (mapcar (lambda (b) (concat "branch: " b)) branches))))

  (defun my-diff-hl--extract-revision (selected)
    "Extract git revision string from SELECTED candidate."
    (cond
     ((string-prefix-p "branch: " selected)
      (substring selected 8))
     (t
      (car (split-string selected " ")))))

  (defun my-diff-hl--apply-revision (revision)
    "Apply REVISION as diff-hl baseline for the current project."
    (setq my-diff-hl-review--project
          (expand-file-name (project-root (project-current t))))
    (setq my-diff-hl-review--revision revision)
    (my-diff-hl-review--update-all-buffers revision)
    (add-hook 'find-file-hook #'my-diff-hl-review--apply-to-buffer)
    (message "diff-hl baseline: %s" revision))

  (defun my-diff-hl-set-reference ()
    "Select a git commit as the baseline for diff-hl.
Changes AFTER the selected commit are shown in the fringe (exclusive)."
    (interactive)
    (let* ((candidates (my-diff-hl--build-candidates))
           (selected (consult--read
                      candidates
                      :prompt "Baseline (changes AFTER this are shown): "
                      :sort nil
                      :require-match t)))
      (if (string= selected "HEAD (reset to default)")
          (my-diff-hl-review-disable)
        (my-diff-hl--apply-revision
         (my-diff-hl--extract-revision selected)))))

  (defun my-diff-hl-set-reference-from-magit ()
    "Set the commit at point in magit-log as diff-hl baseline."
    (interactive)
    (let ((commit (magit-commit-at-point)))
      (unless commit
        (user-error "No commit at point"))
      (my-diff-hl--apply-revision commit)))
  )

;; GitHub PR reviews from inside Emacs.
;; Uses the doomelpa fork because the upstream wandersoncferreira/code-review
;; has been largely inactive; doomelpa carries fixes for current forge/ghub.
;;
;; Auth reuses the same ~/.authinfo entry that forge uses (api.github.com login
;; <user>^forge). No additional setup required when forge already works.
;;
;; Usage:
;;   - From a forge topic buffer (e.g. magit-status PR list, RET on a PR),
;;     press `C-c M v` to open the PR in code-review.
;;   - Or `M-x code-review-start` and paste a PR URL.
;;   - Inside the review buffer:
;;       RET on a hunk -> add an inline comment
;;       r            -> transient menu (approve / request-changes / comment)
;;     For a side-by-side view of a single hunk, split the window
;;     horizontally (`C-x 3`) and visit the file with `magit-diff-visit-file`
;;     in the other window; comments stay in the code-review buffer.
(use-package code-review
  :vc (:url "https://github.com/doomelpa/code-review.git" :rev :newest)
  :after forge
  :bind (("C-c M v" . code-review-forge-pr-at-point))
  :custom
  ;; Open the review buffer in the other window so the source file stays
  ;; visible side-by-side with the diff/comments.
  (code-review-new-buffer-window-strategy #'switch-to-buffer-other-window)
  ;; Reuse forge's auth-source entry (api.github.com login <user>^forge).
  (code-review-auth-login-marker 'forge)
  :config
  ;; ghub 5.0 moved `ghub-graphql' (and friends) out of `ghub' into
  ;; `ghub-legacy', which is not autoloaded.  code-review still calls the
  ;; legacy names, so without this require every PR fetch fails with
  ;; "deferred error: (wrong-type-argument listp void-function)".
  (require 'ghub-legacy)
  ;; Disable flyspell in the comment editor; it fights with code identifiers.
  (add-hook 'code-review-comment-mode-hook
            (lambda () (when (bound-and-true-p flyspell-mode)
                         (flyspell-mode -1)))))

(use-package git-commit
  :ensure nil
  :init
  (setq git-commit-major-mode 'markdown-mode)
  (add-hook 'git-commit-setup-hook
            (lambda ()
              (setq-local markdown-indent-on-enter 'indent-and-new-item)
              (auto-fill-mode 1)))
  )

;; Export EDITOR in terminal buffers so commands like `git commit' launched
;; inside the shell open their editor buffer in this Emacs (via emacsclient)
;; instead of spawning a nested editor.
(use-package with-editor
  :hook ((shell-mode . with-editor-export-editor)
         (eshell-mode . with-editor-export-editor)
         (vterm-mode . with-editor-export-editor)))

(use-package browse-at-remote :ensure t
  :bind (("C-c b" . 'echo-url-at-remote))
  :config
  (defun echo-url-at-remote ()
    (interactive)
    (message "URL: %s" (browse-at-remote-get-url)))
  )

(provide 'init-git)
;;; init-git.el ends here
