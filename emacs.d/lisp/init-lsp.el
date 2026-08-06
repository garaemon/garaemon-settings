;;; init-lsp.el --- Language Server Protocol and syntax checking -*- lexical-binding: t -*-

;;; Commentary:
;; lsp-mode and its UI/backend companions, plus flycheck.

;;; Code:

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

(provide 'init-lsp)
;;; init-lsp.el ends here
