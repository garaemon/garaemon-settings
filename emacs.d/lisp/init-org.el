;;; init-org.el --- Org mode configuration -*- lexical-binding: t -*-

;;; Commentary:
;; All Org mode related configuration.

;;; Code:

(use-package org
  :ensure nil
  ;; If we build org through package.el and `:ensure t`, org-mode can be slower than the
  ;; the built-in version.
  ;; To prevent package.el from installing and building from the source code, specify it as
  ;; built-in.
  :requires (cl-lib)
  :init
  (setq org-jouornelly-file
   (expand-file-name
    "~/Library/Mobile Documents/iCloud~com~xenodium~Journelly/Documents/Journelly.org"))
  :custom
  (org-startup-indented t)
  (org-hide-emphasis-markers t)
  (org-startup-with-latex-preview nil)
  (org-link-file-path-type 'relative)
  (org-directory (expand-file-name "~/ghq/github.com/garaemon/org/"))
  ;; The special characters for org-capture-templates are described below:
  ;; https://orgmode.org/manual/Template-expansion.html#Template-expansion
  (org-capture-templates
   '(("t" "Todo" entry (file+headline (lambda () (concat org-directory "Tasks.org"))
                                      "Tasks")
      "* TODO %?\n  CAPTURED_AT: %a\n  %i\n"
      )
     ("m" "Memo" entry (file+headline
                        (lambda () (concat org-directory "INBOX.org"))
                        "Memos")
      "*** MEMO [%T] %? \n    CAPTURED_AT: %a\n    %i"
      :unarrowed t
      :prepend t)
     ("j" "Journelly" entry (file org-jouornelly-file)
      "* %T @ %(system-name) by %(user-login-name)\n%?"
      :prepend t
      :jump-to-captured nil
      )
     ))
  (org-todo-keywords '((sequence "TODO" "INPROGRESS" "|" "DONE" "DELEGATED")))
  ;; Use C-c C-q to insert tag.
  ;; To update the tag list from the agenda files, I set
  ;; `org-complete-tags-always-offer-all-agenda-tags' t.
  (org-complete-tags-always-offer-all-agenda-tags t)
  :config
  (add-to-list 'org-agenda-files org-directory)
  (add-to-list 'org-agenda-files org-jouornelly-file)
  ;; Write content to org-capture from MINI Buffer
  ;; http://ganmacs.hatenablog.com/entry/2016/04/01/164245
  (defun org/note-right-now (content)
    (interactive "sContent for org-capture quick memo: ")
    (org-capture nil "m")
    (insert content)
    (org-capture-finalize))

  (defun my-org-mode-wrap-inline-code (start end)
    "Wrap the region between START and END with backticks."
    (interactive "r")
    (let ((text (buffer-substring-no-properties start end)))
      (delete-region start end)
      ;; TODO: do not insert whitespaces around = if no need
      (insert " =" text "= ")))

  (defun my-org-schedule-if-todo ()
    "When an item becomes a TODO state, schedule it for today if not already scheduled."
    (when (equal org-state "TODO")
      (org-schedule nil (with-temp-buffer (org-time-stamp '(16)) (buffer-string)))))

  (add-hook 'org-todo-state-hook #'my-org-schedule-if-todo)
  (add-hook 'org-after-todo-state-change-hook #'my-org-schedule-if-todo)
  ;; org-babel
  (org-babel-do-load-languages 'org-babel-load-languages
                               '((plantuml . t)
                                 (sql . t)
                                 (gnuplot . t)
                                 (emacs-lisp . t)
                                 (python . t)
                                 (shell . t)
                                 (js . t)
                                 (org . t)
                                 (ruby . t)))
  ;; The default font color is too dark. Use brighter color.
  (plist-put org-format-latex-options :foreground "whitesmoke")
  ;; The default font is too small. Increase the size.
  (plist-put org-format-latex-options :scale 2.0)
;; Customize `textwidth` in LaTeX headers from -3cm to -6cm.
;; This adjustment moves equation numbers further left, compensating for increased font size
;; and ensuring proper alignment, as `org-format-latex-header` updates.
  (setq org-format-latex-header
        "\\documentclass{article}
\\usepackage[usenames]{color}
[DEFAULT-PACKAGES]
[PACKAGES]
\\pagestyle{empty}             % do not remove
% The settings below are copied from fullpage.sty
\\setlength{\\textwidth}{\\paperwidth}
\\addtolength{\\textwidth}{-6cm}
\\setlength{\\oddsidemargin}{1.5cm}
\\addtolength{\\oddsidemargin}{-2.54cm}
\\setlength{\\evensidemargin}{\\oddsidemargin}
\\setlength{\\textheight}{\\paperheight}
\\addtolength{\\textheight}{-\\headheight}
\\addtolength{\\textheight}{-\\headsep}
\\addtolength{\\textheight}{-\\footskip}
\\addtolength{\\textheight}{-3cm}
\\setlength{\\topmargin}{1.5cm}
\\addtolength{\\topmargin}{-2.54cm}")

  (defun my-create-org-blog-file (title)
    "Create a new org file with the current date and a user-provided title.
The filename will be in the format 'YYYY-MM-DD-your-title.org'.
Spaces in the title are replaced with hyphens.
If the file is new, it will be populated with a default template."
    ;; Using (interactive "s...") receives string input from the user
    ;; and binds it to the function's argument `title`.
    (interactive "sEnter file title: ")
    (let* ((org-blog-directory (concat org-directory "blog/"))
           ;; Get the current date as a string in "YYYY-MM-DD" format.
           (date-str (format-time-string "%Y-%m-%d"))
           ;; Replace all spaces in the user-provided title with hyphens.
           (processed-title (replace-regexp-in-string " " "-" title))
           ;; Construct the filename in the format "date-title.org".
           (filename (concat org-blog-directory date-str "-" processed-title ".org")))

      ;; find-file opens the file if it exists, or creates a new one if it doesn't.
      (find-file filename)

      ;; Check if the buffer size is zero.
      ;; If it's zero, it means the file was newly created.
      (when (zerop (buffer-size))
        ;; For a new file, insert the specified template.
        ;; Insert the original user-provided title into #+TITLE:.
        (insert (format "#+TITLE: %s\n" title))
        (insert "#+FILETAGS:\n"))))

  ;; Set up for auto commit and pull
  (defvar my-org-git-pull-done-sessions nil
    "An alist of (repo-root . date) pairs tracking when git pull was last executed.
Date format is YYYY-MM-DD.")

  (defun my-org-get-git-root ()
    "Returns the root directory of the Git repository for the current buffer's file.
     Returns nil if not found or if it's not a file buffer."
    (when (buffer-file-name)
      ;; Prefer vc-git-root (available in Emacs 29+)
      (if (fboundp 'vc-git-root)
          (vc-git-root (buffer-file-name))
        ;; Use locate-dominating-file as a fallback
        (locate-dominating-file (buffer-file-name) ".git"))))

  (defun my-org-git-pull-interactive (repo-root)
    "Asks the user whether to run git pull in the specified repository."
    ;; Confirm with user (yes-or-no-p)
    (when (yes-or-no-p (format "Run git pull in Org repository (%s)? " repo-root))
      (message "Org-Git-Sync: Executing git pull in %s..." repo-root)
      (let ((default-directory repo-root))
        (condition-case e
            (shell-command "git pull")
          (error (message "Org-Git-Sync: git pull failed: %s" e)))
        (message "Org-Git-Sync: git pull complete."))

      ;; Record today's date for this repository
      (let ((today (format-time-string "%Y-%m-%d"))
            (existing (assoc repo-root my-org-git-pull-done-sessions)))
        (if existing
            (setcdr existing today)
          (add-to-list 'my-org-git-pull-done-sessions (cons repo-root today))))))

  (defun my-org-check-for-initial-pull ()
    "Attempts git pull when opening a Git-managed Org file if not done today."
    ;; Is this an org-mode buffer?
    (message "calling my-org-check-for-initial-pull")
    (when (and (eq major-mode 'org-mode)
               buffer-file-name
               (boundp 'org-directory)
               org-directory
               (string-prefix-p (expand-file-name org-directory)
                                (expand-file-name buffer-file-name)))
      ;; Get the Git repository root
      (let ((git-root (my-org-get-git-root)))
        (when git-root
          ;; Check if pull has already been run for this repo today
          (let ((last-pull-date (cdr (assoc git-root my-org-git-pull-done-sessions)))
                (today (format-time-string "%Y-%m-%d")))
            (unless (string= last-pull-date today)
              (my-org-git-pull-interactive git-root)))))))

  (add-hook 'find-file-hook 'my-org-check-for-initial-pull nil nil)

  ;; Auto commit and push for org files
  (defvar my-org-auto-commit-timer nil
    "Timer for auto commit and push of org files.")

  (defvar my-org-auto-commit-idle-delay 300
    "Idle time in seconds before auto committing org changes.")

  (defun my-org-git-commit-and-push ()
    "Commit and push changes in the org directory."
    (when (and (boundp 'org-directory) org-directory)
      (let ((default-directory (expand-file-name org-directory)))
        (when (file-exists-p (concat default-directory ".git"))
          (message "Org-Git-Sync: Auto-committing changes...")
          ;; Check if there are any changes
          (let ((status-output (shell-command-to-string "git status --porcelain")))
            (if (string-empty-p (string-trim status-output))
                (message "Org-Git-Sync: No changes to commit.")
              ;; Add all org files
              (let ((add-result (shell-command "git add . 2>&1")))
                (unless (eq add-result 0)
                  (message "Org-Git-Sync: git add failed"))
                ;; Commit with timestamp
                (let* ((commit-msg (format-time-string "Auto-commit org changes at %Y-%m-%d %H:%M:%S"))
                       (commit-result (shell-command (format "git commit -m \"%s\" 2>&1" commit-msg))))
                  (if (eq commit-result 0)
                      (progn
                        ;; Push
                        (let ((push-result (shell-command "git push 2>&1")))
                          (if (eq push-result 0)
                              (message "Org-Git-Sync: Auto-commit and push complete.")
                            (message "Org-Git-Sync: git push failed"))))
                    (message "Org-Git-Sync: git commit failed"))))))))))

  (defun my-org-schedule-auto-commit ()
    "Schedule an auto-commit after idle delay."
    (when (and (eq major-mode 'org-mode)
               buffer-file-name
               (boundp 'org-directory)
               org-directory
               (string-prefix-p (expand-file-name org-directory)
                                (expand-file-name buffer-file-name)))
      ;; Cancel existing timer if any
      (when my-org-auto-commit-timer
        (cancel-timer my-org-auto-commit-timer))
      ;; Schedule new timer
      (setq my-org-auto-commit-timer
            (run-with-idle-timer my-org-auto-commit-idle-delay
                                 nil
                                 'my-org-git-commit-and-push))))

  (add-hook 'after-save-hook 'my-org-schedule-auto-commit)

  :bind (("C-c c" . 'org-capture)
         ("C-M-c" . 'org/note-right-now)
         ("C-c /" . 'consult-org-agenda)
         ("C-c s" . 'org-store-link)
         :map org-mode-map
         ("M-e" . 'my-org-mode-wrap-inline-code)
         ("C-c /" . 'consult-org-agenda)
         ("C-c s" . 'org-store-link))
  :hook ((org-mode . (lambda ()
                       ;; To wrap texts
                       (visual-line-mode)
                       ;; Show images inline automatically
                       (setq org-startup-with-inline-images t)
                       ;; Enable only under org-directory
                       (when (and buffer-file-name
                                  (string-prefix-p org-directory
                                                   (file-name-directory buffer-file-name)))
                       )))
         (org-agenda-mode . (lambda ()
                              (display-line-numbers-mode -1)
                              (display-fill-column-indicator-mode -1)))
         )
  )

(use-package org-agenda
  :ensure nil
  ;; org includes org-agenda
  :after (org)
  :config

  (defmacro define-org-quick-command (new-func org-func)
    `(defun ,new-func ()
      ,(format "Call %s with large GC threshold and some modes disabled. It speeds up %s." org-func org-func)
      (interactive)
      (let ((started-at (float-time))
            (gc-cons-threshold (* 500 1024 1024))
            (org-modules nil)
            (magit-refresh-status-buffer nil)
            (magit-auto-revert-mode nil)
            (vc-handled-backends nil)
            (treesit-auto-langs nil))
        (global-auto-revert-mode nil)
        (global-jinx-mode nil)
        (global-treesit-auto-mode nil)
        (unwind-protect
            (call-interactively ',org-func))
        (global-auto-revert-mode)
        (global-jinx-mode)
        (global-treesit-auto-mode)
        (let* ((ended-at (float-time))
               (delta-duration (- ended-at started-at)))
          (message "%s took %s sec" (symbol-name ',org-func) delta-duration)
          )))
    )

  (define-org-quick-command org-agenda-quick org-agenda)
  (define-org-quick-command org-set-tags-command-quick org-set-tags-command)

  :bind (("C-c a" . 'org-agenda-quick)
         ("C-c C-q" . 'org-set-tags-command-quick)
         :map org-mode-map
         ("C-c C-q" . 'org-set-tags-command-quick)
         )
  )

(use-package org-ai :ensure t :after org
  ;; C-c C-c (=org-ai-complete-block) to get AI response.
  :bind
  ;; In org capture mode, C-c C-c is used to finish a capture.
  ;; We need a different keymap.
  ("C-c x" . 'org-execute-block-src-or-ai)
  :custom
  ;; Use Geimini
  (org-ai-service 'google)
  (org-ai-default-chat-model "gemini-2.5-flash")
  (org-ai-auto-fill nil)
  ;; ~/.authinfo should have
  ;; machine generativelanguage.googleapis.com login org-ai password <API-KEY>.
  :config
  ;; Fix the indent of ai response in ai block.
  ;; https://github.com/rksm/org-ai/issues/18#issuecomment-1737931580
  (defun dss/-org-ai-after-chat-insertion-hook (type _text)
    (when (and (eq type 'end) (eq major-mode 'org-mode)
               (memq 'org-indent-mode minor-mode-list))
      (org-indent-indent-buffer)))
  (add-hook 'org-ai-after-chat-insertion-hook #'dss/-org-ai-after-chat-insertion-hook)
  (defun org-execute-block-src-or-ai ()
    (interactive)
    (if (eq (car (org-element-context)) 'src-block)
        (org-babel-execute-src-block)
      (org-ai-complete-block)))
  )

(use-package org-tempo :after org
  :ensure nil
  :custom
  (org-structure-template-alist
   '(("A" . "ai")
     ("a" . "ai")
     ("ai" . "ai")
     ;;("a" . "export ascii")
     ("c" . "center")
     ("C" . "comment")
     ("cpp" . "src c++")
     ("py" . "src python")
     ("el" . "src elisp")
     ("e" . "example")
     ("E" . "export")
     ("h" . "export html")
     ("l" . "export latex")
     ("q" . "quote")
     ("s" . "src")
     ("sh" . "src shell")
     ("v" . "verse")
     ))
  ;; The keys of org-tempo-keywords-alist and org-structure-template-alist have to be unique.
  ;; To simplify it, clean up org-tempo-keywords-alist.
  (org-tempo-keywords-alist nil)
  )

(use-package org-download :ensure t :after org
  :custom (org-download-image-dir (concat org-directory "/images"))
  )

(use-package ob-mermaid :ensure t
  :requires (org)
  ;; npm install -g @mermaid-js/mermaid-cli
  :init
  (if (not (executable-find "mmdc"))
      (call-process-shell-command "npm install -g @mermaid-js/mermaid-cli"))
  :config
  (add-to-list 'org-babel-load-languages '(mermaid . t))
  (org-babel-do-load-languages 'org-babel-load-languages org-babel-load-languages)
  :custom
  (ob-mermaid-cli-path (executable-find "mmdc"))
  )

(use-package org-roam
  :ensure t
  :custom
  (org-roam-db-update-method 'immediate)
  (org-roam-db-location "~/.emacs.d/org-roam.db")
  (org-roam-directory (concat org-directory "org-roam/"))
  (org-roam-index-file (concat org-roam-directory "Index.org"))
  (org-roam-capture-templates
   '(("d" "default" plain "%?"
     :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                        "#+title: ${title}\n#+date: %T\n#+filetags: \n")
     :unnarrowed t
     :jump-to-captured t)))
  :config
  (if (not (file-exists-p org-roam-directory))
      (make-directory org-roam-directory t))
  (org-roam-db-autosync-mode)
  (add-to-list 'org-agenda-files org-roam-directory)
  ;; Why do we need this? Without this require, (use-package org-roam-dailies) does not load the
  ;; configuration.
  (require 'org-roam-dailies)
  :bind
  (("C-c n f" . 'org-roam-node-find)
   ("C-c n i" . 'org-roam-node-insert))
  )

(use-package org-roam-dailies
  :ensure nil
  :after org-roam
  :custom
  (org-roam-dailies-capture-templates
   ;; Insert timestamp automatically for org-agenda
   '(("d" "default" entry
      "* %T %?\n "
      :target (file+head "%<%Y-%m-%d>.org" "#+title: %<%Y-%m-%d>\n")
      :jump-to-captured t)))
  :config
  (add-to-list 'org-agenda-files (concat org-roam-directory "daily/"))
  :bind-keymap ("C-c n d" . org-roam-dailies-map)
  )

(use-package org-modern :ensure t
  :custom
  (org-modern-block-indent t)
  (org-modern-fold-stars
   '(("▶" . "▼")
     ("▷" . "▽")
     ("▸" . "▾")
     ("▹" . "▿")))
  (org-modern-checkbox
   '((?X . "✅")
     (?- . "🏃‍➡️")
     (?\s . "⬜")))
  ;; TODO: update the face configuration to make stars visible
  (org-modern-hide-stars nil)
  :config (global-org-modern-mode)
  )

(use-package outshine :ensure t
  :hook (outline-minor-mode . outshine-hook-function))

(use-package calfw :ensure t :defer t)

(provide 'init-org)
;;; init-org.el ends here
