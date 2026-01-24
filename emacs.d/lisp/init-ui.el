;;; init-ui.el --- Visual appearance and UI settings -*- lexical-binding: t -*-

;;; Commentary:
;; Visual appearance, themes, and display-related packages.

;;; Code:

;;; GUI settings
(when-darwin
 (when (display-graphic-p)
   ;; see http://d.hatena.ne.jp/kazu-yamamoto/20090122/1232589385
   (if (> (x-display-pixel-width) 1440)
       (setq default-face-height 120)
     (setq default-face-height 100))
   (set-frame-font "Monaco" 12)
   (setq ns-command-modifier (quote meta))
   (setq ns-alternate-modifier (quote super))
   ;; Do not pass control key to mac OS X
   (defvar mac-pass-control-to-system)
   (setq mac-pass-control-to-system nil)
   ;; for emacs24 x mac
   (setq mac-command-modifier 'meta)
   ;; Force to use \ instead of ¥
   (define-key global-map [?¥] [?\\])
   ))

(when (eq system-type 'gnu/linux)
  (defvar default-face-height 100)
  (set-face-attribute 'default nil
                      :height default-face-height)
  (let ((font "Monaco Nerd Font Mono"))
    (if (find-font (font-spec :name font))
        (set-frame-font font 12)))
  ;; special key as meta
  ;; (setq x-super-keysym 'meta)
  )

;;; Text scale functions
(defun text-scale+ ()
  "Increase the size of text of CURRENT-BUFFER."
  (interactive)
  (set-face-attribute 'default nil :height (+ (face-attribute 'default :height) 10)))

(defun text-scale- ()
  "Decrease the size of text of CURRENT-BUFFER."
  (interactive)
  (set-face-attribute 'default nil :height (- (face-attribute 'default :height) 10)))

(defun text-scale0 ()
  "Reset the size of text of CURRENT-BUFFER."
  (interactive)
  (set-face-attribute 'default nil :height default-face-height))

(global-set-key "\M-+" 'text-scale+)
(global-set-key "\M--" 'text-scale-)
(global-set-key "\M-0" 'text-scale0)

;;; Theme settings
(when (display-graphic-p)
  (add-to-list 'custom-theme-load-path (concat (file-name-directory load-file-name) "../themes"))
  (setq custom-theme-directory (concat (file-name-directory load-file-name) "../themes"))
  )

;;; Smerge colors
;; Fix smerge color for solarized theme environment
(setq smerge-refined-added '(t (:inherit smerge-refined-change :background "dark green")))
(setq smerge-refined-removed '(t (:inherit smerge-refined-change :background "dark red")))

;;; Visualize abnormal white spaces
;; Mark zenkaku-whitespaces and tabs
(setq whitespace-style '(tabs tab-mark spaces space-mark))
(setq whitespace-space-regexp "\\(\x3000+\\)")
(setq whitespace-display-mappings '((space-mark ?\x3000 [?\□])
                                    (tab-mark   ?\t   [?\xBB ?\t])))

;;; Display line numbers
(if (functionp 'global-display-line-numbers-mode)
    (global-display-line-numbers-mode)
  )

;;; UI-related packages

;; Need to run (all-the-icons-install-fonts)
(use-package all-the-icons :ensure t)

(use-package base16-theme :ensure t
  :if (display-graphic-p)
  :config
  (setq base16-distinct-fringe-background nil)
  ;; (load-theme 'base16-solarized-dark t)
  )

(use-package solarized-theme :ensure t
  :if (display-graphic-p)
  :config
  (load-theme 'solarized-dark t)
  )

(use-package diff-hl :ensure t
  :custom (diff-hl-disable-on-remote nil)
  :config (global-diff-hl-mode))

(use-package hl-line
  ;; It is difficult to disable hl-line mode for specific modes if we use (global-hl-line-mode).
  ;; For example, (setq-local global-hl-line-mode nil) does not work for vterm mode if we launch
  ;; emacs in terminals.
  ;; Instead, we enable hl-line-mode for all the text modes and prog modes.
  ;; https://emacsredux.com/blog/2020/11/21/disable-global-hl-line-mode-for-specific-modes/
  :hook
  (prog-mode-hook . hl-line-mode)
  (text-mode-hook . hl-line-mode)
  )

(use-package emoji
  :ensure nil
  :bind (("C-:" . 'emoji-search))
  )

(use-package emojify :ensure t
  :if (display-graphic-p)
  :hook (org-mode . emojify-mode)
  )

(use-package auto-highlight-symbol
  :ensure t
  :config (global-auto-highlight-symbol-mode t)
  :bind (:map auto-highlight-symbol-mode-map
              ;; Do not allow ahs to steal M--
              ("M--" . 'text-scale-)))

(defun my-toggle-window-persistence ()
  "Toggle persistence for the current window, preventing or allowing
it from being deleted by `delete-other-windows` (C-x 1)."
  (interactive)
  (let* ((window (selected-window))
         (param 'no-delete-other-windows)
         (current-status (window-parameter window param)))
    (set-window-parameter window param (not current-status))
    (message "Window persistence %s." (if current-status "OFF" "ON"))))

(global-set-key (kbd "C-c , d") 'my-toggle-window-persistence)

;;; Frame management
(defun my-frame-move-left ()
  "Move the current frame to the left half of the screen."
  (interactive)
  (modify-frame-parameters nil '((left . 0.0) (top . 0.0) (width . 0.5) (height . 1.0))))

(defun my-frame-move-right ()
  "Move the current frame to the right half of the screen."
  (interactive)
  (modify-frame-parameters nil '((left . 1.0) (top . 0.0) (width . 0.5) (height . 1.0))))

(defun my-frame-move-top ()
  "Move the current frame to the top half of the screen."
  (interactive)
  (modify-frame-parameters nil '((left . 0.0) (top . 0.0) (width . 1.0) (height . 0.5))))

(defun my-frame-move-bottom ()
  "Move the current frame to the bottom half of the screen."
  (interactive)
  (modify-frame-parameters nil '((left . 0.0) (top . 1.0) (width . 1.0) (height . 0.5))))

(global-set-key (kbd "C-M-<left>") 'my-frame-move-left)
(global-set-key (kbd "C-M-<right>") 'my-frame-move-right)
;; Do not enable these keybinds because of the conflicts with multiple-cursors
;; (global-set-key (kbd "C-M-<up>") 'my-frame-move-top)
;; (global-set-key (kbd "C-M-<down>") 'my-frame-move-bottom)

;; Display an indicator at the 100th column
(setq-default fill-column 100)
(global-display-fill-column-indicator-mode)
;; Use a light gray as the default color is a bit dark
(set-face-foreground 'fill-column-indicator "#555555")

;; Highlight changes
(use-package pulsar
  :config
  (pulsar-global-mode))

(provide 'init-ui)
;;; init-ui.el ends here
