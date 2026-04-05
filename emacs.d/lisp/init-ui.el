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
  :custom
  (diff-hl-disable-on-remote nil)
  (diff-hl-update-async t)
  :config
  (global-diff-hl-mode)
  (diff-hl-flydiff-mode)
  ;; Use more vivid fringe colors for better visibility on solarized-dark
  ;; foreground = fringe bar, background = fringe area behind the bar
  (set-face-attribute 'diff-hl-change nil :foreground "#E8890C" :background "#7A4C00")
  (set-face-attribute 'diff-hl-insert nil :foreground "#73D936" :background "#2B5000")
  (set-face-attribute 'diff-hl-delete nil :foreground "#FF6B6B" :background "#6B1E24")
  ;; Workaround: diff-hl sometimes misses the initial update on file open
  (add-hook 'diff-hl-mode-hook
            (lambda ()
              (when diff-hl-mode
                (run-with-idle-timer 0.3 nil #'diff-hl-update)))))

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
  :init
  (pulsar-global-mode)
  :custom
  ;; Highlight edited regions when emacs modifies buffers by regions
  (pulsar-pulse-region-functions
    '(yank
      yank-pop
      append-next-kill
      undo
      undo-redo
      backward-kill-word
      kill-word
      ;; vundo
      vundo-backward
      vundo-forward
      vundo-step-back
      vundo-step-forward
      ))
  )

;;;; ============================================================
;;;; Window Layout Management
;;;; ============================================================
;;;;
;;;; IDE-like window layout with three building blocks:
;;;;
;;;; 1. Side Windows (display-buffer-alist)
;;;;    - Designated buffers (vterm, compilation) are automatically
;;;;      displayed in fixed side windows.
;;;;    - Side windows are immune to C-x 1 (delete-other-windows), so they
;;;;      stay visible while you reorganize the main editing area.
;;;;    - Multiple side windows can coexist. The `slot' value controls
;;;;      ordering on the same side (lower slot = further left/top).
;;;;
;;;; 2. Side Window Profiles
;;;;    - Profiles define where each side window appears and how large it is.
;;;;    - `wide'  : for large/external monitors (terminals on bottom)
;;;;    - `narrow' : for laptop screens (terminals on bottom, smaller)
;;;;    - Switch with: C-c w p  (my-switch-side-window-profile)
;;;;    - The new profile applies to buffers opened AFTER switching.
;;;;      Already-open side windows keep their current position.
;;;;
;;;; 3. Winner Mode (built-in)
;;;;    - Tracks window configuration history.
;;;;    - C-c <left>  : undo last window layout change
;;;;    - C-c <right> : redo
;;;;
;;;; Quick Reference:
;;;;   C-c w s   - Toggle all side windows on/off
;;;;   C-c w p   - Switch side window profile (wide/narrow)
;;;;   C-c l     - Open magit-status (full window)
;;;;   C-c L     - Open magit-status (side window, left)
;;;;   C-c <left>  - Undo window layout change (winner-undo)
;;;;   C-c <right> - Redo window layout change (winner-redo)
;;;;   C-x {     - Shrink window horizontally  (repeatable via repeat-mode)
;;;;   C-x }     - Enlarge window horizontally  (repeatable via repeat-mode)
;;;;   C-x ^     - Enlarge window vertically    (repeatable via repeat-mode)
;;;;   C-x +     - Balance all windows
;;;;   C-x r w <c> - Save current window layout to register <c>
;;;;   C-x r j <c> - Restore window layout from register <c>
;;;;
;;;; Customization:
;;;;   - To add a new buffer to side window management, add an entry to
;;;;     `my-side-window-common-buffers' and corresponding entries in
;;;;     each profile in `my-side-window-profiles'.
;;;;   - To add a new profile, add an entry to `my-side-window-profiles'.
;;;; ============================================================

;;; Winner mode - undo/redo window configuration changes
(winner-mode 1)

;;; Side windows - protect specific buffers from C-x 1 etc.
(defvar my-side-window-common-buffers
  '(("\\*vterm.*\\*" . terminal)
    ("\\*compilation\\*" . output))
  "Alist of (CONDITION . TYPE) for side window managed buffers.
CONDITION is a regexp string matching buffer names.")

(defvar my-side-window-profiles
  '((wide . ((terminal . (side bottom slot 0 height 0.3))
             (output . (side bottom slot 1 height 0.3))))
    (narrow . ((terminal . (side bottom slot 0 height 0.25))
               (output . (side bottom slot 1 height 0.25)))))
  "Side window layout profiles for different screen sizes.")

(defvar my-side-window-current-profile 'wide
  "Currently active side window profile.")

(defun my-side-window--build-display-buffer-alist (profile-name)
  "Build `display-buffer-alist' entries from PROFILE-NAME."
  (let ((profile (alist-get profile-name my-side-window-profiles)))
    (mapcar
     (lambda (buf-entry)
       (let* ((condition (car buf-entry))
              (type (cdr buf-entry))
              (conf (alist-get type profile))
              (side (plist-get conf 'side))
              (slot (plist-get conf 'slot))
              (size-key (if (memq side '(left right)) 'window-width 'window-height))
              (size-val (or (plist-get conf 'width) (plist-get conf 'height))))
         `(,condition
           (display-buffer-in-side-window)
           (side . ,side)
           (slot . ,slot)
           (,size-key . ,size-val)
           (window-parameters . ((no-delete-other-windows . t))))))
     my-side-window-common-buffers)))

(defun my-switch-side-window-profile ()
  "Switch side window profile interactively."
  (interactive)
  (let* ((names (mapcar #'car my-side-window-profiles))
         (candidates (mapcar (lambda (name)
                               (if (eq name my-side-window-current-profile)
                                   (format "%s (current)" name)
                                 (symbol-name name)))
                             names))
         (selected (completing-read "Side window profile: " candidates nil t))
         (choice (intern (replace-regexp-in-string " (current)$" "" selected))))
    (setq my-side-window-current-profile choice)
    (setq display-buffer-alist (my-side-window--build-display-buffer-alist choice))
    (message "Side window profile: %s" choice)))

;; Apply default profile
(setq display-buffer-alist (my-side-window--build-display-buffer-alist my-side-window-current-profile))

(defun my-magit-status-side-window ()
  "Open magit-status in a side window on the left."
  (interactive)
  (let ((display-buffer-overriding-action
         '((display-buffer-in-side-window)
           (side . left)
           (slot . 0)
           (window-width . 0.2)
           (window-parameters . ((no-delete-other-windows . t))))))
    (magit-status)))

(global-set-key (kbd "C-c w s") 'window-toggle-side-windows)
(global-set-key (kbd "C-c w p") 'my-switch-side-window-profile)

(provide 'init-ui)
;;; init-ui.el ends here
