;;; init-ui.el --- Visual appearance and UI settings -*- lexical-binding: t -*-

;;; Commentary:
;; Visual appearance, themes, and display-related packages.

;;; Code:

;;; GUI settings
(require 'seq)

(defvar my-default-face-height 100
  "Default face height in 1/10 pt.  Set per-display in the platform blocks.")

(defvar my-font-candidates
  '(;; Monaco first -- it is simply the most readable of the lot.  It has no
    ;; Japanese glyphs, so Japanese falls back to another family whose
    ;; advance width has nothing to do with Monaco's; `my-tune-cjk-font'
    ;; below fixes that up.  Org needs the fix because `org-table-align' pads
    ;; cells by `string-width', which counts a full-width character as two
    ;; columns: at any ratio other than 1:2 the `|' separators of a table
    ;; containing Japanese drift further apart on every row.
    "Monaco"
    "Monaco Nerd Font Mono"
    ;; Fallbacks for machines without Monaco.  These ship Japanese glyphs at
    ;; exactly twice the half-width advance already, so they need no tuning.
    "HackGen Console NF"
    "HackGen35 Console NF"
    "HackGen"
    "UDEV Gothic NF"
    "UDEV Gothic"
    "PlemolJP Console NF"
    "PlemolJP"
    "Cica"
    "Ricty Diminished")
  "Font families for the default face, most preferred first.
The first family that is actually installed wins, so an entry that is not
present on this machine simply falls through to the next one.")

(defvar my-cjk-fallback-font-candidates
  '("Hiragino Sans" "Hiragino Kaku Gothic ProN"
    "Noto Sans Mono CJK JP" "Noto Sans CJK JP" "IPAGothic"
    "HackGen" "UDEV Gothic" "PlemolJP" "Cica" "Ricty Diminished")
  "Japanese families to pin when the default face font has no CJK glyphs.")

(defun my-first-available-font (candidates)
  "Return the first family in CANDIDATES that is installed, or nil."
  (seq-find (lambda (family) (find-font (font-spec :family family))) candidates))

(defun my-cjk-font-width-ratio ()
  "Return rendered width of a full-width char divided by a half-width one.
Return nil when the width cannot be measured (non-graphical display).  A
value of 2.0 is what Org tables with Japanese text need; see
`my-font-candidates'."
  (when (and (display-graphic-p) (fboundp 'string-pixel-width))
    (let ((half (string-pixel-width "aa"))
          (full (string-pixel-width "ああ")))
      (when (> half 0)
        (/ (float full) half)))))

(defun my-check-cjk-font-ratio ()
  "Report whether full-width chars render at exactly twice the half-width.
Use this to verify the font setup instead of eyeballing a table."
  (interactive)
  (let ((ratio (my-cjk-font-width-ratio)))
    (cond
     ((null ratio)
      (message "Cannot measure glyph widths on this display."))
     ((< (abs (- ratio 2.0)) 0.02)
      (message "Full/half width ratio is %.3f -- Org tables with Japanese line up."
               ratio))
     (t
      (message "Full/half width ratio is %.3f (want 2.000) -- Org tables with Japanese will drift. Try M-x my-tune-cjk-font"
               ratio)))))

(defun my--set-cjk-font (family size)
  "Render the CJK charsets with FAMILY at SIZE pixels."
  (dolist (charset '(japanese-jisx0208 japanese-jisx0212
                     katakana-jisx0201 kana han cjk-misc))
    ;; ADD nil replaces the charset's entry outright, so re-running this
    ;; (after `text-scale+', say) does not pile up stale sizes behind it.
    (set-fontset-font t charset (font-spec :family family :size size)))
  (clear-face-cache))

(defun my-tune-cjk-font ()
  "Make full-width characters render exactly twice as wide as half-width ones.
A no-op for the 1:2 families listed in `my-font-candidates'.  It is Monaco
-- the preferred family -- that needs this: Monaco carries no Japanese
glyphs, so Japanese falls back to a family whose advance width has nothing
to do with Monaco's, and Org tables containing Japanese drift apart.

A full-width glyph advances by its em box, so pinning the fallback family
to twice `frame-char-width' pixels makes it occupy exactly two columns.
Rounding inside the font can miss by a pixel, hence the small search around
that nominal size.

Note the cost of keeping Monaco: Monaco advances only ~0.6 em, so twice
that is ~1.2 em and the Japanese font ends up visibly larger than the ASCII
one -- lines containing Japanese are taller than pure-ASCII lines.

The pinned size is absolute, so this has to run again whenever the default
face height changes; `text-scale+' and friends below do that."
  (interactive)
  (let ((ratio (my-cjk-font-width-ratio)))
    (when (and ratio (> (abs (- ratio 2.0)) 0.001))
      (let* ((family (my-first-available-font my-cjk-fallback-font-candidates))
             (nominal (* 2 (frame-char-width))))
        (when family
          (unless (catch 'aligned
                    (dolist (size (list nominal (1- nominal) (1+ nominal)
                                        (- nominal 2) (+ nominal 2)))
                      (when (> size 0)
                        (my--set-cjk-font family size)
                        (let ((measured (my-cjk-font-width-ratio)))
                          (when (and measured
                                     (< (abs (- measured 2.0)) 0.001))
                            (throw 'aligned t)))))
                    nil)
            ;; Nothing landed exactly.  Keep the nominal size, which is the
            ;; closest, and say so rather than leaving tables quietly crooked.
            (my--set-cjk-font family nominal)
            (message "Could not align %s to twice the ASCII width (M-x my-check-cjk-font-ratio)"
                     family)))))))

(defun my-apply-default-font (family)
  "Apply FAMILY to the default face and seed `default-frame-alist'."
  ;; Set the default face's family/height explicitly rather than only
  ;; the frame `font' parameter via `set-frame-font'.  With just the
  ;; frame parameter, the default face's `:family' stays unspecified, so
  ;; `(face-attribute 'default :font)' is unstable: creating a child
  ;; frame (e.g. vertico-posframe on the first `C-x b') re-resolves it to
  ;; the macOS default proportional font (Helvetica), which then leaks
  ;; into normal buffers like dired.  An explicit family keeps it put.
  (set-face-attribute 'default nil :family family :height my-default-face-height)
  ;; NOTE: seed `default-frame-alist' with a plain font string rather than
  ;; calling `set-frame-font' here -- re-applying the font on the running
  ;; frame at startup reintroduces the very fallback this guards against.
  (setf (alist-get 'font default-frame-alist)
        (format "%s-%d" family (/ my-default-face-height 10))))

(defun my-setup-fonts ()
  "Pick the best installed family from `my-font-candidates' and apply it."
  (let ((family (my-first-available-font my-font-candidates)))
    (when family
      (my-apply-default-font family)))
  ;; Defer the width check until the initial frame is fully set up --
  ;; `string-pixel-width' needs a live window to measure against.
  (add-hook 'window-setup-hook #'my-tune-cjk-font))

(when-darwin
 (when (display-graphic-p)
   ;; see http://d.hatena.ne.jp/kazu-yamamoto/20090122/1232589385
   (if (> (x-display-pixel-width) 1440)
       (setq my-default-face-height 120)
     (setq my-default-face-height 100))
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

;; On GNU/Linux, to use the special key as meta:
;; (setq x-super-keysym 'meta)

;; Must run after the platform blocks above, which set
;; `my-default-face-height'.
(when (display-graphic-p)
  (my-setup-fonts))

;;; Text scale functions
;; `my-tune-cjk-font' pins the Japanese font to an absolute pixel size, which
;; cannot follow the ASCII font on its own -- re-run it after every change to
;; the default face height or Org tables go crooked again at the new size.
(defun text-scale+ ()
  "Increase the size of text of CURRENT-BUFFER."
  (interactive)
  (set-face-attribute 'default nil :height (+ (face-attribute 'default :height) 10))
  (my-tune-cjk-font))

(defun text-scale- ()
  "Decrease the size of text of CURRENT-BUFFER."
  (interactive)
  (set-face-attribute 'default nil :height (- (face-attribute 'default :height) 10))
  (my-tune-cjk-font))

(defun text-scale0 ()
  "Reset the size of text of CURRENT-BUFFER."
  (interactive)
  (set-face-attribute 'default nil :height my-default-face-height)
  (my-tune-cjk-font))

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
  :custom
  (solarized-scale-org-headlines nil)
  (solarized-scale-outline-headlines nil)
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

(use-package dired-icon :ensure t
  :hook (dired-mode-hook . dired-icon-mode))

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
  :config
  ;; Pulsar runs `pulsar-resolve-function-aliases' every time
  ;; `pulsar-mode' is enabled in a new buffer, and each invocation walks
  ;; the entire obarray twice via `mapatoms'. With many agenda files
  ;; this dominates the cost of opening Org buffers (82% of cold-path
  ;; org-agenda time in profiling). The function only mutates the two
  ;; global lists `pulsar-pulse-functions' and
  ;; `pulsar-pulse-region-functions', so a single run per session is
  ;; sufficient.
  (defvar my-pulsar-resolve-done nil
    "Non-nil after `pulsar-resolve-function-aliases' has run once.")
  (defun my-pulsar-resolve-function-aliases-once (orig &rest args)
    "Run ORIG only on the first call in this Emacs session."
    (unless my-pulsar-resolve-done
      (setq my-pulsar-resolve-done t)
      (apply orig args)))
  (advice-add 'pulsar-resolve-function-aliases
              :around #'my-pulsar-resolve-function-aliases-once))

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

;;; Left side windows: expand on focus, shrink on blur
;;
;; A magit buffer (or the forge ediff review file-list sidebar) shown in a
;; left side window is too narrow for everyday reading, but a permanently
;; wide side window steals horizontal space from the main editing area. The
;; block below resolves this by watching `window-selection-change-functions'
;; and resizing such a window to `my-magit-side-window-focused-width' while
;; it has focus, and back to `my-magit-side-window-unfocused-width' as soon
;; as focus moves away.  Resizing the review sidebar on every focus also
;; re-asserts its width after ediff transiently shrinks it on navigation.

(defcustom my-magit-side-window-focused-width 80
  "Width in columns for a focus-resize left side window while it has focus.
Applies to magit buffers and the review file-list sidebar."
  :type 'integer
  :group 'magit)

(defcustom my-magit-side-window-unfocused-width 30
  "Width in columns for a focus-resize left side window without focus.
Applies to magit buffers and the review file-list sidebar."
  :type 'integer
  :group 'magit)

(defun my-magit-left-side-window-p (window)
  "Return non-nil when WINDOW is a left side window that should focus-resize.
Covers magit buffers and the forge ediff review file-list sidebar
\(`*forge-review-files*'), so both widen while selected and shrink back on
blur.  The sidebar is matched by buffer name to avoid loading the review
feature just to know its mode."
  (and (window-live-p window)
       (eq (window-parameter window 'window-side) 'left)
       (let ((buffer (window-buffer window)))
         (or (with-current-buffer buffer (derived-mode-p 'magit-mode))
             (equal (buffer-name buffer) "*forge-review-files*")))))

(defun my-magit-resize-window-to (window target-width)
  "Resize WINDOW horizontally to TARGET-WIDTH columns."
  (let ((width-delta (- target-width (window-width window))))
    (unless (zerop width-delta)
      ;; Pass IGNORE=t so window-resize bypasses the preserved-size constraint
      ;; that display-buffer-in-side-window installs from `window-width'.
      (ignore-errors
        (window-resize window width-delta t t)))))

(defun my-magit-adjust-side-window-on-focus (&optional frame)
  "Widen the focused focus-resize left side window in FRAME, narrow the others.
Hooked into `window-selection-change-functions' so such a side window (a
magit buffer or the review file-list sidebar) is expanded only while it is
selected, and shrunk back as soon as focus moves away."
  (let ((selected-window-in-frame (frame-selected-window frame)))
    (dolist (frame-window (window-list frame))
      (when (my-magit-left-side-window-p frame-window)
        (my-magit-resize-window-to
         frame-window
         (if (eq frame-window selected-window-in-frame)
             my-magit-side-window-focused-width
           my-magit-side-window-unfocused-width))))))

(with-eval-after-load 'magit
  (add-hook 'window-selection-change-functions
            'my-magit-adjust-side-window-on-focus))

(global-set-key (kbd "C-c w s") 'window-toggle-side-windows)
(global-set-key (kbd "C-c w p") 'my-switch-side-window-profile)

(provide 'init-ui)
;;; init-ui.el ends here
