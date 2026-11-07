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
;; NonGNU ELPA is part of the Emacs default and carries dependencies that
;; neither GNU ELPA nor MELPA serves, such as treesit-fold, which tsx-mode
;; requires.  Dropping it here left tsx-mode unable to activate.
(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/")))
;; Load treesit before the activation pass below.  Emacs does not preload it,
;; so an autoload file that calls `treesit-ready-p' at top level aborts with
;; "Error loading autoloads: (void-function treesit-ready-p)".
(require 'treesit nil t)
(package-initialize)

;; Install use-package if not already installed
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;; Customize saves to custom.el instead of appending to the tracked init.el.
;; Load the file early so per-machine overrides (e.g. org-directory) win over
;; defaults set via use-package :custom in init-*.el.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file))

;; Load configuration files
(require 'init-basic)
(require 'init-ui)
(require 'init-editor)
;; init-prog comes before the modules split out of it: it configures
;; exec-path-from-shell, and everything below expects the shell PATH.
(require 'init-prog)
(require 'init-lang)
(require 'init-lsp)
(require 'init-git)
(require 'init-ai)
(require 'init-org)
(require 'init-utils)

;; Reset GC threshold to reasonable value after startup
(setq gc-cons-threshold (* 2 1024 1024)  ; 2MB
      gc-cons-percentage 0.1)

;; Start server
(unless (server-running-p)
  (server-start))

;;; init.el ends here
