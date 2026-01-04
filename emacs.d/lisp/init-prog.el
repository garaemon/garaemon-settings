;;; init-prog.el --- Programming languages and development tools -*- lexical-binding: t -*-

;;; Commentary:
;; All programming language configurations and development tools.

;;; Code:

;;; Input method settings

;;; anthy setting
(when (and (or (eq system-type 'cygwin)
               (eq system-type 'gnu/linux))
           (<= emacs-major-version 26))
  (setq load-path (append '("/usr/share/emacs/site-lisp/anthy/") load-path))
  (when (require 'anthy nil t)
    (global-unset-key "\C-\\")
    (setq default-input-method "japanese-anthy")
    (global-set-key "\C-\\" 'anthy-mode)))

;;; Language-specific settings and modes

;;; Cuda
(setq auto-mode-alist (cons (cons "\\.cu?$" 'c-mode) auto-mode-alist))
(setq auto-mode-alist (cons (cons "\\.cg?$" 'c-mode) auto-mode-alist))

;; A utility function to share a region as an image via m2i.garaemon.com.
(defun markup-to-image-share-region (start end)
  "Render the selected region using the markup service."
  (interactive "r")
  (let ((url-base "https://m2i.garaemon.com") ;; Change this to your deployed URL
        (content (url-hexify-string (buffer-substring-no-properties start end)))
        (lang (cond ((derived-mode-p 'markdown-mode) "markdown")
                    ((derived-mode-p 'latex-mode) "latex")
                    (t "code")))
        (code-lang (replace-regexp-in-string "-mode$" "" (symbol-name major-mode))))
    (browse-url (format "%s/?l=%s&cl=%s&txt=%s" url-base lang code-lang content))))

;;; shell script
(setq sh-basic-offset 2)
(setq sh-indentation 2)
(setq sh-shell-file "/bin/bash")
(add-to-list 'auto-mode-alist '("\\.subr$" . shell-script-mode))

;;; C+++
(setq auto-mode-alist (cons (cons "\\.h?$" 'c++-mode) auto-mode-alist))
;; For yasnippet helper
(defun get-c++-include-guard-macro-name ()
  (interactive)                         ;for debug
  (let* ((full-current-file-name (buffer-file-name))
         (file-name (file-name-nondirectory full-current-file-name))
         (directory-name (get-c++-namespace)))
    (let ((macro-name (replace-regexp-in-string "\\\." "_" file-name)))
      (format "%s_%s" (upcase directory-name) (upcase macro-name)))))

(defun get-c++-namespace ()
  (interactive)                         ;for debug
  (let* ((full-current-file-name (buffer-file-name)))
    (file-name-nondirectory
     ;; Remove the tailing '/'
     (substring (file-name-directory full-current-file-name) 0 -1))))

;;; lisp
(font-lock-add-keywords
 'lisp-mode
 (list
  ;; *hoge*に色を付ける
  (list "\\(\\*\\w\+\\*\\)\\>" '(1 font-lock-constant-face nil t))
  ;; +hoge+に色を付ける
  (list "\\(\\+\\w\+\\+\\)\\>" '(1 font-lock-constant-face nil t))
  ;; <hoge>に色を付ける
  (list "\\(<\\w\+>\\)\\>" '(1 font-lock-constant-face nil t))
  ;; defclass*に色を付ける
  (list "\\(defclass\\*\\)" '(1 font-lock-keyword-face nil t))))

(defun cl-indent (sym indent)
  "Set indent level of SYM according to indent level of INDENT."
  (put sym 'common-lisp-indent-function
       (if (symbolp indent)
           (get indent 'common-lisp-indent-function) indent)))
(cl-indent 'iterate 'let)
(cl-indent 'collect 'progn)
(cl-indent 'mapping 'let)
(cl-indent 'mapping 'let)
(cl-indent 'define-test 'let)

(defun my-indent-sexp ()
  "Fix indent of current s expression."
  (interactive)
  (save-restriction (save-excursion (widen)
                                    (let* ((inhibit-point-motion-hooks t)
                                           (parse-status (syntax-ppss (point)))
                                           (beg (nth 1 parse-status))
                                           (end-marker (make-marker))
                                           (end (progn (goto-char beg)
                                                       (forward-list)
                                                       (point)))
                                           (ovl (make-overlay beg end)))
                                      (set-marker end-marker end)
                                      (overlay-put ovl 'face 'highlight)
                                      (goto-char beg)
                                      (while (< (point)
                                                (marker-position end-marker))
                                        ;; don't reindent blank lines so we don't set the "buffer
                                        ;; modified" property for nothing
                                        (beginning-of-line)
                                        (unless (looking-at "\\s-*$")
                                          (indent-according-to-mode))
                                        (forward-line))
                                      (run-with-timer 0.5 nil '(lambda(ovl)
                                                                 (delete-overlay ovl)) ovl)))))
(define-key lisp-mode-map "\C-cr" 'my-indent-sexp)

;;; emacslisp
(define-key emacs-lisp-mode-map "\C-cr" 'my-indent-sexp)

;;; elisp format
(require 'elisp-format nil t)

;;; haskell
(setq auto-mode-alist
      (append auto-mode-alist '(("\\.[hg]s$"  . haskell-mode)
                                ("\\.hi$"     . haskell-mode)
                                ("\\.l[hg]s$" . literate-haskell-mode))))
(autoload
  'haskell-mode "haskell-mode" "Major mode for editing Haskell scripts." t)
(autoload 'literate-haskell-mode "haskell-mode" "Major mode for editing literate Haskell scripts."
  t)
(add-hook 'haskell-mode-hook 'turn-on-haskell-decl-scan)
(add-hook 'haskell-mode-hook 'turn-on-haskell-doc-mode)
(add-hook 'haskell-mode-hook 'turn-on-haskell-indent)
(add-hook 'haskell-mode-hook 'turn-on-haskell-ghci)
(defvar haskell-literate-default)
(defvar haskell-doc-idle-delay)
(setq haskell-literate-default 'latex)
(setq haskell-doc-idle-delay 0)

(global-set-key "\C-c(" 'hs-hide-block)
(global-set-key "\C-c)" 'hs-show-block)
(global-set-key "\C-c{" 'hs-hide-all)
(global-set-key "\C-c}" 'hs-show-all)

;;; nxml
(defvar nxml-child-indent 2)
(setq mumamo-background-colors nil)

;;; objective-c
(add-to-list 'magic-mode-alist
             `(,(lambda ()
                  (and (string= (file-name-extension buffer-file-name) "h")
                       (re-search-forward "@\\<interface\\>"
                                          magic-mode-regexp-match-limit t))) . objc-mode))
(add-to-list 'auto-mode-alist '("\\.mm$" . objc-mode))
(add-to-list 'auto-mode-alist '("\\.m$" . objc-mode))

;;; Programming language packages

(use-package html
  :ensure nil
  :mode
  ("\\.html$" . html-mode)
  ("\\.ejs$" . html-mode)
  )

(use-package project
  :ensure nil
  :config
  (global-unset-key (kbd "C-x p"))
  ;; C-x p to switch buffer with inverse manner.
  ;; I have to define the keybind after removing the keybind of "C-x p" of project mode.
  (global-set-key "\C-xp" (lambda ()
                          (interactive)
                          (other-window -1)))

  )

(use-package ruby-mode
  :mode ("\\.thor$" . ruby-mode)
  :custom (ruby-indent-level 2)
  )

(use-package c++-mode
  :ensure nil
  ;; Use c++-mode for Arduino files
  :mode (("\\.ino\\'" . c++-mode))
  )

(use-package coffee-mode :ensure t :defer t)

(use-package python
  :custom (gud-pdb-command-name "python3 -m pdb")
  :config
  (defun run-python-and-switch-to-shell ()
    (interactive)
    (run-python)
    (python-shell-switch-to-shell))
  ;; TODO: It does not work
  (defun python-shell-send-region-or-statement ()
    (interactive)
    (if (use-region-p)
        (progn
          (call-interactively 'python-shell-send-region)
          (deactivate-mark))
      (let ((beg (save-excursion (beginning-of-line) (point)))
            (end (save-excursion (end-of-line) (point))))
        (python-shell-send-string
         (python-shell-buffer-substring beg end))
        )))
  :bind (:map python-mode-map
              ("\C-x\C-E" . 'python-shell-send-region-or-statement)
              ("\C-cE" . 'run-python-and-switch-to-shell)
              ("\C-ce" . 'run-python-and-switch-to-shell)
              ("\C-c <right>" . 'python-indent-shift-right)
              ("\C-c <left>" . 'python-indent-shift-left)
              ("\C-c\C-r" . 'rich-compile-run-menu)
         :map python-ts-mode-map
              ("\C-x\C-E" . 'python-shell-send-region-or-statement)
              ("\C-cE" . 'run-python-and-switch-to-shell)
              ("\C-ce" . 'run-python-and-switch-to-shell)
              ("\C-c <right>" . 'python-indent-shift-right)
              ("\C-c <left>" . 'python-indent-shift-left)
              ("\C-c\C-r" . 'rich-compile-run-menu)
              )
  :hook ((python-mode . (lambda () (setq-local comment-inline-offset 2))))
  )

(use-package elpy :ensure t :if nil
  :config
  (elpy-enable)
  ;; use ipython for interactive shell
  (setq python-shell-interpreter "ipython"
        python-shell-interpreter-args "-i --no-confirm-exit"
        python-shell-enable-font-lock nil)
  (defun elpy-shell-send-region-or-statement ()
    "Send region or statement to python shell."
    (interactive)
    (if (use-region-p)
        (progn
          (elpy-shell-send-region-or-buffer)
          (deactivate-mark))
      (elpy-shell-send-statement)
      ))
  (define-key python-mode-map "\C-x\C-E" 'elpy-shell-send-region-or-statement)
  (define-key python-mode-map "\C-cE" 'elpy-shell-switch-to-shell)
  (global-set-key "\C-cE" 'elpy-shell-switch-to-shell)
  (add-hook 'elpy-mode-hook (lambda () (highlight-indentation-mode -1)))
  )

(use-package go-mode :ensure t :defer t
  :config
  (defun my-go-mode-hook ()
    (make-local-variable 'whitespace-style)
    (setq whitespace-style (delete 'tabs whitespace-style))
    (setq whitespace-style (delete 'tab-mark whitespace-style))
    )

  :hook ((go-mode . my-go-mode-hook)
         (go-ts-mode . my-go-mode-hook))
  )

(use-package google-c-style :ensure t
  :config
  (setf (cdr (assoc 'c-basic-offset google-c-style)) 2)
  :hook ((c-mode-common . google-set-c-style)
         (c-mode-common . google-make-newline-indent))
  )

(use-package jinja2-mode :ensure t
  :bind (:map jinja2-mode-map
              ;; Do not allow jinja2-mode to take over M-o.
              ("M-o" . 'switch-window-or-split))
  )

(use-package json-mode :ensure t :defer t)

(use-package less-css-mode :ensure t :defer t)

(use-package lua-mode :ensure t :defer t)

(use-package markdown-mode :ensure t
  :config
  (setq auto-mode-alist (cons '("\\.md" . markdown-mode) auto-mode-alist))
  (defvar markdown-mode-map)
  (define-key markdown-mode-map (kbd "M-p") nil)
  (define-key markdown-mode-map (kbd "M-n") nil)
  (define-key markdown-mode-map (kbd "C-c m") 'newline)
  ;; do not work?
  (setq markdown-display-remote-images t)
  (setq markdown-max-image-size '(600 . 600))
  (setq markdown-enable-math t)
  ;; syntax highlight for code block
  (setq markdown-fontify-code-blocks-natively t)
  ;; Do not change font in code block
  (set-face-attribute 'markdown-code-face nil
                      :inherit 'default)
  (set-face-attribute 'markdown-inline-code-face nil
                      :inherit 'default
                      :foreground (face-attribute font-lock-type-face :foreground))
  ;; For emacs 24
  (add-hook 'markdown-mode-hook '(lambda ()
                                   (electric-indent-local-mode -1)))
  )

(add-to-list 'load-path "~/.emacs.d/markdown-dnd-images")
(use-package markdown-dnd-images
  :ensure nil
  :custom
  (dnd-save-directory "images")
  (dnd-view-inline t)
  (dnd-save-buffer-name nil)
  (dnd-capture-source t)
  )

(use-package modern-cpp-font-lock :ensure t
  :hook (c++-mode . modern-c++-font-lock-mode))

(use-package php-mode :ensure t)

(use-package protobuf-mode :ensure t
  :init (add-to-list 'auto-mode-alist '("\\.proto$" . protobuf-mode))
  :config
  (add-hook 'protobuf-mode-hook
            (lambda ()
              (c-add-style "my-style" '((c-basic-offset . 4)
                                        (indent-tabs-mode . nil))
                           t)))
  )

(use-package puppet-mode :ensure t :defer t
  :init (add-to-list 'auto-mode-alist '("\\.pp$" . puppet-mode)))

(use-package rust-mode :ensure t)

(use-package swift-mode :ensure t)

(use-package yaml-mode :ensure t
  :init (add-to-list 'auto-mode-alist '("\\.\\(yml\\|yaml\\|rosinstall\\|yml\\.package\\)$" . yaml-mode)))

(use-package cmake-mode
  :ensure t
  :mode (("\\.cmake.em\\'" . cmake-mode))
  :init
  (setq auto-mode-alist (cons '("CMakeLists.txt" . cmake-mode) auto-mode-alist))
  (setq auto-mode-alist (cons '("\\.cmake$" . cmake-mode) auto-mode-alist))
  )

(use-package cmuscheme
  :init
  (autoload 'scheme-mode "cmuscheme" "Major mode for Scheme." t)
  (autoload 'run-scheme "cmuscheme" "Run an inferior Scheme process." t)
  :config
  (setq process-coding-system-alist
        (cons '("gosh" utf-8 . utf-8) process-coding-system-alist))
  (setq
   scheme-program-name "gosh"
   gosh-program-name "/usr/bin/env gosh -i"
   scheme-program-name "gosh -i")

  (defun scheme-other-window ()
    "Run scheme on other window."
    (interactive)
    (switch-to-buffer-other-window (get-buffer-create "*scheme*"))
    (run-scheme scheme-program-name))
  (define-key global-map "\C-cS" 'scheme-other-window)
  (put 'if 'scheme-indent-function 2)
  (put 'dotimes 'scheme-indent-function 1)
  (put 'dolist 'scheme-indent-function 1)
  (put 'instance 'scheme-indent-function 1)
  (put 'set! 'scheme-indent-function 1)
  (put 'let-keywords* 'scheme-indent-function 2)
  (put 'defun 'scheme-indent-function 2)
  (put 'defclass 'scheme-indent-function 2)
  (put 'defmethod 'scheme-indent-function 2)
  (put 'define-method* 'scheme-indent-function 2)
  (put 'define-class* 'scheme-indent-function 2)
  (put 'define-function* 'scheme-indent-function 1)
  (put 'let-keywords 'scheme-indent-function 2)
  (put 'let-optionals* 'scheme-indent-function 2)
  (put 'let-optionals 'scheme-indent-function 2)
  (put 'let-values 'scheme-indent-function 2)
  (put 'receive 'scheme-indent-function 1)
  (put 'mutex-block 'scheme-indent-function 2)
  (put 'unless 'scheme-indent-function 1)
  (put 'when 'scheme-indent-function 1)
  (put 'while 'scheme-indent-function 1)
  (put 'defmethod 'scheme-indent-function 1)

  ;;font-lock
  (font-lock-add-keywords
   'scheme-mode
   (list
    (list (concat "(" (regexp-opt '("use") t) "\\>")
          '(1 font-lock-keyword-face nil t))
    (list "\\(self\\)\\>" '(1 font-lock-constant-face nil t))
    (list "\\(\\*\\w\+\\*\\)\\>" '(1 font-lock-constant-face nil t))
    (list "\\(#\\(\\+\\|\\-\\)\.\*\\)" '(1 font-lock-variable-name-face))
    (cons "\\(dotimes\\|unless\\|when\\|dolist\\|while\\)\\>" 1)
    (cons
     "\\(let-\\(keywords\\|optionals\\|values\\|keywords\\*\\|optionals\\*\\|values\\*\\)\\)\\>"
     1)
    (list "\\(warn\\)\\>" '(1 font-lock-warning-face))
    (list "\\(#t\\|#f\\)\\>" '(1 font-lock-constant-face))
    (cons "\\(defclass\\|defmethod\\)\\>" 1)
    (cons "\\(define-\\(function\\*\\|class\\*\\|method\\*\\)\\)\\>" 1)))
  )

(use-package qml-mode :ensure t
  :config
  (setq js-indent-level 2)
  )


;; Install tsx-mode from custom repository
;; The latest emacs30 branch depends on flymaks-jsts.
;; `(use-package flymake-jsts)' does not work well.
;; We revert the latest change.
;; To do so, I forked tsx-mode.el and removed the latest commit.
;; Use garaemon's fork because the original repository, orzechowskid's, cannot load correctly.
(when (fboundp 'package-vc-install)
  (unless (package-installed-p 'tsx-mode)
    (package-vc-install
     '(tsx-mode :url "https://github.com/garaemon/tsx-mode.el"
                :branch "emacs30"))))
(use-package tsx-mode
  :after (treesit)
  ;; :defer t
  :mode (("\\.tsx\\'" . tsx-ts-mode)
         ("\\.jsx\\'" . tsx-ts-mode))
  :custom
  (tsx-mode-enable-css-in-js t)
  )

(use-package typescript-mode :ensure t
  :custom (typescript-indent-level 2)
  )

(use-package terraform-mode
  :ensure t
  )

(use-package xml
  :ensure nil
  :mode
  ("\\.urdf$" . xml-mode)
  ("\\.xacro$" . xml-mode)
  ("\\.launch$" . xml-mode)
  ("\\.test$" . xml-mode)
  )

;;; Development tools

(use-package exec-path-from-shell :ensure t
  :config
  (add-to-list 'exec-path-from-shell-variables "CMAKE_PREFIX_PATH")
  (add-to-list 'exec-path-from-shell-variables "EMACS_GEMINI_KEY")
  (add-to-list 'exec-path-from-shell-variables "PYTHONPATH")
  (add-to-list 'exec-path-from-shell-variables "PYTHONHOME")
  (exec-path-from-shell-initialize)
  )

(use-package aidermacs
  :defer t
  :ensure t
  ;; :bind (("C-c a" . aidermacs-transient-menu))
  :config
  ;; Use gemini as default LLM
  (if (getenv "EMACS_GEMINI_KEY")
      (setenv "GEMINI_API_KEY" (getenv "EMACS_GEMINI_KEY")))

  (let* ((uv-tool-dir (string-trim (shell-command-to-string "uv tool dir")))
         (aider-exec (format "%s/aider-chat/bin/aider" uv-tool-dir)))
    (setq aidermacs-program aider-exec))
  :custom
  ; See the Configuration section below
  (aidermacs-use-architect-mode t)
  (aidermacs-default-model "gemini/gemini-2.5-flash")
  :hook (aidermacs-comint-mode . (lambda ()
                                   (display-line-numbers-mode -1)
                                   (display-fill-column-indicator-mode -1)
                                   ))
  )

(use-package docker
  :ensure t)

(use-package dockerfile-mode :ensure t :defer t
  :init (add-to-list 'auto-mode-alist '("Dockerfile\\'" . dockerfile-mode)))

(use-package udev-mode :ensure t)

(use-package lsp-mode :ensure t
  ;; npm install -g typescript-language-server typescript
  :hook ((typescript-mode . #'lsp)
         (typescript-ts-mode . #'lsp)
         (yaml-mode . #'lsp)
         (yaml-ts-mode . #'lsp)
         (python-mode . #'lsp)
         (python-ts-mode . #'lsp)
         (shell-script-mode . #'lsp)
         (shell-script-ts-mode . #'lsp)
         (c-mode . #'lsp)
         (c-ts-mode . #'lsp)
         (c++-mode . #'lsp)
         (c++-ts-mode . #'lsp)
         (go-mode . #'lsp)
         (go-ts-mode . #'lsp)
         (sh-mode . #'lsp)
         (sh-ts-mode . #'lsp)
         (swift-mode . #'lsp)
         (swift-ts-mode . #'lsp)
         (lsp-completion-mode . my-lsp-mode-setup-completion))
  :init
  (defun my-lsp-mode-setup-completion ()
    (setf (alist-get 'styles (alist-get 'lsp-capf completion-category-defaults))
          '(orderless)))
  :config
  (add-to-list 'lsp-disabled-clients '(python-mode . ruff))
  (add-to-list 'lsp-disabled-clients '(python-ts-mode . ruff))
  ;; Disable ruff in tramp environment too
  (add-to-list 'lsp-disabled-clients '(python-mode . ruff-tramp))
  (add-to-list 'lsp-disabled-clients '(python-ts-mode . ruff-tramp))
  (add-to-list 'lsp-disabled-clients 'semgrep-ls)
  (add-to-list 'lsp-disabled-clients 'semgrep-ls-tramp)
  ;; Disable yamlls and sh because these language servers written in node.js do not work well with
  ;; direct-async process.
  (add-to-list 'lsp-disabled-clients 'yamlls-tramp)
  (add-to-list 'lsp-disabled-clients 'sh-tramp)
  (defun my-lsp-format (s e)
    (interactive "r")
    (if (region-active-p)
        (lsp-format-region s e)
      (lsp-format-buffer)))
  (if (not (display-graphic-p))
      ;; header-line for LSP mode is hard to see in emacs -nw environment.
      ;; https://emacs.stackexchange.com/questions/77279/how-can-i-find-the-face-of-the-items-in-the-headeline-in-lsp-mode
      (custom-set-faces
       '(header-line ((t (:inverse-video nil :underline t)))))
    )

  ;; Breadcrumb of lsp-mode does not work well in my linux configuration. Use an ascii character
  ;; for the separator.
  (when (eq system-type 'gnu/linux)
    ;; Disable icons to remove tofus
    (setq lsp-headerline-breadcrumb-icons-enable nil)
    ;; Use an ASCII character as the separator
    (setq lsp-headerline-breadcrumb-separator " > ")
    )

  :custom
  ;; (lsp-log-io t)
  (lsp-pylsp-plugins-yapf-enabled t)
  (lsp-pylsp-plugins-black-enabled nil)
  (lsp-pylsp-plugins-autopep8-enabled nil)
  (lsp-completion-provider :none) ;; we use Corfu!
  (lsp-signature-auto-activate nil) ; Prevent from minibuffer suddenly being large.
  ;; (lsp-python-server-settings
  ;;    '((pylsp . ((plugins . ((yapf . ((enabled . t)))
  ;;                            (black . ((enabled . nil)))
  ;;                            (autopep8 . ((enabled . nil))))
  ;;                         )))))
  ;; debug
  ;; (lsp-log-io t)
  ;; (lsp-log-process-output t)
  ;; :init
  (lsp-pylsp-server-command '("uv" "tool" "run" "--from" "python-lsp-server" "pylsp" "--verbose"
                              "--log-file" "pylsp.log"))
  :bind (
         ("C-c f" . 'my-lsp-format)
         ("M-." . 'lsp-find-definition)
         )
  )

(use-package lsp-ui :ensure t)

(use-package lsp-sourcekit
  :ensure t
  :after lsp-mode
  :custom
  (lsp-sourcekit-executable
   "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp")
  )

(use-package flycheck :ensure t
  :requires (thingopt)
  :config
  (setq flycheck-check-syntax-automatically '(mode-enabled save))
  ;; flycheck runs emacs with `-Q` option to lint emacs lisp codes. It means that
  ;; load-path is not taken into account in linting.
  ;; By assiging `flycheck-emacs-lisp-load-path` to 'inherit, flycheck runs emacs with
  ;; `load-path` inherited from the current emacs.
  (setq flycheck-emacs-lisp-load-path 'inherit)
  (global-flycheck-mode t)
  (flycheck-add-next-checker 'python-flake8 'python-pylint)
  )

(use-package minuet
  :ensure t
  :bind
  (:map minuet-active-mode-map
   ("TAB" . #'minuet-accept-suggestion) ;; accept whole completion
   ("<M-return>" . #'minuet-accept-suggestion) ;; accept whole completion
   ("M-A" . #'minuet-accept-suggestion) ;; accept whole completion
   ;; Accept the first line of completion, or N lines with a numeric-prefix:
   ;; e.g. C-u 2 M-a will accepts 2 lines of completion.
   ("M-a" . #'minuet-accept-suggestion-line)
   ("M-e" . #'minuet-dismiss-suggestion))
  :hook (prog-mode . minuet-auto-suggestion-mode)
  :custom
  (minuet-provider 'openai-fim-compatible)
  (minuet-auto-suggestion-debounce-delay 1.0)
  (minuet-n-completions 1)
  (minuet-context-window 1024)
  (minuet-request-timeout 10)
  ;; Do not show the completion when the cursor is NOT at the end of lines.
  (minuet-auto-suggestion-block-functions '(minuet-evil-not-insert-state-p my-not-eolp))
  :config
  (plist-put minuet-openai-fim-compatible-options
             :end-point "http://localhost:11434/v1/completions")
  ;; an arbitrary non-null environment variable as placeholder.
  ;; For Windows users, TERM may not be present in environment variables.
  ;; Consider using APPDATA instead.
  (plist-put minuet-openai-fim-compatible-options :name "Ollama")
  (plist-put minuet-openai-fim-compatible-options :api-key "TERM")
  ;; TODO: Install qwen2.5-coder:3b automatically
  ;; (plist-put minuet-openai-fim-compatible-options :model "qwen2.5-coder:3b")
  (plist-put minuet-openai-fim-compatible-options :model "deepseek-coder-v2:lite")

  (defun my-not-eolp ()
    (not (eolp)))

  (minuet-set-optional-options minuet-openai-fim-compatible-options :max_tokens 56)
  )

(use-package gist :ensure t
  :bind
  (("C-c C-g" . gist-region-or-buffer))
  )

(use-package google-this :ensure t
  :config
  (global-set-key (kbd "C-x g") 'google-this-mode-submap)
  (global-set-key (kbd "C-c g") 'google-this)
  )

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

(use-package magit :ensure t
  ;; (magit-refresh-status-buffer nil)
  :bind (("\C-cl" . 'magit-status)
         ("\C-cL" . 'magit-status)
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
- Use imperative form
")
  :hook (magit-mode . gptel-magit-install))

(use-package forge
  :after magit
  :ensure t
  ;; How to setup forge:
  ;;   1. configure github.user by following command:
  ;;     git config --global github.user garaemon
  ;;   2. Create ~/.authinfo file and write an entry like:
  ;;      machine api.github.com login garaemon^forge password {token}
  ;;     The scope of token to be enabled are
  ;;       1. repo
  ;;       2. user
  ;;       3. read:org
  :custom
  (forge-owned-accounts '(("garaemon")))
  :config
  (defun my-forge-create-pullreq ()
    (interactive)
    (call-interactively 'forge-create-pullreq)
    ;; Insert the last commit to the current buffer.
    ;; After calling forge-create-pullreq, the current buffer should be a buffer to edit the title
    ;; and the description of the new pull request.
    (magit-git-insert "log" "-1" "--pretty=%B")
    )
  )

(use-package git-commit
  :ensure nil
  :init
  (setq git-commit-major-mode 'markdown-mode)
  (add-hook 'git-commit-setup-hook
            (lambda ()
              (setq-local markdown-indent-on-enter 'indent-and-new-item)
              (auto-fill-mode 1)))
  )

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

(use-package browse-at-remote :ensure t
  :bind (("C-c b" . 'echo-url-at-remote))
  :config
  (defun echo-url-at-remote ()
    (interactive)
    (message "URL: %s" (browse-at-remote-get-url)))
  )

(use-package vterm
  :ensure t
  :after browse-url
  :bind (:map vterm-mode-map
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
                        ))
  )

(use-package multi-vterm :ensure t
  :after (vterm)
  :config
  ;; Make a new vterm terminal from local computer
  (defun vterm-local ()
    (interactive)
    (let ((default-directory (getenv "HOME")))
      (multi-vterm)))
  :bind (("C-M-t" . 'my-new-local-multi-vterm))
  )

(use-package vterm-toggle :ensure t
  :after (vterm)
  :config
  ;; Overwrite vterm-toggle. If the vterm buffer is not focused, focus to the buffer.
  (defun my-vterm-toggle (&optional args)
    "Vterm toggle.
Optional argument ARGS ."
    (interactive "P")
    (cond
     ((not (derived-mode-p 'vterm-mode))
      (vterm-toggle-show))
     ((or (derived-mode-p 'vterm-mode)
          (and (vterm-toggle--get-window)
               vterm-toggle-hide-method))
      (if (equal (prefix-numeric-value args) 1)
          (vterm-toggle-hide)
        (vterm vterm-buffer-name)))
     ((equal (prefix-numeric-value args) 1)
      (vterm-toggle-show))
     ((equal (prefix-numeric-value args) 4)
      (let ((vterm-toggle-fullscreen-p
             (not vterm-toggle-fullscreen-p)))
        (vterm-toggle-show)))))
  :bind
  ("\C-c t" . 'my-vterm-toggle)
  ;; ("\C-c t" . 'vterm-toggle)
  ;; ("\C-c T" . 'vterm-toggle-cd)
  )

(use-package gptel :ensure t
  :after (exec-path-from-shell)
  ;; TODO: Should I use \?
  :bind (("C-¥" . my-gptel-toggle)
         :map gptel-mode-map
         ("C-c C-c" . gptel-send))
  :custom
  '(gptel-directives
   '((default
      . "You are a large language model living in Emacs and a helpful assistant.
You have to follow the following orders:
- Respond concisely.
- Respond in Japanese. User is a Japanese. Even if the user uses English to ask questions, you have to answer in Japanese.
- Use English in program examples.
- Answer conclusions first.")
     (programming
      . "You are a large language model and a careful programmer. Provide code and only code as output without any additional text, prompt or note.")
     (writing
      . "You are a large language model and a writing assistant. Respond concisely.")
     (chat
      . "You are a large language model and a conversation partner. Respond concisely.")))
  :config
  (if (not (display-graphic-p))
      ;; header-line for LSP mode is hard to see in emacs -nw environment.
      ;; https://emacs.stackexchange.com/questions/77279/how-can-i-find-the-face-of-the-items-in-the-headeline-in-lsp-mode
      (custom-set-faces
       '(header-line ((t (:inverse-video nil :underline t)))))
    )

  (let ((gemini-key (getenv "EMACS_GEMINI_KEY")))
    (if gemini-key
        (setq gptel-model 'gemini-flash-latest
              gptel-backend (gptel-make-gemini "Gemini"
                 :key gemini-key
                 :stream t))
      ))

  (gptel-make-ollama "Ollama (gemmma3:4b)"
    :host "localhost:11434"
    :stream t
    :models '(gemma3:4b))

  (defun my-gptel-get-buffer ()
    (car (cl-remove-if #'null
                       (mapcar #'(lambda (buf)
                                   (with-current-buffer buf
                                     (if (member 'gptel-mode local-minor-modes)
                                         buf)))
                               (buffer-list)))))

  (defun my-gptel-toggle ()
    (interactive)
    (let ((gptel-buffer (my-gptel-get-buffer)))
      (if gptel-buffer
          (switch-to-buffer gptel-buffer)
        (call-interactively 'gptel)
      )))
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

(use-package treesit
  :ensure nil
  :custom
  (treesit-font-lock-level 4)
  )

(use-package treesit-auto
  :ensure t
  :custom
  (treesit-auto-install 'prompt)
  :config
  (treesit-auto-add-to-auto-mode-alist 'all)
  ;; cmake ts sometimes does not work well.
  (delete 'cmake treesit-auto-langs)
  ;; Modify some version of the treesit recipes in treesit-auto-recipe-list.
  (let* ((new-recipe-list (list (make-treesit-auto-recipe
                                 :lang 'bash
                                 :ts-mode 'bash-ts-mode
                                 :remap 'bash-mode
                                 :url "https://github.com/tree-sitter/tree-sitter-bash"
                                 :revision "v0.23.3"
                                 :ext "\\.sh\\'")
                                (make-treesit-auto-recipe
                                 :lang 'c
                                 :ts-mode 'c-ts-mode
                                 :remap 'c-mode
                                 :url "https://github.com/tree-sitter/tree-sitter-c"
                                 :revision "v0.23.6"
                                 :ext "\\.c\\'")
                                (make-treesit-auto-recipe
                                 :lang 'css
                                 :ts-mode 'css-ts-mode
                                 :remap 'css-mode
                                 :url "https://github.com/tree-sitter/tree-sitter-css"
                                 :revision "v0.23.2"
                                 :ext "\\.css\\'")
                                (make-treesit-auto-recipe
                                 :lang 'go
                                 :ts-mode 'go-ts-mode
                                 :remap 'go-mode
                                 :url "https://github.com/tree-sitter/tree-sitter-go"
                                 :revision "v0.23.4"
                                 :ext "\\.css\\'")
                                (make-treesit-auto-recipe
                                 :lang 'python
                                 :ts-mode 'python-ts-mode
                                 :remap 'python-mode
                                 :url "https://github.com/tree-sitter/tree-sitter-python"
                                 :revision "v0.23.6"
                                 :ext "\\.py\\'")
                                ))
         (new-recipe-alist (mapcar #'(lambda (recipe)
                                       (cons (treesit-auto-recipe-lang recipe)
                                             recipe))
                                   new-recipe-list)))
    (setq treesit-auto-recipe-list
          (mapcar #'(lambda (recipe)
                      (let ((lang (treesit-auto-recipe-lang recipe)))
                        (if (assoc lang new-recipe-alist)
                            (cdr (assoc lang new-recipe-alist))
                          recipe)))
                  treesit-auto-recipe-list))
    )
  (global-treesit-auto-mode)

  ;; Install some mandatory languages
  (let ((auto-install-languages '(c cpp python tsx typescript yaml go css bash make json))
        ;; `treesit-install-language-grammar' requires `treesit-language-source-alist' to be set up.
        ;; `treesit-auto--build-treesit-source-alist' builds a list for `treesit-language-source-alist' from
        ;; `treesit-auto-recipe-list'.
        (treesit-language-source-alist (treesit-auto--build-treesit-source-alist)))
    (dolist (lang auto-install-languages)
      (when (not (treesit-ready-p lang))
        (message "treesit grammar for %s has not yet been installed. Install the grammar automatically" lang)
        (treesit-install-language-grammar lang)))
    )
  )

(use-package annotate
  :ensure t
  :hook (prog-mode . annotate-mode)
  )

(use-package rich-compile
  :ensure nil
  :bind (("C-c C-r" . rich-compile-run-menu))
  )

(provide 'init-prog)
;;; init-prog.el ends here
