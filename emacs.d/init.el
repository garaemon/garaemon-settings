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

;; Load custom file if it exists
(let ((custom-file (expand-file-name "custom.el" user-emacs-directory)))
  (when (file-exists-p custom-file)
    (load custom-file)))

;;; init.el ends here
