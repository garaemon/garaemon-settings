;;; garaemon-dot-emacs.el --- This is the emacs settings file for garaemon

;;; Commentary:
;; Use C-# to toggle folding for visibility.

;;; Code:

(require 'garaemon-util)
(eval-when-compile
  (require 'cl))

;;; basic setting {{{
;; C-o to expand completion
(global-set-key "\C-o" 'dabbrev-expand)
;; Increase threshold to fire garbage collection
(setq gc-cons-threshold 134217728)
(global-set-key "\C-h" 'backward-delete-char)
(global-set-key "\M-h" 'help-for-help)
;; C-x p to switch buffer with inverse manner.
(global-set-key "\C-xp" (lambda ()
                          (interactive)
                          (other-window -1)))
;; Show line number
(line-number-mode 1)
;; Show time
(display-time)
;; Show active region
(setq-default transient-mark-mode t)
(global-set-key "\M-g" 'goto-line)
;; Indent when insert newline
(global-set-key "\C-m" 'newline-and-indent)
(global-set-key "\C-j" 'newline)
;; Do not concer about upper/lower case in completion.
(setq completion-ignore-case t)
(global-unset-key "\C-\\")
(set-language-environment "Japanese")
(prefer-coding-system 'utf-8)
(setq column-number-mode t) ; show column number
;; no scroll bar
(scroll-bar-mode -1)
;; no menu bar
(menu-bar-mode -1)
;; no tool bar
(tool-bar-mode -1)
(setq scroll-conservatively 1)
;; Do not create ~ files
(setq make-backup-files nil)
;; Disable bell
(setq visible-bell nil)
(setq ring-bell-function 'ignore)
;; Highlight parens
(show-paren-mode t)
(setq show-paren-style 'mixed)
;; Disable hard tabs
(setq-default indent-tabs-mode nil)
;; Disable startup image
(setq inhibit-startup-message t)
;; Force to use y-or-n-p
(fset 'yes-or-no-p 'y-or-n-p)
;; ??
(setq system-uses-terminfo nil)
(setq-default tab-width 4)
;; scroll down compilation buffer when new output is available.
(setq compilation-scroll-output t)
;; sort with ignoring case.
(setq sort-fold-case t)
(eldoc-mode nil)
;; subword for camelcase
(global-subword-mode)
;; do not ask y-or-n when saving all
(defun save-all ()
  "Save all buffers without y-or-n asking."
  (interactive)
  (save-some-buffers t))
(global-set-key "\C-xs" 'save-all)
;; Do not ask y-or-n when following symlinks
(setq vc-follow-symlinks t)

(defun open-setting-file ()
  "Open this file."
  (interactive)
  (find-file "~/.emacs./lisp/garaemon-dot-emacs.el"))

(defun rad2deg (rad)
  "Convert radian RAD to degree."
  (* (/ rad pi) 180))

(defun deg2rad (deg)
  "Convert degree DEG to radian."
  (* (/ deg 180.0) pi))

(defun rad2deg-interactive (rad)
  "Convert radian RAD to degree."
  (interactive "nrad ")
  (message "%f rad -> %f deg" rad (rad2deg rad)))

(defun deg2rad-interactive (deg)
  "Convert degree DEG to radian."
  (interactive "ndeg ")
  (message "%f deg -> %f rad" deg (deg2rad deg)))

(defun jump-to-corresponding-brace ()
  "Move to corresponding brace."
  (interactive)
  (let ((c (following-char))
        (p (preceding-char)))
    (if (eq (char-syntax c) 40) (forward-list)
      (if (eq (char-syntax p) 41) (backward-list)
        (backward-up-list)))))
(global-set-key (kbd "C-,") 'jump-to-corresponding-brace)

;;; }}}

;;; scroll in place {{{

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
;;; }}}

;;; GUI setting {{{
(when-darwin
 (when (display-graphic-p)
   ;; see http://d.hatena.ne.jp/kazu-yamamoto/20090122/1232589385
   (defvar default-face-height 120)
   (set-face-attribute 'default nil :family "monaco" :height default-face-height)
   ;; Japanese font
   (set-fontset-font
    nil 'japanese-jisx0208
    (font-spec :family "Hiragino Kaku Gothic ProN")) ; font
   (setq ns-command-modifier (quote meta))
   (setq ns-alternate-modifier (quote super))
   ;; Do not pass control key to mac OS X
   (defvar mac-pass-control-to-system)
   (setq mac-pass-control-to-system nil)
   ;; for emacs24 x mac
   (setq mac-command-modifier 'meta)))

(when (eq system-type 'gnu/linux)
  (defvar default-face-height 120)
  (set-face-attribute 'default nil
                      :height default-face-height)    ;font size
  ;;(set-frame-font "Ricty Diminished-12")
  ;; special key as meta
  ;; (setq x-super-keysym 'meta)
  )

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
;;; }}}

;;; theme {{{
(add-to-list 'custom-theme-load-path "~/.emacs.d/themes")
(setq custom-theme-directory "~/.emacs.d/themes")
(if (not (display-graphic-p))
  (load-theme 'garaemon-solarized-dark t))
;;; }}}

;;; smerge {{{
;; fix smerge color for solarized theme environment
(setq smerge-refined-added '(t (:inherit smerge-refined-change :background "dark green")))
(setq smerge-refined-removed '(t (:inherit smerge-refined-change :background "dark red")))
;;; }}}

;;; Visualize abnormal white spaces such as hard tab and japanese space. {{{
;; mark zenkaku-whitespaces and tabs
(setq whitespace-style '(tabs tab-mark spaces space-mark))
(setq whitespace-space-regexp "\\(\x3000+\\)")
(setq whitespace-display-mappings '((space-mark ?\x3000 [?\□])
                                    (tab-mark   ?\t   [?\xBB ?\t])))
;;; anthy setting {{{
(when (and (or (eq system-type 'cygwin)
               (eq system-type 'gnu/linux))
           (<= emacs-major-version 26))
  (setq load-path (append '("/usr/share/emacs/site-lisp/anthy/") load-path))
  (when (require 'anthy nil t)
    (global-unset-key "\C-\\")
    (setq default-input-method "japanese-anthy")
    (global-set-key "\C-\\" 'anthy-mode)))
;;; }}}

;;; Cuda {{{
(setq auto-mode-alist (cons (cons "\\.cu?$" 'c-mode) auto-mode-alist))
(setq auto-mode-alist (cons (cons "\\.cg?$" 'c-mode) auto-mode-alist))
;;; }}}

;;; C+++ {{{
(setq auto-mode-alist (cons (cons "\\.h?$" 'c++-mode) auto-mode-alist))
;;; }}}

;;; lisp {{{
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
;;; }}}

;;; emacslisp {{{
(define-key emacs-lisp-mode-map "\C-cr" 'my-indent-sexp)
;;; }}}

;;; haskell {{{
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
;;; }}}

;;; html {{{
(setq auto-mode-alist (cons (cons "\\.html$" 'html-mode) auto-mode-alist))
(setq auto-mode-alist (cons '("\\.\\(xml\\|xsl\\|rng\\|xhtml\\|kml\\|gpx\\)\\'" . html-mode)
                            auto-mode-alist))
(add-to-list 'auto-mode-alist '("\\.ejs$" . html-mode))
(add-to-list 'auto-mode-alist '("\\.xml$" . html-mode))
(add-to-list 'auto-mode-alist '("\\.launch$" . html-mode))
(add-to-list 'auto-mode-alist '("\\.test$" . html-mode))

;;; }}}

;;; nxml {{{
(defvar nxml-child-indent 2)
(setq mumamo-background-colors nil)
;;; }}}

;;; sdic {{{
(autoload 'sdic-describe-word "sdic" "英単語の意味を調べる" t nil)
(global-set-key "\C-cw" 'sdic-describe-word)
(autoload 'sdic-describe-word-at-point "sdic" "カーソルの位置の英単語の意味を調べる" t nil)
(global-set-key "\C-cW" 'sdic-describe-word-at-point)
;;; }}}

;;; ruby {{{
(add-to-list 'auto-mode-alist '("\\.thor$" . ruby-mode))
(defvar ruby-indent-level 2)
;;; }}}

;;; objective-c {{{
(add-to-list 'magic-mode-alist
             `(,(lambda ()
                  (and (string= (file-name-extension buffer-file-name) "h")
                       (re-search-forward "@\\<interface\\>"
                                          magic-mode-regexp-match-limit t))) . objc-mode))
(add-to-list 'auto-mode-alist '("\\.mm$" . objc-mode))
(add-to-list 'auto-mode-alist '("\\.m$" . objc-mode))
;;; }}}

;;; nlinum or display-line-numbers {{{
(if (functionp 'global-display-line-numbers-mode)
    (progn
      (global-display-line-numbers-mode)
      (defun display-line-numbers-color-on-after-init (frame)
        "Hook function executed after FRAME is generated."
        (unless (display-graphic-p frame)
          (set-face-background
           'line-number
           (plist-get base16-solarized-dark-colors :base01))))
      (add-hook 'after-make-frame-functions
                (lambda (frame)
                  (display-line-numbers-color-on-after-init frame)))
      ))
;;; }}}

;;; Delete trailing whitespaces when saving the file. {{{
(add-hook 'before-save-hook 'delete-trailing-whitespace)
;;; }}}

;;; insert date at current cursor {{{
(defun insert-date ()
  "Insert date at current cursor."
  (interactive)
  (insert (format-time-string "%Y-%m-%dT%H:%M:%SZ\n" nil t)))
;;; }}}

;;; query-replace-regexp. {{{
(defalias 'qrr 'query-replace-regexp)
;; for mistype :)
(global-set-key "\M-%" 'query-replace)
;;; }}}

;;; rosemacs {{{
(when
    (require 'rosemacs nil t)
  (invoke-rosemacs)
  (global-set-key "\C-x\C-r" ros-keymap))
;;; }}}

;;; useful functions to manage multiple windows. {{{
(defun split-window-vertically-n (num-wins)
  "Split window vertically into NUM-WINS windows."
  (interactive "p")
  (if (= num-wins 2)
      (split-window-vertically)
    (progn (split-window-vertically (- (window-height)
                                       (/ (window-height) num-wins)))
           (split-window-vertically-n (- num-wins 1)))))

(defun split-window-horizontally-n (num-wins)
  "Split window horizontally into NUM-WINS windows."
  (interactive "p")
  (if (= num-wins 2)
      (split-window-horizontally)
    (progn (split-window-horizontally (- (window-width)
                                         (/ (window-width) num-wins)))
           (split-window-horizontally-n (- num-wins 1)))))

(defun other-window-or-split ()
  "Split window if there is enough space and switch to next window."
  (interactive)
  (when (one-window-p)
    (if (>= (window-body-width) 300)
        (let ((split-num (/ (window-body-width) 100)))
          (split-window-horizontally-n split-num))
      (split-window-horizontally)))
  (win-switch-dispatch))

(global-set-key "\M-o" 'other-window-or-split)
(global-set-key "\C-x@" '(lambda ()
                           (interactive)
                           (split-window-vertically-n 3)))
(global-set-key "\C-x#" '(lambda ()
                           (interactive)
                           (split-window-horizontally-n 3)))
;;; }}}


;;; code-format-view {{{
(when (require 'code-format nil t)
  ;; (global-set-key "\M-[" 'code-format-view)
  (global-unset-key "\M-[")
  (setq code-format-yapf-options '("--style" "google")))
;;; }}}

;;; Show eidiff with horizontal split view. {{{
(setq ediff-split-window-function 'split-window-horizontally)
;;; }}}


;;; Re-open current file with \M-r {{{
(defun revert-buffer-no-confirm (&optional force-reverting)
  "Force to reload buffer if the file is modiied or FORCE-REVREZTING is t.

Ignoring the auto-save file and not requesting for confirmation.
When the current buffer is modified, the command refuses to revert it,
unless you specify the optional argument: FORCE-REVERTING to true."
  (interactive "P")
  ;;(message "force-reverting value is %s" force-reverting)
  (if (or force-reverting
          (not (buffer-modified-p)))
      (revert-buffer
       :ignore-auto
       :noconfirm)
    (error
     "The buffer has been modified")))
(global-set-key "\M-r" 'revert-buffer-no-confirm)
;;; }}}

;;; tmux integration utilities {{{
(defun open-current-file-in-tmux ()
  "Open current file in tmux."
  (interactive)
  (let ((file-path (buffer-file-name)))
    (let ((target-dir (if (file-directory-p file-path)
                          file-path
                        (file-name-directory file-path))))
      (message (format "Opening directory %s in tmux" target-dir))
      (call-process-shell-command (format
                                   "tmux new-window -a -t $(tmux ls -F \"#S\") -c %s"
                                   target-dir) nil "*tmux-output*" nil
                                   ))))

(global-set-key "\M-t" 'open-current-file-in-tmux)
;;; }}}

;;; Increase and decrease the number at point. {{{
(defun increment-number-at-point ()
  "Increase number at current cursor."
  (interactive)
  (skip-chars-backward "0123456789")
  (or (looking-at "[0123456789]+")
      (error
       "No number at point"))
  (replace-match (number-to-string (1+ (string-to-number (match-string 0))))))
(defun decrement-number-at-point ()
  "Decrease number at current cursor."
  (interactive)
  (skip-chars-backward "0123456789")
  (or (looking-at "[0123456789]+")
      (error
       "No number at point"))
  (replace-match (number-to-string (1- (string-to-number (match-string 0))))))

(global-set-key (kbd "C-c C-+") 'increment-number-at-point)
(global-set-key (kbd "C-c C-;") 'increment-number-at-point)
(global-set-key (kbd "C-c C--") 'decrement-number-at-point)
;;; }}}

;;; shell-script {{{
(add-to-list 'auto-mode-alist '("\\.subr$" . shell-script-mode))
;;; }}}

;;; elisp format {{{
(require 'elisp-format nil t)
;;; }}}

;;; ros {{{
(setq auto-mode-alist (cons (cons "\\.urdf$" 'xml-mode) auto-mode-alist))
(setq auto-mode-alist (cons (cons "\\.xacro$" 'xml-mode) auto-mode-alist))
(setq auto-mode-alist (cons (cons "\\.launch$" 'xml-mode) auto-mode-alist))

;; Based on https://www.seas.upenn.edu/~chaoliu/2018/03/12/ros-programming-in-emacs/#org8817889

(defun ros-catkin-make (dir)
  "Run catkin_make command in DIR."
  (interactive (list (file-name-directory (buffer-file-name))))
  ;; clear compilation buffer first not to occupy memory space.
  (if (get-buffer "*catkin_make*")
      (kill-buffer "*catkin_make*"))
  (let* ((default-directory dir)
         (compilation-buffer-name-function (lambda (major-mode-name) "*catkin_make*")))
    (compile "catkin bt --no-status"))
  ;; (switch-to-buffer (get-buffer "*catkin_make*"))
  (switch-to-buffer-other-window (get-buffer-create "*catkin_make*"))
  )

(defun ros-catkin-make-json (dir)
  "Run catkin_make command in DIR."
  (interactive (list (file-name-directory (current-buffer))))
  (let* ((default-directory dir)
         (compilation-buffer-name-function (lambda (major-mode-name) "*catkin_make*")))
    (compile "catkin_make -DCMAKE_EXPORT_COMPILE_COMMANDS=1 ."))
  )

(global-set-key (kbd "C-x C-m") 'ros-catkin-make)
(global-set-key (kbd "C-x m") 'ros-catkin-make) ; Hijack key for compose-mail
(global-set-key [f5] 'ros-catkin-make)
;;; }}}

;; Provide package
(provide 'garaemon-dot-emacs)

;; Local Variables:
;; byte-compile-warnings: (not free-vars)
;; eval: (origami-mode)
;; End:
