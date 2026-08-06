;;; init-prog.el --- Programming languages and development tools -*- lexical-binding: t -*-

;;; Commentary:
;; All programming language configurations and development tools.

;;; Code:

;;; Development tools

(use-package exec-path-from-shell :ensure t
  :config
  (add-to-list 'exec-path-from-shell-variables "CMAKE_PREFIX_PATH")
  (add-to-list 'exec-path-from-shell-variables "PYTHONPATH")
  (add-to-list 'exec-path-from-shell-variables "PYTHONHOME")
  (exec-path-from-shell-initialize)
  )

(use-package docker
  :ensure t)

(use-package dockerfile-mode :ensure t :defer t
  :init (add-to-list 'auto-mode-alist '("Dockerfile\\'" . dockerfile-mode)))

(use-package udev-mode :ensure t)

(use-package gist :ensure t
  :bind
  (("C-c C-g" . gist-region-or-buffer))
  )

(use-package google-this :ensure t)

(use-package graphviz-dot-mode :ensure t
  :config
  (defun graphviz-compile-preview ()
    "Compile and preview graphviz dot file."
    (interactive)
    (compile compile-command)
    (sleep-for 1)
    (graphviz-dot-preview))
  )

(use-package sqlite3
  :if (not (sqlite-available-p))
  :ensure t)

(use-package yasnippet :ensure t
  :config
  (setq yas-snippet-dirs '("~/.emacs.d/snippets"
                           "~/.emacs.d/yasnippet-snippets/snippets"))
  (setq yas-trigger-key "Enter")
  (yas-global-mode 1)
  ;;(custom-set-variables '(yas-trigger-key "TAB"))

  ;; insert new snippet
  (define-key yas-minor-mode-map (kbd "C-x i i") 'yas-insert-snippet)
  ;; create a new snippet
  (define-key yas-minor-mode-map (kbd "C-x i n") 'yas-new-snippet)
  ;; edit a snippet
  (define-key yas-minor-mode-map (kbd "C-x i v") 'yas-visit-snippet-file)
  :hook ((prog-mode . yas-minor-mode)
         (cmake-mode . yas-minor-mode))
  )

(use-package yasnippet-capf
  :ensure t
  :after cape
  :config
  (add-to-list 'completion-at-point-functions #'yasnippet-capf)
  (defun my-add-at-sign-to-syntax ()
    "Add @ to word syntax."
    (modify-syntax-entry ?@ "w"))
  (add-hook 'org-mode-hook #'my-add-at-sign-to-syntax)
  )

(use-package yatemplate :ensure t
  :config
  (setq auto-insert-alist '(()))
  (setq yatemplate-dir (expand-file-name "~/.emacs.d/templates"))
  (yatemplate-fill-alist)
  (auto-insert-mode 1)
  (defun after-save-hook--yatemplate ()
    (when (string-match "emacs.*/templates/" buffer-file-name)
      (yatemplate-fill-alist)))
  (add-hook 'after-save-hook 'after-save-hook--yatemplate)
  )

(use-package ansi-color
  :init
  (defun endless/colorize-compilation ()
    "Colorize from `compilation-filter-start' to `point'."
    (let ((inhibit-read-only t))
      (ansi-color-apply-on-region
       compilation-filter-start (point))))

  (add-hook 'compilation-filter-hook
            #'endless/colorize-compilation)
  )

;; apheleia runs an external formatter asynchronously on save. It applies the
;; result as a diff, so point and window scroll position never jump.
;; `:demand' is required because `:bind' alone would defer loading until the
;; first `C-c f', leaving `apheleia-global-mode' off until then.
;;
;; `apheleia-mode-alist' maps about 100 major modes to a formatter out of the
;; box. The entries this configuration is likely to hit, `-ts-mode' variants
;; included:
;;
;;   emacs-lisp, lisp                     lisp-indent (indent-region, built-in)
;;   c, c++, objc                         clang-format
;;   python                               ruff (set below; the default is black)
;;   go                                   gofmt
;;   rust                                 rustfmt
;;   bash                                 shfmt
;;   js, ts, tsx, json, yaml, css, html   prettier
;;   ruby                                 prettier
;;   lua                                  stylua
;;   cmake                                cmake-format
;;   terraform                            tofu fmt
;;   toml                                 taplo
;;   dockerfile                           dprint
;;   nix                                  nixfmt
;;   java                                 google-java-format
;;   php                                  phpcs
;;   latex                                latexindent
;;   sql                                  pg_format
;;
;; Only lisp-indent runs in-process. Every other entry shells out, and apheleia
;; skips the buffer silently when `executable-find' cannot locate the command.
;; An uninstalled formatter therefore costs nothing beyond leaving the buffer
;; unformatted. prettier is looked up in the project's node_modules before PATH,
;; so TypeScript and the other prettier-backed modes only get formatted inside a
;; project that carries prettier itself. Run `M-x describe-variable RET
;; apheleia-mode-alist' for the full table.
(use-package apheleia :ensure t
  :demand t
  :bind (("C-c f" . 'apheleia-format-buffer))
  :config
  ;; Format Python with ruff. The apheleia default is black, which is not
  ;; installed here, so Python buffers would otherwise stay unformatted.
  (setf (alist-get 'python-mode apheleia-mode-alist) 'ruff)
  (setf (alist-get 'python-ts-mode apheleia-mode-alist) 'ruff)
  (apheleia-global-mode +1)
  )

(use-package clang-format :ensure t
  ;; :bind (:map c-mode-base-map
  ;;             ("C-c f" . 'clang-format-buffer))
  )

(use-package emacs-clang-rename
  :ensure nil
  :if (file-exists-p "~/.emacs.d/plugins/emacs-clang-rename.el")
  :bind (:map c-mode-base-map
              ("C-c c p" . emacs-clang-rename-at-point)
              ("C-c c q" . emacs-clang-rename-qualified-name)
              ("C-c c a" . emacs-clang-rename-qualified-name-all))
  :config
  (if (executable-find "clang-rename-6.0")
      (setq emacs-clang-rename-binary "clang-rename-6.0"))
  )

(use-package py-yapf :ensure t :if nil
  :hook ((python-mode . (lambda () (define-key python-mode-map "\C-cf" 'py-yapf-buffer))))
  )

(use-package browse-url)

(use-package vterm
  :ensure t
  :after browse-url
  :bind (:map vterm-mode-map
              ("\C-c \C-c" . 'vterm--self-insert)
              ("\C-h" . 'vterm-send-backspace)
              ;; vterm-copy-mode is mapped to C-c C-t originally but C-t is used as tmux prefix
              ;; key.
              ("\C-c [" . 'vterm-copy-mode) ; like tmux
              ("\C-c t" . 'my-vterm-toggle)
              ("<mouse-1>" . 'my-browse-url-at-point)
              ("\C-k" . 'my-vterm-kill-line)
              )
  :custom
  (vterm-max-scrollback  10000)
  (vterm-buffer-name-string  "*vterm: %s*")
  ;; Remove C-h from the original vterm-keymap-exceptions
  (vterm-keymap-exceptions '("C-c" "C-x" "C-u" "C-g" "C-l" "M-x" "M-o" "C-v" "M-v" "C-y" "M-y"
                             "C-k"))
  (vterm-always-compile-module t)
  :config

  ;; https://github.com/akermu/emacs-libvterm/issues/304#issuecomment-621617817
  (defun my-vterm-kill-line ()
    "Send `C-k' to libvterm and copy the line to the kill-ring."
    (interactive)
    (kill-ring-save (point) (vterm-end-of-line))
    (vterm-send-key "k" nil nil t))

  (defun my-browse-url-at-point ()
    "Open URL only if the thing-at-point is URL.
`browse-url-at-point' uses (thing-at-point 'file). To open URLs only, we define a simple wrapper."
    (interactive)
    (let ((url (thing-at-point 'url)))
      (if url (browse-url url))))

  :hook (vterm-mode . (lambda ()
                        (display-line-numbers-mode -1)
                        (if (x-list-fonts "Monaco Nerd Font Mono")
                            (setq-local buffer-face-mode-face '(:family "Monaco Nerd Font Mono")))
                        (buffer-face-mode)
                        (display-fill-column-indicator-mode -1)
                        (setq-local show-trailing-whitespace nil)
                        ))
  )

(use-package multi-vterm :ensure t
  :after (vterm))

(use-package vterm-toggle :ensure t
  :after (vterm)
  :config
  ;; The toggle dispatch lives in lisp/my-vterm-toggle.el so that
  ;; tests/my-vterm-toggle-test.el can load it without pulling in the whole
  ;; init.
  (require 'my-vterm-toggle)
  :bind
  ("\C-c t" . 'my-vterm-toggle)
  ;; ("\C-c t" . 'vterm-toggle)
  ;; ("\C-c T" . 'vterm-toggle-cd)
  )

(use-package string-inflection :ensure t
  :config (global-set-key (kbd "C-c i") 'string-inflection-cycle))

(use-package tramp
  :custom
  ;; (tramp-copy-size-limit (* 1024 1024)) ;; 1MB
  (tramp-copy-size-limit (* 1024 10))
  (remote-file-name-inhibit-locks t)
  (tramp-use-scp-direct-remote-copying t)
  (remote-file-name-inhibit-auto-save-visited t)
  ;;Cache the file properties. If the target file is not updated frequently, nil is the best.
  (remote-file-name-inhibit-cache nil)
  ;; Suppress cache flash
  (process-file-side-effects nil)
  ;; Disable debug for performance.
  (tramp-debug-buffer nil)
  (tramp-verbose 0)
  :config
  ;; (add-hook 'find-file-hook
  ;;           (lambda ()
  ;;             (when (file-remote-p default-directory)
  ;;               (setq-local vc-handled-backends nil))))

  (connection-local-set-profile-variables
   'remote-direct-async-process
   '((tramp-direct-async-process . t)))

  (connection-local-set-profiles
   '(:application tramp :protocol "ssh")
   'remote-direct-async-process)

  ;; (setq magit-tramp-pipe-stty-settings 'pty)

  (setq tramp-default-method "ssh")
  (setq tramp-pipe-stty-settings "")
  (defun tramp-cleanup-all ()
    "Cleanup all tramp connection and buffers"
    (interactive)
    (tramp-cleanup-all-buffers)
    (call-interactively 'tramp-cleanup-all-connections))
  ;; By adding 'tramp-own-remote-path to tramp-remote-path, tramp can use the PATH value that
  ;; the remote shell sets by default. For example, tramp can use the PATH value set by ~/.zshenv.
  (add-to-list 'tramp-remote-path 'tramp-own-remote-path)
  )

(use-package treemacs :ensure t
  :after (all-the-icons)
  :config
  ;; (treemacs-start-on-boot)
  :hook
  ((treemacs-mode . (lambda ()
                      (display-line-numbers-mode -1)
                      (display-fill-column-indicator-mode -1)
                      ))
   )
  )

(use-package treemacs-magit
  :after (treemacs magit)
  :ensure t)

(use-package annotate
  :ensure t
  :hook (prog-mode . annotate-mode)
  )

;; projectile handles project root detection, project type detection,
;; per-type compile/test/run commands, and task discovery (npm scripts,
;; Makefile, justfile, etc.). These used to be reimplemented by hand in
;; lisp/rich-compile.el; that module is gone now that projectile covers it.
;;
;; The prefix is projectile's traditional "C-c p". "C-x p" is left alone -
;; this config deliberately unbinds project.el's "C-x p" and repurposes it
;; for other-window backwards (see the `project' block in init-lang.el).
;; `projectile-keymap-prefix' is read once when `projectile-mode-map' is
;; built, too early for :custom, so it's bound with :bind-keymap instead.
(use-package projectile
  :ensure t
  :demand t
  :custom
  ;; So a build and a test run, or two different projects' builds, don't
  ;; overwrite each other's *compilation* buffer.
  (projectile-compilation-buffer-scope t)
  :bind-keymap ("C-c p" . projectile-command-map)
  ;; C-c C-r has meant "what can I run here?" since the rich-compile days.
  ;; `projectile-run-task' is projectile's equivalent, listing npm scripts,
  ;; Makefile targets, justfile recipes, and the catkin commands registered
  ;; below.
  :bind (("C-c C-r" . projectile-run-task))
  :config
  (projectile-mode +1)

  ;; A catkin workspace is one git repository holding many ROS packages,
  ;; and "catkin build --this" means "the package default-directory is
  ;; in", so the project root has to be the package directory, not the
  ;; repository. `projectile-root-bottom-up' returns the closest ancestor
  ;; containing any marker, so adding package.xml makes a ROS package win
  ;; over the enclosing .git without affecting any other repository.
  ;; Escape hatch: drop an empty .projectile at the workspace root and
  ;; `projectile-root-marked', which runs first, treats the whole
  ;; workspace as one project again.
  (add-to-list 'projectile-project-root-files-bottom-up "package.xml")

  ;; projectile has no notion of ROS/catkin (no built-in type looks for
  ;; package.xml). A registered type is consed onto the front of
  ;; `projectile-project-types' and detection returns the first match, so
  ;; registering it here makes it win over the built-in CMake type.
  ;; :run is deliberately left unset - a ROS node is started by name, not
  ;; by package. :tasks is a projectile 3.1+ keyword, and
  ;; `projectile-register-project-type' is a cl-defun without
  ;; &allow-other-keys, so passing it to an older projectile would signal;
  ;; guard on the variable instead.
  (apply #'projectile-register-project-type
         'ros-catkin '("package.xml")
         (append
          (list :project-file "package.xml"
                :compile "catkin build --this"
                :test "catkin run_tests --this --no-deps"
                :test-prefix "test_"
                :src-dir "src/"
                :test-dir "test/")
          (when (boundp 'projectile-tasks)
            ;; The --no-deps build has no lifecycle phase of its own, so
            ;; list all three as tasks to make them reachable from C-c C-r.
            (list :tasks
                  '(("catkin:build"             . "catkin build --this")
                    ("catkin:build-no-deps"     . "catkin build --this --no-deps")
                    ("catkin:run-tests-no-deps" . "catkin run_tests --this --no-deps"))))))
  )

(use-package auth-source-1password
  :ensure t
  :custom (auth-source-1password-vault "Private")
  :config
  (defun my-auth-source-1password-construct-path (_backend _type host user _port)
    "Create a path by converting usernames containing '^' for Forge into a format usable by
1Password, and stripping API suffixes from the host."
    (let* ((vault auth-source-1password-vault)
           (clean-host (if (stringp host)
                           (replace-regexp-in-string "/api/v3\\'" "" host)
                         host))
           ;; Replace 'username^forge' with 'username-forge' or other characters allowed by 1Password.
           (safe-user (if (stringp user)
                          (replace-regexp-in-string "\\^" "-" user)
                        user)))
      (mapconcat #'identity (list vault clean-host safe-user) "/")))

  ;; Assign the custom function to the package configuration.
  (setq auth-source-1password-construct-secret-reference #'my-auth-source-1password-construct-path)
  (auth-source-1password-enable))

(provide 'init-prog)
;;; init-prog.el ends here
