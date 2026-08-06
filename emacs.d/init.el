;;; init.el --- Emacs configuration entry point -*- lexical-binding: t -*-

;;; Commentary:
;; This file loads all configuration from lisp/init-*.el files

;;; Code:

;; Add load paths
;; Use load-file-name to ensure correct path in batch mode
(let ((init-dir (file-name-directory (or load-file-name (buffer-file-name)))))
  (add-to-list 'load-path (expand-file-name "lisp" init-dir))
  (add-to-list 'load-path (expand-file-name "plugins" init-dir)))

;; Remove tramp file first to clean up old tramp connection
(let ((tramp-old-file (expand-file-name "~/.emacs.d/tramp")))
  (require 'tramp)
  (tramp-cleanup-all-buffers)
  (call-interactively 'tramp-cleanup-all-connections)
  (if (file-exists-p tramp-old-file)
      (progn
        (message "deleting %s" tramp-old-file)
        (delete-file tramp-old-file))))

;; Package system setup
(require 'package)
(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("melpa" . "https://melpa.org/packages/")))
(package-initialize)

;; Install use-package if not already installed
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;; Load custom file early so per-machine overrides (e.g. org-directory) win
;; over defaults set via use-package :custom in init-*.el.
(let ((custom-file (expand-file-name "custom.el" user-emacs-directory)))
  (when (file-exists-p custom-file)
    (load custom-file)))

;; Load configuration files
(require 'init-basic)
(require 'init-ui)
(require 'init-editor)
(require 'init-prog)
(require 'init-org)
(require 'init-utils)

;; Reset GC threshold to reasonable value after startup
(setq gc-cons-threshold (* 2 1024 1024)  ; 2MB
      gc-cons-percentage 0.1)

;; Start server
(unless (server-running-p)
  (server-start))

;;; init.el ends here
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(minuet-auto-suggestion-block-predicates '(minuet-evil-not-insert-state-p my-not-eolp) nil nil "Customized with use-package minuet")
 '(package-selected-packages
   '(all-the-icons anzu apheleia auth-source-1password auto-highlight-symbol backup-each-save
               base16-theme bm browse-at-remote buffer-move calfw cape clang-format cmake-mode
               coffee-mode corfu diff-hl docker dockerfile-mode elpy embark-consult expreg
               fill-column-indicator flycheck forge gist go-mode google-c-style google-this gptel
               graphviz-dot-mode imenus jinja2-mode jinx json-mode lsp-sourcekit lsp-ui lua-mode
               marginalia minuet modern-cpp-font-lock multi-vterm multiple-cursors nix-mode
               ob-mermaid orderless org-ai org-download org-excalidraw org-modern org-roam outshine
               php-mode projectile protobuf-mode puppet-mode py-yapf qml-mode recentf-ext rust-mode
               smartrep solarized-theme sqlite3 string-inflection swift-mode swiper switch-window
               systemd terraform-mode thingopt treemacs-magit treesit-auto tsx-mode typescript-mode
               udev-mode undo-tree vertico-posframe vterm-toggle vundo yaml-mode yasnippet-capf
               yatemplate))
 '(package-vc-selected-packages
   '((org-excalidraw :url "https://github.com/4honor/org-excalidraw.git"))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(org-document-title ((t (:family "Monaco" :height 1.0 :weight bold :inherit default))))
 '(org-level-1 ((t (:family "Monaco" :inherit default))))
 '(org-level-2 ((t (:family "Monaco" :inherit default))))
 '(org-level-3 ((t (:family "Monaco" :inherit default))))
 '(org-level-4 ((t (:family "Monaco" :inherit default))))
 '(org-level-5 ((t (:family "Monaco" :inherit default))))
 '(org-level-6 ((t (:family "Monaco" :inherit default))))
 '(org-level-7 ((t (:family "Monaco" :inherit default))))
 '(org-level-8 ((t (:family "Monaco" :inherit default)))))
