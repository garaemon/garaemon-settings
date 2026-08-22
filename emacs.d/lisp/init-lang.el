;;; init-lang.el --- Programming language modes and syntax settings -*- lexical-binding: t -*-

;;; Commentary:
;; Per-language major modes, auto-mode-alist entries, indentation rules and
;; tree-sitter grammar setup.

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
              ("\C-c\C-r" . 'projectile-run-task)
              :map python-ts-mode-map
              ("\C-x\C-E" . 'python-shell-send-region-or-statement)
              ("\C-cE" . 'run-python-and-switch-to-shell)
              ("\C-ce" . 'run-python-and-switch-to-shell)
              ("\C-c <right>" . 'python-indent-shift-right)
              ("\C-c <left>" . 'python-indent-shift-left)
              ("\C-c\C-r" . 'projectile-run-task)
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

(use-package astro-ts-mode
  :after treesit-auto
  :ensure nil
  :vc (:url "https://git.isincredibly.gay/srxl/astro-ts-mode.git" :rev :newest))

(use-package treesit
  :ensure nil
  :custom
  (treesit-font-lock-level 4)
  )

;; Install tree-sitter grammars BEFORE `use-package treesit-auto' is processed.
;;
;; This must happen up here, not inside `:config' of treesit-auto, because of
;; the following chain that fires when treesit-auto is loaded:
;;
;;   (require 'treesit-auto)
;;     -> (provide 'treesit-auto) at end of file
;;        -> `eval-after-load' triggers for `:after treesit-auto' packages
;;           -> `astro-ts-mode' loads
;;              -> top-level defvar `astro-ts-mode--font-lock-settings'
;;                 evaluates `(typescript-ts-mode--font-lock-settings 'tsx)'
;;                 which compiles tree-sitter queries against the tsx grammar
;;                 -> `treesit-load-language-error' if tsx grammar is missing
;;
;; That error propagates up through use-package's `:catch' handler, which
;; swallows it silently and skips the rest of `:config' -- meaning any
;; grammar-installation loop placed inside `:config' never gets a chance to
;; run. By installing the grammars up here (before treesit-auto is required),
;; astro-ts-mode's top-level forms succeed and the rest of treesit-auto's
;; setup runs normally.
;;
;; The recipe URLs/revisions duplicate the ones used inside `treesit-auto'
;; below because we cannot reach `treesit-auto--build-treesit-source-alist'
;; without loading treesit-auto, which is exactly what we are trying to avoid.
(require 'treesit)
;; `warning-suppress-log-types' silences any residual `treesit' warnings
;; emitted during this install loop. The `(treesit-ready-p lang t)' calls
;; below pass QUIET=t and therefore do not warn, but
;; `treesit-install-language-grammar' itself still calls `display-warning'
;; if a freshly built grammar fails to load afterward (for example, an ABI
;; mismatch). That secondary warning is not actionable at this layer -- the
;; `condition-case' below already reports failures via `message' -- so it is
;; suppressed for the duration of the loop. The variable is rebound locally
;; via `let' so global warning behavior is unaffected.
(let ((treesit-language-source-alist
       '((bash       "https://github.com/tree-sitter/tree-sitter-bash" "v0.23.3")
         (c          "https://github.com/tree-sitter/tree-sitter-c" "v0.23.6")
         (cpp        "https://github.com/tree-sitter/tree-sitter-cpp" "v0.22.0")
         (css        "https://github.com/tree-sitter/tree-sitter-css" "v0.23.2")
         (go         "https://github.com/tree-sitter/tree-sitter-go" "v0.23.4")
         (python     "https://github.com/tree-sitter/tree-sitter-python" "v0.23.6")
         (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
         (tsx        "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
         (yaml       "https://github.com/tree-sitter-grammars/tree-sitter-yaml" "v0.7.2")
         (make       "https://github.com/tree-sitter-grammars/tree-sitter-make" "v1.1.1")
         (json       "https://github.com/tree-sitter/tree-sitter-json" "master")
         (astro      "https://github.com/virchau13/tree-sitter-astro" "master" "src")))
      (warning-suppress-log-types '((treesit))))
  (dolist (lang '(typescript tsx c cpp python yaml go css bash make json astro))
    ;; The second arg `t' (QUIET) is critical: `treesit-ready-p' with the
    ;; default nil emits a `display-warning' call for every unavailable
    ;; grammar, which is exactly what we are trying to avoid on a fresh
    ;; startup where none of these grammars exist yet.
    (unless (treesit-ready-p lang t)
      (message "Installing tree-sitter grammar for %s..." lang)
      (condition-case err
          (treesit-install-language-grammar lang)
        (error (message "Failed to install tree-sitter grammar for %s: %S" lang err))))))

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
                                (make-treesit-auto-recipe
                                 :lang 'javascript
                                 :ts-mode 'js-ts-mode
                                 :remap 'js-mode
                                 :url "https://github.com/tree-sitter/tree-sitter-javascript"
                                 :revision "v0.23.1"
                                 :source-dir "src"
                                 :ext "\\.js\\'")
                                (make-treesit-auto-recipe
                                 :lang 'astro
                                 :ts-mode 'astro-ts-mode
                                 :url "https://github.com/virchau13/tree-sitter-astro"
                                 :revision "master"
                                 :source-dir "src")
                                ;; Pin to v1.1.1: master tracks tree-sitter-cli 0.24+ which
                                ;; emits ABI 15, but Emacs 30 only loads up to ABI 14, so a
                                ;; master build triggers a "version-mismatch" warning.
                                (make-treesit-auto-recipe
                                 :lang 'make
                                 :ts-mode 'makefile-ts-mode
                                 :remap 'makefile-mode
                                 :url "https://github.com/tree-sitter-grammars/tree-sitter-make"
                                 :revision "v1.1.1"
                                 :ext "\\([Mm]akefile\\|.*\\.\\(mk\\|make\\)\\)\\'")
                                ))
         (new-recipe-alist (mapcar #'(lambda (recipe)
                                       (cons (treesit-auto-recipe-lang recipe)
                                             recipe))
                                   new-recipe-list)))
    (let* ((existing-langs (mapcar #'treesit-auto-recipe-lang treesit-auto-recipe-list))
           (replaced-list (mapcar #'(lambda (recipe)
                                      (let ((lang (treesit-auto-recipe-lang recipe)))
                                        (if (assoc lang new-recipe-alist)
                                            (cdr (assoc lang new-recipe-alist))
                                          recipe)))
                                  treesit-auto-recipe-list))
           (additional-recipes (seq-filter #'(lambda (recipe)
                                               (not (member (treesit-auto-recipe-lang recipe)
                                                            existing-langs)))
                                           new-recipe-list))
           (additional-langs (mapcar #'treesit-auto-recipe-lang additional-recipes)))
      (setq treesit-auto-recipe-list (append replaced-list additional-recipes))
      ;; `treesit-auto-langs' is a snapshot of recipe langs at package load time;
      ;; newly appended recipes must be registered here too so they are picked up
      ;; by `treesit-auto--build-treesit-source-alist'.
      (dolist (lang additional-langs)
        (add-to-list 'treesit-auto-langs lang)))
    )

  (global-treesit-auto-mode))

(use-package nix-mode
  :ensure t
  :mode "\\.nix\\'")

(use-package powershell :ensure t)

(provide 'init-lang)
;;; init-lang.el ends here
