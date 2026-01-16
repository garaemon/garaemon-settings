;;; init-basic.el --- Basic Emacs settings -*- lexical-binding: t -*-

;;; Commentary:
;; Fundamental Emacs behavior and basic keybindings.

;;; Code:

(require 'init-utils)
(eval-when-compile
  (require 'cl))

;;; Tab and indentation settings
(setq-default tab-width 4)
(setq-default indent-tabs-mode nil)

;;; Basic keybindings
;; Use C-h as backspace
(global-set-key "\C-h" 'backward-delete-char)
(global-set-key "\M-h" 'help-for-help)

;; C-o to expand completion
(global-set-key "\C-o" 'dabbrev-expand)

;; M-g for goto-line
(global-set-key "\M-g" 'goto-line)

;; Newline behavior
(global-set-key "\C-m" 'newline-and-indent)
(global-set-key "\C-j" 'newline)

;; Unset C-\ (for input method)
(global-unset-key "\C-\\")

;;; Scroll in place functions
(global-unset-key "\M-p")
(global-unset-key "\M-n")

(defun scroll-up-in-place (n)
  "Scroll up the current buffer with keeping cursor position.

- N the number of the lines to scroll up"
  (interactive "p")
  (forward-line (- n))
  (scroll-down n))

(defun scroll-down-in-place (n)
  "Scroll down the current buffer with keeping cursor position.

- N the number of the lines to scroll down"
  (interactive "p")
  (forward-line n)
  (scroll-up n))

(global-set-key "\M-p" 'scroll-up-in-place)
(global-set-key [M-up] 'scroll-up-in-place)
(global-set-key "\M-n" 'scroll-down-in-place)
(global-set-key [M-down] 'scroll-down-in-place)

;;; Mac command modifier
(setq mac-command-modifier 'meta)

;;; Display settings
;; Show line number in mode line
(line-number-mode 1)
;; Show column number in mode line
(setq column-number-mode t)
;; Show time
(display-time)
;; Show active region
(setq-default transient-mark-mode t)
;; Visualize the end of file
(setq-default indicate-empty-lines t)

;;; Coding system
(prefer-coding-system 'utf-8)

;;; Backup settings
;; Do not create ~ files
(setq make-backup-files nil)

;;; Bell settings
;; Disable bell
(setq visible-bell nil)
(setq ring-bell-function 'ignore)

;;; Show paren settings
;; Highlight parentheses
(show-paren-mode t)
;; Highlight the content inside parenthesis
(setq show-paren-style 'expression)
;; Highlight the content ignoring the spaces before and after the parenthesis
(setq show-paren-when-point-in-periphery t)
;; Do not highlight the content if the cursor is on the closing parenthesis
(setq show-paren-when-point-inside-paren nil)

;;; User interface preferences
;; Force to use y-or-n-p
(fset 'yes-or-no-p 'y-or-n-p)
;; Do not concern about upper/lower case in completion
(setq completion-ignore-case t)

;;; Compilation behavior
;; Scroll down compilation buffer when new output is available
(setq compilation-scroll-output t)

;;; File and directory settings
;; Exclude .git directory from find-name-dired
(setq find-name-arg "-not -path '*/\\.git*' -name")
;; Do not ask y-or-n when following symlinks
(setq vc-follow-symlinks t)

;;; Scroll settings
(setq scroll-conservatively 1)

;;; Sort settings
;; Sort with ignoring case
(setq sort-fold-case t)

;;; Word navigation
;; Subword mode for camelCase
(global-subword-mode)

;;; Misc settings
(setq system-uses-terminfo nil)
(setq garbage-collection-messages t)

;;; History
(savehist-mode t)

;;; Highlight indentation mode hook
(add-hook 'highlight-indentation-mode (lambda () (highlight-indentation-mode -1)))

;; Read buffer automatically if an external process modifies it
(use-package autorevert
  :ensure nil
  :init (global-auto-revert-mode))

(setopt show-trailing-whitespace t)

(provide 'init-basic)
;;; init-basic.el ends here
