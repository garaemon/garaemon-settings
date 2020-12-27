;;; dot.emacs --- entrypoint of setting emacs

;;; This elisp provides minimum settings for coding and load
;;; other settings.

;;; Commentary:

;;; Code:
;;; ln -sf ~/.emacs.d/dot.emacs ~/.emacs

(add-to-list 'load-path "~/.emacs.d/lisp")
(add-to-list 'load-path "~/.emacs.d/plugins")

;; remove tramp file first to clean up old tramp connection
(let ((tramp-old-file (expand-file-name "~/.emacs.d/tramp")))
  (require 'tramp)
  (tramp-cleanup-all-buffers)
  (call-interactively 'tramp-cleanup-all-connections)
  (if (file-exists-p tramp-old-file)
      (progn
        (message "deleting %s" tramp-old-file)
        (delete-file tramp-old-file))))

;; minimum settings
(setq-default tab-width 4)
;; disable hard-tab
(setq-default indent-tabs-mode nil)
;; use C-h as backspace
(global-set-key "\C-h" 'backward-delete-char)

;; Use M-p and M-n to scoll in place
(global-unset-key "\M-p")
(global-unset-key "\M-n")

(defun scroll-up-in-place (n)
  "Scroll up the current buffer with keeping cursor position.

- N the number of the lines to scroll up"
  (interactive "p")
  ;;(line-move-visual (- n) t)
  (forward-line (- n))
  (scroll-down n))

(defun scroll-down-in-place (n)
  "Scroll down the current buffer with keeping cursor position.

- N the number of the lines to scroll down"
  (interactive "p")
  ;;(line-move-visual n t)
  (forward-line n)
  (scroll-up n))

(global-set-key "\M-p" 'scroll-up-in-place)
(global-set-key [M-up] 'scroll-up-in-place)
(global-set-key "\M-n" 'scroll-down-in-place)
(global-set-key [M-down] 'scroll-down-in-place)

(global-set-key "\C-o" 'dabbrev-expand)
(setq mac-command-modifier 'meta)

(add-hook 'highlight-indentation-mode (lambda () (highlight-indentation-mode -1)))

;; Bind C-x # to switch back to tmux window where emacsclient run.
;; In order to use this feature, the window index should be stored in ~/.emacs.d/emacsclient-window.
(global-set-key
 "\C-x#"
 (lambda ()
   (interactive)
   (shell-command "tmux select-window -t \`cat ~/.emacs.d/emacsclient-window\`")))

(require 'garaemon-util)
(eval-when-compile
  (require 'cl))

;;; basic setting {{{
;; C-o to expand completion
(global-set-key "\C-o" 'dabbrev-expand)
(setq garbage-collection-messages t)

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
(prefer-coding-system 'utf-8)
(setq column-number-mode t) ; show column number
;; no scroll bar
(scroll-bar-mode -1)
;; no menu bar
(menu-bar-mode -1)
;; no tool bar
(tool-bar-mode -1)
;; The default of find-name-arg is "-name".
;; In order to exclude git directory from `find-name-dired', add option to exclude .git directory.
(setq find-name-arg "-not -path '*/\.git*' -name")
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
(global-set-key "\M-&" 'query-replace)
;;; }}}

;;; rosemacs {{{
(when
    (require 'rosemacs nil t)
  (invoke-rosemacs)
  (global-set-key "\C-x\C-r" ros-keymap))
(defun get-package-name-for-dynamic-reconfigure-cfg ()
  (interactive)                       ;for debug
  ;; package/cfg/Foo.cfg
  (let* ((full-current-file-name (buffer-file-name)))
    (message (file-name-nondirectory
              (substring                ;Remove trailing /
               (file-name-directory
                (substring              ;Remoev trailing /
                 (file-name-directory full-current-file-name) 0 -1))
               0 -1))))
  )
(defun get-file-name-for-dynamic-reconfigure-cfg ()
  (interactive)                         ;for debug
  ;; package/cfg/Foo.cfg
  (file-name-base (buffer-file-name)))
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

(defun ros-catkin-make-impl (dir option)
  (if (get-buffer "*catkin_make*")
      (kill-buffer "*catkin_make*"))
  (let* ((default-directory dir)
         (compilation-buffer-name-function (lambda (major-mode-name) "*catkin_make*")))
    (compile (concat "catkin bt --no-status " option)))
  (switch-to-buffer-other-window (get-buffer-create "*catkin_make*"))
  )

(defun ros-catkin-make (dir)
  "Run catkin build --this command in DIR."
  (interactive (list default-directory))
  (ros-catkin-make-impl dir nil)
  )

(defun ros-catkin-make-no-deps (dir)
  "Run catkin build --thid --no-deps command in DIR."
  (interactive (list default-directory))
  (ros-catkin-make-impl dir "--no-deps")
  )

(defun ros-catkin-make-json (dir)
  "Run catkin_make command in DIR."
  (interactive (list (file-name-directory (current-buffer))))
  (let* ((default-directory dir)
         (compilation-buffer-name-function (lambda (major-mode-name) "*catkin_make*")))
    (compile "catkin_make -DCMAKE_EXPORT_COMPILE_COMMANDS=1 ."))
  )

(global-set-key (kbd "C-x C-m") 'ros-catkin-make-no-deps)
(global-set-key (kbd "C-x m") 'ros-catkin-make) ; Hijack key for compose-mail
(global-set-key [f5] 'ros-catkin-make)
;;; }}}

(require 'package)
(setq package-archives
      '(("gnu" . "http://elpa.gnu.org/packages/")
        ("melpa" . "http://melpa.org/packages/")
        ("org" . "http://orgmode.org/elpa/")))

(unless (require 'use-package nil t)
  (package-initialize)
  (unless (package-installed-p 'use-package)
    (package-refresh-contents))
  ;; Install use-package
  (package-install 'use-package))

;; (when (executable-find "pdftex")
;;   (use-package auctex :ensure t)) ;; it depends on tex
;; Need to run (all-the-icons-install-fonts)
(use-package all-the-icons :ensure t)

(use-package anzu :ensure t
  :defer t
  :config (progn
            (global-anzu-mode +1)
            (setq anzu-search-threshold 1000)))

(use-package backup-each-save :ensure t
  :config (progn
            (setq backup-each-save-mirror-location "~/.emacs.d/backups")
            ;; suffix for backup file
            (setq backup-each-save-time-format "%y%m%d_%H%M%S")
            ;; the size limit of backup files
            (setq backup-each-save-size-limit 5000000)
            ;; backup all the files
            (setq backup-each-save-filter-function 'identity))
  :init (add-hook 'after-save #'backup-each-save)
  )

(use-package base16-theme :ensure t
  :config (progn
            (setq base16-distinct-fringe-background nil)
            (if (display-graphic-p)
                (load-theme 'base16-solarized-dark t)))
  )

(use-package bm :ensure t
  :bind ((("M-^" . 'bm-toggle)
          ("C-M-n" . 'bm-next)
          ("C-M-p" . 'bm-previous)))
  :config (progn
            (global-set-key [?\C-\M-\ ] 'bm-toggle) ;not work
            (set-face-background bm-face "orange")
            (set-face-foreground bm-face "black"))
  )

(use-package calfw :ensure t :defer t)

(use-package coffee-mode :ensure t :defer t)

(use-package company :ensure t
  :config (progn
            (global-company-mode)
            (setq company-idle-delay 0.2)
            (setq company-minimum-prefix-length 2)
            ;; 候補の一番下でさらに下に行こうとすると一番上に戻る
            (setq company-selection-wrap-around t)
            (add-to-list 'company-backends 'company-dabbrev-code)
            ;; (add-to-list 'company-backends 'company-yasnippet)
            (add-to-list 'company-backends 'company-files)
            (define-key company-active-map (kbd "C-n") 'company-select-next)
            (define-key company-active-map (kbd "C-p") 'company-select-previous)
            (define-key company-search-map (kbd "C-n") 'company-select-next)
            (define-key company-search-map (kbd "C-p") 'company-select-previous)
            (define-key company-search-map (kbd "C-h") 'backward-delete-char)
            (define-key company-active-map (kbd "C-h") 'backward-delete-char)
            (push (apply-partially #'cl-remove-if
                                   (lambda (c)
                                     (or (string-match-p "[^\x00-\x7F]+" c)
                                         (string-match-p "[0-9]+" c)
                                         (if (equal major-mode "org")
                                             (>= (length c) 15))))) company-transformers)
            )
  )

(use-package company-statistics :ensure t
  :config (company-statistics-mode))

(use-package dockerfile-mode :ensure t :defer t
  :init (add-to-list 'auto-mode-alist '("Dockerfile\\'" . dockerfile-mode)))
;; (use-package elisp-format
;;   :url "http://www.emacswiki.org/emacs/download/elisp-format.el")

(use-package udev-mode :ensure t)

(use-package python
  :config
  (let ((ipython-executable "ipython2"))
    ;; Verify ipython version
    (if (executable-find ipython-executable)
        ;; ipython-version-string is a string like "5.5.0"
        (let* ((ipython-version-string (shell-command-to-string (concat ipython-executable " --version")))
               (ipython-major-version (string-to-number (car (split-string "5.5.0" "\\.")))))
          (if (>= ipython-major-version 5)
              (setq python-shell-interpreter ipython-executable
                    python-shell-interpreter-args "-i --simple-prompt --no-confirm-exit"
                    python-shell-enable-font-lock nil)
            (setq python-shell-interpreter ipython-executable
                  python-shell-interpreter-args "-i --no-confirm-exit"
                  python-shell-enable-font-lock nil)))
      ;; Use the default python if no ipython is installed
      (setq python-shell-interpreter ipython-executable
              python-shell-interpreter-args nil
              python-shell-enable-font-lock nil)
      )
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
          ))))
  :bind (:map python-mode-map
              ("\C-x\C-E" . 'python-shell-send-region-or-statement)
              ("\C-cE" . 'run-python-and-switch-to-shell)
              ("\C-ce" . 'run-python-and-switch-to-shell)
              ("\C-c <right>" . python-indent-shift-right)
              ("\C-c <left>" . python-indent-shift-left)
              )
  :hook ((python-mode . (lambda () (setq-local comment-inline-offset 2))))
  )

(use-package elpy :ensure t :if nil
  :config (progn
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
            ))

(use-package exec-path-from-shell :ensure t
  :config (progn
            (add-to-list 'exec-path-from-shell-variables "CMAKE_PREFIX_PATH")
            (exec-path-from-shell-initialize))
  )

(use-package expand-region :ensure t
  :config (progn
            (when (<= emacs-major-version 24)
              (defmacro save-mark-and-excursion
                  (&rest
                   body)
                `(save-excursion ,@body)))
            (global-set-key (kbd "C-^") 'er/expand-region)
            (global-set-key (kbd "C-M-^") 'er/contract-region)
            ;; Dummy functions to ignore deprecated functions.
            (defun org-outline-overlay-data (&rest args))
            (defun org-set-outline-overlay-data (&rest args)))
  )

;; It does not work with lsp mode
(use-package fill-column-indicator :ensure t :if (<= emacs-major-version 26)
  :hook ((prog-mode) . fci-mode)
  :config (progn
            (setq-default fci-rule-column 100)
            ;; Automatically hide fci ruler if window is too narrow
            ;; See http://bit.ly/2Yw3XiE
            (defvar i42/fci-mode-suppressed nil)
            (make-variable-buffer-local 'i42/fci-mode-suppressed)

            (defun fci-width-workaround (frame)
              (let ((fci-enabled (symbol-value 'fci-mode))
                    (fci-column (if fci-rule-column fci-rule-column fill-column))
                    (current-window-list (window-list frame 'no-minibuf)))
                (dolist (window current-window-list)
                  (with-selected-window window
                    (if i42/fci-mode-suppressed
                        (when (and (eq fci-enabled nil)
                                   (< fci-column
                                      (+ (window-width) (window-hscroll))))
                          (setq i42/fci-mode-suppressed nil)
                          (turn-on-fci-mode))
                      ;; i42/fci-mode-suppressed == nil
                      (when (and fci-enabled fci-column
                                 (>= fci-column
                                     (+ (window-width) (window-hscroll))))
                        (setq i42/fci-mode-suppressed t)
                        (turn-off-fci-mode)))))))
            (add-hook 'window-size-change-functions 'fci-width-workaround)
            )
  )
(when (>= emacs-major-version 27)
  (setq-default display-fill-column-indicator-column 100)
  (global-display-fill-column-indicator-mode))

(use-package flycheck :ensure t
  :requires (thingopt)
  :config (progn
            (setq flycheck-check-syntax-automatically '(mode-enabled save))
            (global-flycheck-mode t)
            ;; flycheck runs emacs with `-Q` option to lint emacs lisp codes. It means that
            ;; load-path is not taken into account in linting.
            ;; By assiging `flycheck-emacs-lisp-load-path` to 'inherit, flycheck runs emacs with
            ;; `load-path` inherited from the current emacs.
            (setq flycheck-emacs-lisp-load-path 'inherit)

            (defun flycheck-exclude-tramp ()
              "Do not run flycheck for the file over tramp mode.

See http://fukuyama.co/tramp-flycheck"
              (unless (or (and (fboundp 'tramp-tramp-file-p)
                               (tramp-tramp-file-p buffer-file-name))
                          (string-match "sudo:.*:" (buffer-file-name)))
                (flycheck-mode t)))

            ;; Do not use flycheck-pos-tip on cocoa emacs
            (if (not (eq system-type 'darwin))
                (progn
                  (when (require 'flycheck-pos-tip nil t)
                    (eval-after-load 'flycheck
                      '(setq
                        flycheck-display-errors-function #'flycheck-pos-tip-error-messages
                        flycheck-disabled-checkers '(c/c++-clang
                                                     c/c++-gcc
                                                     javascript-jshint))))))
            ;; disable clang and gcc linter
            (setq-default flycheck-disabled-checkers '(c/c++-clang
                                                       c/c++-gcc
                                                       javascript-jshint))

            ;; googlelint for C++
            (eval-after-load 'flycheck
              '(progn
                 (when (require 'flycheck-google-cpplint nil t)
                   (flycheck-add-next-checker 'c/c++-cppcheck '(warning . c/c++-googlelint)))))
            (setq flycheck-googlelint-filter "-runtime/references,-readability/braces"
                  flycheck-googlelint-verbose "3")

            ;; python
            ;; check flake8 version.
            ;; If flake8 is newer than 2.0, it does not have --stdin-display-name.
            (if (executable-find "flake8")
                (let* ((version-command-output (with-temp-buffer (shell-command "flake8 --version"
                                                                                (current-buffer))
                                                                 (buffer-substring-no-properties
                                                                  (point-min)
                                                                  (point-max))))
                       (version-string (car (split-string version-command-output " ")))
                       (major-version (read (car (split-string version-string "\\."))))
                       (error-filter-func #'(lambda (errors)
                                              (let ((errors (flycheck-sanitize-errors errors)))
                                                (seq-do #'flycheck-flake8-fix-error-level errors)
                                                errors))))
                  (if (>= major-version 2)
                      (progn (message "flake8 vresion is larger than 2.0 %s" major-version)
                             ;; Use eval ` to evaluate error-filter before quoting.
                             (eval `(flycheck-define-checker python-flake8
                                      "A Python syntax and style checker using Flake8.
This patch is depending on https://github.com/flycheck/flycheck/issues/1078.

Requires Flake8 3.0 or newer. See URL
`https://flake8.readthedocs.io/'."
                                      :command ("flake8"
                                                ;; "--format=default"
                                                ;; (config-file "--config" flycheck-flake8rc)
                                                (option "--max-complexity"
                                                        flycheck-flake8-maximum-complexity nil
                                                        flycheck-option-int)
                                                (option "--max-line-length"
                                                        flycheck-flake8-maximum-line-length nil
                                                        flycheck-option-int) "--ignore=E901" "-")
                                        ;psource)
                                      :standard-input t
                                      :error-filter ,error-filter-func
                                      :error-patterns
                                      ((warning line-start "stdin:" line ":" (optional
                                                                              column ":")
                                                " " (id (one-or-more (any alpha))
                                                        (one-or-more digit)) " " (message
                                                        (one-or-more
                                                         not-newline))
                                                line-end))
                                      :modes python-mode)))
                    (message "flake8 vresion is smaller than 2.0"))))
            )
  )

(when nil
(use-package flyspell :ensure t
  :config (progn
            ;; see http://blog.binchen.org/posts/what-s-the-best-spell-check-set-up-in-emacs.html
            ;; if (aspell installed) { use aspell}
            ;; else if (hunspell installed) { use hunspell }
            ;; whatever spell checker I use, I always use English dictionary
            ;; I prefer use aspell because:
            ;; 1. aspell is older
            ;; 2. looks Kevin Atkinson still get some road map for aspell:
            ;; @see http://lists.gnu.org/archive/html/aspell-announce/2011-09/msg00000.html
            (defun flyspell-detect-ispell-args (&optional run-together)
              "If RUN-TOGETHER is true, spell check the CamelCase words."
              (let (args)
                (cond
                 ((string-match  "aspell$" ispell-program-name)
                  ;; Force the English dictionary for aspell
                  ;; Support Camel Case spelling check (tested with aspell 0.6)
                  (setq args (list "--sug-mode=ultra" "--lang=en_US"))
                  (if run-together
                      (setq args (append args
                                         '("--run-together" "--run-together-limit=5" "--run-together-min=2")))))
                 ((string-match "hunspell$" ispell-program-name)
                  ;; Force the English dictionary for hunspell
                  (setq args "-d en_US")))
                args))

            (cond
             ((executable-find "aspell")
              ;; you may also need `ispell-extra-args'
              (setq ispell-program-name "aspell"))
             ((executable-find "hunspell")
              (setq ispell-program-name "hunspell")

              ;; Please note that `ispell-local-dictionary` itself will be passed to hunspell cli with "-d"
              ;; it's also used as the key to lookup ispell-local-dictionary-alist
              ;; if we use different dictionary
              (setq ispell-local-dictionary "en_US")
              (setq ispell-local-dictionary-alist
                    '(("en_US" "[[:alpha:]]" "[^[:alpha:]]" "[']"
                       nil ("-d" "en_US") nil utf-8))))
             (t (setq ispell-program-name nil)))

            ;; ispell-cmd-args is useless, it's the list of *extra* arguments we will append to the ispell process when "ispell-word" is called.
            ;; ispell-extra-args is the command arguments which will *always* be used when start ispell process
            ;; Please note when you use hunspell, ispell-extra-args will NOT be used.
            ;; Hack ispell-local-dictionary-alist instead.
            (setq-default ispell-extra-args (flyspell-detect-ispell-args t))
            ;; (setq ispell-cmd-args (flyspell-detect-ispell-args))
            (defadvice ispell-word (around my-ispell-word activate)
              (let ((old-ispell-extra-args ispell-extra-args))
                (ispell-kill-ispell t)
                (setq ispell-extra-args (flyspell-detect-ispell-args))
                ad-do-it
                (setq ispell-extra-args old-ispell-extra-args)
                (ispell-kill-ispell t)
                ))

            (defadvice flyspell-auto-correct-word (around my-flyspell-auto-correct-word activate)
              (let ((old-ispell-extra-args ispell-extra-args))
                (ispell-kill-ispell t)
                ;; use emacs original arguments
                (setq ispell-extra-args (flyspell-detect-ispell-args))
                ad-do-it
                ;; restore our own ispell arguments
                (setq ispell-extra-args old-ispell-extra-args)
                (ispell-kill-ispell t)
                ))

            (defun text-mode-hook-setup ()
              ;; Turn off RUN-TOGETHER option when spell check text-mode
              (setq-local ispell-extra-args (flyspell-detect-ispell-args)))
            (add-hook 'text-mode-hook 'text-mode-hook-setup)

            (defun add-word-to-ispell-dictionary ()
              "Add word to dictionary file for ispell."
              (interactive)
              (let ((user-dictionary-file (expand-file-name "~/.aspell.en.pws")))
                (let ((buf (find-file-noselect user-dictionary-file)))
                  (if (not (file-exists-p user-dictionary-file))
                      (with-current-buffer buf
                        (insert "personal_ws-1.1 en 0\n")
                        (save-buffer)))
                  (let ((theword (thing-at-point 'word)))
                    (if theword
                        (with-current-buffer buf
                          (goto-char (point-max))
                          (insert (format "%s\n" theword))
                          (save-buffer))))
                  )))

            (global-set-key "\M-." 'add-word-to-ispell-dictionary)
            )
  )
)

;; (use-package flycheck-google-cpplint :ensure t)
;; (if (not (eq system-type 'darwin))
;;     (use-package flycheck-pos-tip))
;; (use-package Simplify/flycheck-typescript-tslint)

;; Need to setup:
;; git config --global github.user <username>
;; git config --global github.oauth-token <token>
(use-package gist :ensure t
  :bind
  (("C-c C-g" . gist-region-or-buffer))
  )


(use-package git-gutter+ :ensure t
  :if (not (display-graphic-p))
  :config
  (progn (global-git-gutter+-mode)
         (defun git-gutter+-remote-default-directory (dir file)
           (let* ((vec (tramp-dissect-file-name file))
                  (method (tramp-file-name-method vec))
                  (user (tramp-file-name-user vec))
                  (domain (tramp-file-name-domain vec))
                  (host (tramp-file-name-host vec))
                  (port (tramp-file-name-port vec)))
             (tramp-make-tramp-file-name method user domain host port dir)))

         (defun git-gutter+-remote-file-path (dir file)
           (let ((file (tramp-file-name-localname (tramp-dissect-file-name file))))
             (replace-regexp-in-string (concat "\\`" dir) "" file)))
         )
  )

(use-package git-gutter-fringe+ :ensure t
  :if (display-graphic-p)
  :config (progn (global-git-gutter+-mode)
                 (defun git-gutter+-remote-default-directory (dir file)
                   (let* ((vec (tramp-dissect-file-name file))
                          (method (tramp-file-name-method vec))
                          (user (tramp-file-name-user vec))
                          (domain (tramp-file-name-domain vec))
                          (host (tramp-file-name-host vec))
                          (port (tramp-file-name-port vec)))
                     (tramp-make-tramp-file-name method user domain host port dir)))

                 (defun git-gutter+-remote-file-path (dir file)
                   (let ((file (tramp-file-name-localname (tramp-dissect-file-name file))))
                     (replace-regexp-in-string (concat "\\`" dir) "" file))))
  )

(use-package go-mode :ensure t :defer t)

(use-package google-c-style :ensure t
  :config (progn
            (setf (cdr (assoc 'c-basic-offset google-c-style)) 2)
            )
  :hook ((c-mode-common . google-set-c-style)
         (c-mode-common . google-make-newline-indent))
  )

(use-package google-this :ensure t
  :config (progn (global-set-key (kbd "C-x g") 'google-this-mode-submap)
                 (global-set-key (kbd "C-c g") 'google-this)))

(use-package graphviz-dot-mode :ensure t
  :config (progn (defun graphviz-compile-preview ()
                   "Compile and preview graphviz dot file."
                   (interactive)
                   (compile compile-command)
                   (sleep-for 1)
                   (graphviz-dot-preview))
                 ;;(global-set-key [f5] 'graphviz-compile-preview)
                 )
  )

(use-package migemo :ensure t
  :config
  (progn
    (setq migemo-command "cmigemo")
    (setq migemo-options '("-q" "--emacs"))
    (let ((migemo-dictionary-candiates
           '("/usr/local/share/migemo/utf-8/migemo-dict"
             "/usr/share/cmigemo/utf-8/migemo-dict")))
      (dolist (candidate migemo-dictionary-candiates)
        (if (file-exists-p candidate)
            (setq migemo-dictionary candidate))))
    (setq migemo-user-dictionary nil)
    (setq migemo-regex-dictionary nil)
    ;; charset encoding
    (setq migemo-coding-system 'utf-8-unix)
    (migemo-init)
    ))

(use-package counsel :ensure t
  :config (progn
            (ivy-mode t)
            (counsel-mode t)
            (setq ivy-use-virtual-buffers t)
            (setq enable-recursive-minibuffers t)
            ;; (setq ivy-height 30)
            (setq ivy-extra-directories nil)
            ;; (setq ivy-re-builders-alist '((t . ivy--regex-plus)))

            ;; Remove the first '^' in query form.
            ;; https://github.com/abo-abo/swiper/issues/1455
            (setq ivy-initial-inputs-alist nil)
            (defun catkin-packages-list ()
              "List all the catkin packages in catkin workspace"
              (let ((cmake-prefix-path (getenv "CMAKE_PREFIX_PATH"))
                    (catkin-root nil))
                (when cmake-prefix-path
                  (setq catkin-root
                        (format "%s/../src" (car (split-string cmake-prefix-path ":")))))
                (let ((string-output
                       (shell-command-to-string
                      (format "find %s -name package.xml -exec dirname {} \\\;"
                              catkin-root))))
                  (let ((dirs (split-string string-output "\n")))
                    dirs))))

            (defun my-ivy-switch-buffer-action (buffer)
              "Customized ivy--switch-buffer-action."
              (if (zerop (length buffer))
                  (switch-to-buffer
                   ivy-text nil 'force-same-window)

                (let ((virtual (assoc buffer ivy--virtual-buffers))
                      (view (assoc buffer ivy-views)))
                  (cond ((and virtual (not (get-buffer buffer)))
                         (find-file (cdr virtual)))
                        (view
                         (delete-other-windows)
                         (let (
                               ;; silence "Directory has changed on disk"
                               (inhibit-message t))
                           (ivy-set-view-recur (cadr view))))
                        ;; This is the modification to the original ivy--switch-buffer-action.
                        ;; If `buffer' is a file and the buffer of the file have not opened yet,
                        ;; open the file.
                        ;; This modification is designed to open catkin pacakge.
                        ((and (not (get-buffer buffer))
                              (file-exists-p (expand-file-name buffer)))
                         (find-file buffer))
                        (t
                         (switch-to-buffer
                          buffer nil 'force-same-window))))))

            (defun my-counsel-git-files ()
              (let* ((git-directory (ignore-errors (counsel-locate-git-root)))
                     (counsel-git-cands (if git-directory (counsel-git-cands git-directory))))
                (mapcar #'(lambda (cand) (concat git-directory cand))
                        counsel-git-cands)))

            ;; C-x b like helm-mini
            (defun my-ivy-switch-buffer ()
              "Customized version of ivy-switch-buffer."
              (interactive)
              (ivy-read ">> " #'internal-complete-buffer
                        :keymap ivy-switch-buffer-map
                        :preselect (buffer-name (other-buffer (current-buffer)))
                        :action #'my-ivy-switch-buffer-action ;This is the modification.
                        :matcher #'ivy--switch-buffer-matcher
                        :caller 'my-ivy-switch-buffer)
              )
            ;; Customize sources of my-ivy-switch-buffer
            (ivy-set-sources
             'my-ivy-switch-buffer
             '((original-source)
               (ivy-source-views)
               (my-counsel-git-files)
               (catkin-packages-list)
               ;; (identity projectile-known-projects)
               ))
            (global-set-key (kbd "C-x b") 'my-ivy-switch-buffer)
            (global-set-key "\C-s" 'swiper-isearch)
            (global-set-key "\C-r" 'swiper-isearch-backward)
            (global-set-key (kbd "C-c C-r") 'ivy-resume)
            (global-set-key (kbd "<f6>") 'ivy-resume)
            (global-set-key (kbd "<f2> u") 'counsel-unicode-char)
            (global-set-key (kbd "C-c g") 'counsel-git)
            (global-set-key (kbd "C-c j") 'counsel-git-grep)
            (global-set-key (kbd "C-c k") 'counsel-ag)
            (global-set-key (kbd "C-x l") 'counsel-locate)
            ;; Do not run dired when hitting enter in find-file
            (define-key ivy-minibuffer-map (kbd "RET") #'ivy-alt-done)
            (define-key ivy-minibuffer-map (kbd "C-j") #'ivy-immediate-done)
            (define-key ivy-minibuffer-map (kbd "C-RET") #'ivy-immediate-done)
            (define-key ivy-minibuffer-map "\C-h" 'ivy-backward-delete-char)
            )
  )

(use-package ivy-prescient :ensure t)

(use-package avy :ensure t)
(add-to-list 'load-path "~/.emacs.d/avy-migemo")
(use-package avy-migemo
  ;; :ensure t
  :config
  (avy-migemo-mode 1)
  (setq avy-timeout-seconds nil)
  (require 'avy-migemo-e.g.swiper)
  (global-set-key (kbd "C-M-;") 'avy-migemo-goto-char-timer)
  ;;  (global-set-key (kbd "M-g m m") 'avy-migemo-mode)
  )

(use-package hyde :ensure t
  :config (progn
            (setq-default jekyll-root (expand-file-name "~/gprog/garaemon.github.io"))
            (setq-default hyde-home (expand-file-name "~/gprog/garaemon.github.io"))
            (defun ghyde ()
              "Run hyde mode on HYDE-HOME."
              (interactive)
              (hyde hyde-home))

            (defun jekyll-new-post (title)
              "Create a new post for jekyll with TITLE and date."
              (interactive "MEnter post title: ")
              (let* ((YYYY-MM-DD (format-time-string "%Y-%m-%d" nil t))
                     (file-name (format "%s/_posts/%s-%s.md" jekyll-root YYYY-MM-DD title)))
                ;; template header
                (save-excursion
                  (find-file file-name)
                  (insert "---\n")
                  (insert "layout: post\n")
                  (insert (format "title: %s\n" title))
                  (insert (format "date: %s\n" (format-time-string "%Y-%m-%dT%H:%M:%SJST")))
                  (insert "descriptions:\n")
                  (insert "categories:\n")
                  (insert "- blog\n")
                  (insert "---\n")
                  (insert "\n"))
                (find-file file-name)))
            ))

(use-package hydra :ensure t
  :config (progn
            (defhydra hydra-zoom (global-map "<f2>")
              "zoom"
              ("g" text-scale-increase "in")
              ("l" text-scale-decrease "out"))
            )
  )

(use-package imenus :ensure t)

(use-package js2-mode :ensure t
  :config (progn
            (defun my-js2-indent-function ()
              "Hook function for indent in js2 mode."
              (interactive)
              (save-restriction
                (widen)
                (let* ((inhibit-point-motion-hooks t)
                       (parse-status (save-excursion (syntax-ppss (point-at-bol))))
                       (offset (- (current-column)
                                  (current-indentation)))
                       (indentation (js--proper-indentation parse-status)) node)
                  (save-excursion
                    ;; I like to indent case and labels to half of the tab width
                    (back-to-indentation)
                    (if (looking-at "case\\s-")
                        (setq indentation (+ indentation (/ js-indent-level 2))))
                    ;; consecutive declarations in a var statement are nice if
                    ;; properly aligned, i.e:
                    ;; var foo = "bar",
                    ;;     bar = "foo";
                    (setq node (js2-node-at-point))
                    (when (and node
                               (= js2-NAME (js2-node-type node))
                               (= js2-VAR (js2-node-type (js2-node-parent node))))
                      (setq indentation (+ 4 indentation))))
                  (indent-line-to indentation)
                  (when (> offset 0)
                    (forward-char offset)))))

            (setq auto-mode-alist (cons (cons "\\.js$" 'js2-mode) auto-mode-alist))
            (setq auto-mode-alist (cons (cons "\\.jsx$" 'js2-jsx-mode) auto-mode-alist))
            (add-to-list 'auto-mode-alist '("\\.json$" . js2-mode))
            (setq js-indent-level 2)
            ;; Disable some js2 features for eslint integration by flycheck
            (setq js2-include-browser-externs nil)
            (setq js2-mode-show-parse-errors nil)
            (setq js2-mode-show-strict-warnings nil)
            (setq js2-highlight-external-variables nil)
            (setq js2-include-jslint-globals nil)
            (c-toggle-auto-state 0)
            (c-toggle-hungry-state 1)
            (set (make-local-variable 'indent-line-function) 'my-js2-indent-function)
            ;;  (define-key js2-mode-map [(meta control |)] 'cperl-lineup)
            (define-key js2-mode-map [(meta control \;)]
              '(lambda()
                 (interactive)
                 (insert "/* -----[ ")
                 (save-excursion (insert " ]----- */"))))
            (define-key js2-mode-map [(return)] 'newline-and-indent)
            (define-key js2-mode-map [(backspace)] 'c-electric-backspace)
            (define-key js2-mode-map [(control d)] 'c-electric-delete-forward)
            )
  )

(use-package json-mode :ensure t :defer t)

;; (use-package judge-indent :ensure t)

(use-package less-css-mode :ensure t :defer t)

;; require typescript before configuring lsp-mode
(require 'typescript)

(use-package lua-mode :ensure t :defer t)

(use-package lsp-mode :ensure t
  :hook (
         ;; pip3 install 'python-language-server[all]'
         (python-mode . lsp)
         ;; npm i -g typescript-language-server; npm i -g typescript
         (typescript-mode . lsp)
         ;; npm i -g yaml-language-server
         (yaml-mode . lsp)
         (js-mode . lsp)
         (emacs-lisp-mode . lsp)
         (lsp-mode . lsp-ui-mode)
         (lsp-managed-mode .(lambda () (setq-local company-backends '(company-capf))))
         )
  :bind (:map lsp-signature-mode-map
         ;; These settings are not applied to lsp-signature-mode-map.
         ("\M-n" . 'scroll-down-in-place)
         ("\M-p" . 'scroll-up-in-place)
         )
  :config (progn
            (add-to-list 'auto-mode-alist '("\\.ts[x]?\\'" . typescript-mode))
            (add-to-list 'lsp-file-watch-ignored "[/\\\\]\\.cquery_cached_index$")
            (add-to-list 'lsp-file-watch-ignored "[/\\\\]\\.ccls-cache$")
            (setq lsp-eldoc-enable-hover nil)
            (setq lsp-enable-completion-at-point t)
            (setq lsp-enable-folding nil)
            (setq lsp-enable-imenu t)
            (setq lsp-enable-on-type-formatting t)
            (setq lsp-enable-snippet t)
            (setq lsp-enable-symbol-highlighting t)
            (setq lsp-enable-xref t)
            (setq lsp-prefer-capf t)
            (setq lsp-print-io nil)
            (setq lsp-print-performance t)
            (setq-default lsp-eldoc-enable-hover nil)
            (setq lsp-eldoc-render-all t)
            (setq lsp-markup-display-all t)
            (setq lsp-pyls-plugins-jedi-hover-enabled nil)
            (setq-default lsp-signature-auto-activate nil)
            )
  )
(defun lsp-describe-thing-at-point () (interactive) nil)

(use-package lsp-ui :ensure t
  :init (add-hook 'lsp-mode-hook #'lsp-ui-mode)
  :config (progn
            ;; Reguster lsp-ui-doc--make-request to 'post-command-hook is too heavy.
            ;; Add small latency before calling lsp-ui-doc--make-request.
            (defun lsp-ui-doc-make-request-lazy ()
              (run-with-idle-timer 0.2 nil #'lsp-ui-doc--make-request))
            (add-hook 'lsp-ui-doc-mode-hook
                      '(lambda ()
                         (remove-hook 'post-command-hook 'lsp-ui-doc--make-request t)
                         (add-hook 'post-command-hook 'lsp-ui-doc-make-request-lazy
                                   nil t)
                         ))
            (setq lsp-ui-doc-enable t)
            (setq lsp-ui-doc-header t)
            (setq lsp-ui-doc-include-signature t)
            (setq lsp-ui-doc-max-width 80)
            (setq lsp-ui-doc-max-height 30)
            (setq lsp-ui-peek-enable t)
            )
  )

(use-package lsp-treemacs :ensure t
  :config (global-set-key "\C-c^" 'lsp-treemacs-errors-list))

(use-package cquery :ensure t
  :if nil
  :config (setq cquery-executable "~/.local/bin/cquery")
  :commands lsp
  )

(use-package ccls :ensure t
  :config
  :hook ((c-mode c++-mode objc-mode) .
         (lambda () (require 'ccls) (lsp))))


(use-package magit :ensure t
  :config (progn
            (global-set-key "\C-cl" 'magit-status)
            (global-set-key "\C-cL" 'magit-status)
            ;; It expects core.editor=emacsclient
            (defun github-pull-request ()
              (interactive)
              (shell-command "git config core.editor=emacsclient")
              (shell-command "hub pull-request &"))
            )
  )

(use-package forge :after magit :ensure t)

(use-package sx :ensure t)

(use-package markdown-mode :ensure t
  :config (progn
            (setq auto-mode-alist (cons '("\\.md" . markdown-mode) auto-mode-alist))
            (defvar markdown-mode-map)
            (define-key markdown-mode-map (kbd "M-p") nil)
            (define-key markdown-mode-map (kbd "M-n") nil)
            (defun open-with-shiba ()
              "Open a current markdown file with shiba."
              (interactive)
              (start-process "shiba" "*shiba*" "shiba" "--detach" buffer-file-name))
            (define-key markdown-mode-map (kbd "C-c C-c") 'open-with-shiba)
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
            ))

(add-to-list 'load-path "~/.emacs.d/markdown-dnd-images")
(use-package markdown-dnd-images
  :config
  (setq dnd-save-directory "images")
  (setq dnd-view-inline t)
  (setq dnd-save-buffer-name nil)
  (setq dnd-capture-source t))

(use-package migemo :ensure t
  :if (executable-find "cmigemo")
  :config (progn
            (setq
             migemo-command "cmigemo"
             migemo-options '("-q" "--emacs")
             migemo-dictionary "/usr/share/cmigemo/utf-8/migemo-dict"
             migemo-user-dictionary nil
             migemo-regex-dictionary nil
             migemo-coding-system 'utf-8-unix)
            (migemo-init)
            )
  )

(use-package minimap :ensure t)

(use-package modern-cpp-font-lock :ensure t
  :hook (c++-mode . modern-c++-font-lock-mode))

(use-package omnisharp :ensure t
  :init (add-to-list 'auto-mode-alist '("\\.cs$" . csharp-mode))
  )

(use-package multiple-cursors :ensure t
  :config (progn
            (global-set-key (kbd "<C-M-return>") 'mc/edit-lines)
            (global-set-key (kbd "C-M-j") 'mc/edit-lines)

            (global-set-key (kbd "<C-M-down>") 'mc/mark-next-like-this)
            (global-set-key (kbd "<C-M-up>") 'mc/mark-previous-like-this)
            )
  )

(use-package switch-buffer-functions :ensure t)

(use-package neotree :ensure t
  :requires (all-the-icons)
  :config (progn
            (global-set-key [f8] 'neotree-toggle)
            ;; all-the-icons is required
            (setq neo-theme (if (display-graphic-p) 'icons 'arrow))
            (setq neo-smart-open t)
            (add-hook 'switch-buffer-functions
                      (lambda (prev current)
                        (let ((neotree-buffer (neo-global--get-buffer)))
                          (if (and
                               ;; Ignore if new buffer is neotree
                               (not (eq current neotree-buffer))
                               ;; Ignore if the buffer is not assosiated with a file
                               buffer-file-name
                               ;; Ignore if neotree is not active
                               (neo-global--window-exists-p))
                              (progn
                                (neo-buffer--change-root default-directory)
                                (switch-to-buffer current)
                                )
                            )
                          )
                        )))
  )

(use-package nlinum :ensure t
  :if (not (functionp 'global-display-line-numbers-mode))
  :config (progn
            (global-nlinum-mode)
            ;; these linum-delay and linum-schedule are required even if nlinum-mode is used?
            (setq linum-delay t)
            (defadvice linum-schedule (around my-linum-schedule () activate)
              "Set scheduler of linux-mode."
              (run-with-idle-timer 0.2 nil #'linum-update-current))

            ;; Use darker color when `emacsclient -nw` is used.
            (defun linum-color-on-after-init (frame)
              "Hook function executed after FRAME is generated."
              (unless (display-graphic-p frame)
                (set-face-background
                 'linum
                 (plist-get base16-solarized-dark-colors :base01))))

            (add-hook 'after-make-frame-functions
                      (lambda (frame)
                        (linum-color-on-after-init frame)))
            )
  )

(use-package org :ensure t
  :config (progn
            (setq org-directory (expand-file-name "~/GoogleDrive/org/"))
            ;; The special characters for org-capture-templates are described below:
            ;; https://orgmode.org/manual/Template-expansion.html#Template-expansion
            ;;
            (setq org-capture-templates
                  '(("m" "Memo" entry (file+headline
                                       (lambda () (concat org-directory "INBOX.org"))
                                       "Memos")
                     "*** MEMO [%T] %? \n    CAPTURED_AT: %a\n    %i"
                     :unarrowed t
                     :prepend t
                     ))
                    )
            (global-set-key (kbd "C-c c") 'org-capture)
            ;; Is it ok? minor-modes such as magit takes over this key bind?
            (global-set-key (kbd "C-c C-c") 'org-capture)
            (global-set-key (kbd "C-c a") 'org-agenda)
            ;; Write content to org-capture from MINI Buffer
            ;; http://ganmacs.hatenablog.com/entry/2016/04/01/164245
            (defun org/note-right-now (content)
              (interactive "sContent for org-capture quick memo: ")
              (org-capture nil "m")
              (insert content)
              (org-capture-finalize))
            (global-set-key (kbd "C-M-c") 'org/note-right-now)
            )
  )

(use-package org-download :ensure t
  :config (setq-default org-download-image-dir "~/GoogleDrive/org/images"))

(use-package outshine :ensure t
  :hook (outline-minor-mode . outshine-hook-function))

(use-package php-mode :ensure t)

(use-package protobuf-mode :ensure t
  :init (add-to-list 'auto-mode-alist '("\\.proto$" . protobuf-mode))
  :config (progn
            (add-hook 'protobuf-mode-hook
                      (lambda ()
                        (c-add-style "my-style" '((c-basic-offset . 4)
                                                  (indent-tabs-mode . nil))
                                     t)))
            )
  )

(use-package puppet-mode :ensure t :defer t
  :init (add-to-list 'auto-mode-alist '("\\.pp$" . puppet-mode)))

(use-package rainbow-delimiters :ensure t
  :config (setq rainbow-delimiters-depth-1-face
                '((t
                   (:foreground "#7f8c8d"))))
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package recentf-ext :ensure t)

(use-package rust-mode :ensure t)

(use-package scss-mode :ensure t
  :init (add-to-list 'auto-mode-alist '("\\.scss$" . scss-mode)))

(use-package slack :ensure t
  :if (file-exists-p (expand-file-name "~/.slack.el"))
  :config (progn
            (setq slack-private-file (expand-file-name "~/.slack.el"))
            (setq slack-buffer-emojify t)
            (setq slack-prefer-current-team t)
            ;; use Shift+Enter and Ctrl+Enter as newline
            (define-key slack-mode-map '[S-return] 'newline)
            (define-key slack-mode-map '[C-return] 'newline)
            (load slack-private-file)
            )
  )

(use-package smart-cursor-color :ensure t
  :config (smart-cursor-color-mode +1))

(use-package smart-mode-line :ensure t
  :if nil
  :config (progn
            (setq sml/no-confirm-load-theme t)
            (setq sml/theme 'dark)
            (setq sml/shorten-directory -1)
            (sml/setup)
            (remove-hook 'post-command-hook 'sml/generate-position-help)
            (add-hook 'post-command-hook
                      (lambda ()
                        (run-with-idle-timer 0.2 nil #'sml/generate-position-help)))
            )
  )

(use-package smartrep :ensure t
  :config (progn
            (declare-function smartrep-define-key "smartrep")
            (global-unset-key "\C-q")
            (defun define-smartrep-keys ()
              "Setup smartrep keys."
              (smartrep-define-key global-map "C-q"
                '(("C-t"      . 'mc/mark-next-like-this)
                  ("n"        . 'mc/mark-next-like-this)
                  ("p"        . 'mc/mark-previous-like-this)
                  ("m"        . 'mc/mark-more-like-this-extended)
                  ("u"        . 'mc/unmark-next-like-this)
                  ("U"        . 'mc/unmark-previous-like-this)
                  ("s"        . 'mc/skip-to-next-like-this)
                  ("S"        . 'mc/skip-to-previous-like-this)
                  ("*"        . 'mc/mark-all-like-this)
                  ("d"        . 'mc/mark-all-like-this-dwim)
                  ("i"        . 'mc/insert-numbers)
                  ("o"        . 'mc/sort-regions)
                  ("O"        . 'mc/reverse-regions))))
            (define-smartrep-keys)
            )
  )

(use-package sr-speedbar :ensure t
  :config (setq sr-speedbar-right-side nil))

(use-package string-inflection :ensure t
  :config (global-set-key (kbd "C-c i") 'string-inflection-cycle))

(use-package symon :ensure t
  :if (eq system-type 'gnu/linux)
  :config (progn
            (setq symon-sparkline-type 'symon-sparkline-type-gridded)
            (setq symon-delay 100)
            (symon-mode)
            )
  )

(use-package thingopt :ensure t)

(use-package tide :ensure t :requires (typescript)
  :config (progn
            (setq typescript-indent-level 2)
            (defun my-typescript-hook ()
              "My hook function for typescript-mode."
              (tide-setup)
              (flycheck-mode t)
              ;; (setup-tide-mode)
              (eldoc-mode t)
              (setq flycheck-check-syntax-automatically
                    (mode-enabled save))
              (company-mode-on)
              (tide-hl-identifier-mode +1)
              (setq typescript-indent-level 2)
              (define-smartrep-keys)
              )
            (add-hook 'typescript-mode-hook
                      (lambda ()
                        (my-typescript-hook)
                        ))
            )
  )

(use-package total-lines :ensure t
  :config (progn
            (global-total-lines-mode t)
            (defun my-set-line-numbers ()
              "Init hook to setup total lines."
              (setq-default mode-line-front-space
                            (append mode-line-front-space
                                    '((:eval (format " (%d)" (- total-lines 1)))))))
            (add-hook 'after-init-hook 'my-set-line-numbers)
            )
  )

(use-package tramp
  :config (progn
            (setq tramp-debug-buffer t
                  tramp-verbose 10
                  tramp-default-method "ssh")
            (setq tramp-shell-prompt-pattern
                  "\\(?:^\\|\r\\)[^]#$%>\n]*#?[]#$%>].* *\\(^[\\[[0-9;]*[a-zA-Z] *\\)*")
            (defun tramp-cleanup-all ()
              "Cleanup all tramp connection and buffers"
              (interactive)
              (tramp-cleanup-all-buffers)
              (call-interactively 'tramp-cleanup-all-connections))
            )
  )

(use-package trr :ensure t)

(use-package undo-tree :ensure t
  :config (progn
            (global-undo-tree-mode)
            (define-key undo-tree-visualizer-mode-map "\C-m" 'undo-tree-visualizer-quit)
            )
  )

(use-package undohist :ensure t
  :config (progn
            (undohist-initialize)
            (setq undohist-ignored-files '("/tmp/"))
            )
  )

(use-package uniquify
  :config (setq uniquify-buffer-name-style 'post-forward-angle-brackets))

(use-package volatile-highlights :ensure t
  :config (volatile-highlights-mode))

(use-package web-mode :ensure t :if t
  :requires (flycheck)
  :init (progn (add-to-list 'auto-mode-alist '("\\.tsx\\'" . web-mode))
               (add-to-list 'auto-mode-alist '("\\.html?\\'" . web-mode)))
  ;; Cannot defind this keybind in :bind section of lsp-mode because web-mode-map variable is not
  ;; defined in the scope.
  :bind (("C-c f" . 'prettier-js))
  :config (progn
            (defun my-web-mode-hook ()
              "Hooks for Web mode."
              (setq web-mode-enable-auto-indentation nil)
              (setq web-mode-markup-indent-offset 2)
              (setq web-mode-css-indent-offset 2)
              (setq web-mode-code-indent-offset 2)
              (setq web-mode-script-padding 2)
              (setq web-mode-style-padding 2)
              (setq tab-width 2)
              )
            )
  :hook (web-mode . (lambda ()
                      (my-web-mode-hook)
                      ;; (when (string-equal "tsx" (file-name-extension buffer-file-name))
                      ;;   (setup-tide-mode))
                      ))
  )

(use-package which-key :ensure t
  :config (progn
            (which-key-mode)
            (which-key-setup-side-window-bottom)
            )
  )

(use-package win-switch :ensure t
  :if (not (getenv "TRAVIS"))
  :config (progn
            (setq win-switch-feedback-background-color "yellow"
                  win-switch-feedback-foreground-color "black"
                  win-switch-idle-time 1.5
                  win-switch-window-threshold 1)

            ;; switching window
            (win-switch-set-keys '("k") 'up)
            (win-switch-set-keys '("j") 'down)
            (win-switch-set-keys '("h") 'left)
            (win-switch-set-keys '("l") 'right)
            (win-switch-set-keys '("o") 'next-window)
            (win-switch-set-keys '("p") 'previous-window)
            ;; resizing
            (win-switch-set-keys '("K") 'enlarge-vertically)
            (win-switch-set-keys '("J") 'shrink-vertically)
            (win-switch-set-keys '("H") 'shrink-horizontally)
            (win-switch-set-keys '("L") 'enlarge-horizontally)
            ;; split
            (win-switch-set-keys '("3") 'split-horizontally)
            (win-switch-set-keys '("2") 'split-vertically)
            (win-switch-set-keys '("0") 'delete-window)
            (win-switch-set-keys '(" ") 'other-frame)
            (win-switch-set-keys '("u" [return]) 'exit)
            (win-switch-set-keys '("\M-\C-g") 'emergency-exit)
            ;; replace C-x o
            (global-set-key (kbd "C-x o") 'win-switch-dispatch)
            ;;(global-set-key (kbd "C-x p")
            ;; (win-switch-dispatch-with 'win-switch-previous-window))
            )
  )

(use-package yaml-mode :ensure t
  :init (add-to-list 'auto-mode-alist '("\\.\\(yml\\|yaml\\|rosinstall\\)$" . yaml-mode)))

(use-package yasnippet :ensure t
  :config (progn
            (setq yas-snippet-dirs '("~/.emacs.d/snippets"
                                     "~/.emacs.d/yasnippet-snippets/snippets"))
            (setq yas-trigger-key "Enter")
            (yas-global-mode 1)
            ;;(custom-set-variables '(yas-trigger-key "TAB"))

            ;; insert new snippet
            (define-key yas-minor-mode-map (kbd "C-x i i") 'yas-insert-snippet)
            ;; create a new snippet
            (define-key yas-minor-mode-map (kbd "C-x i n") 'yas-new-snippet)
            ;; edit a snippet
            (define-key yas-minor-mode-map (kbd "C-x i v") 'yas-visit-snippet-file)
            )
  :hook ((prog-mode . yas-minor-mode)
         (cmake-mode . yas-minor-mode))
  )

(use-package yatemplate :ensure t
  :config (progn
            (setq auto-insert-alist '(()))
            (setq yatemplate-dir (expand-file-name "~/.emacs.d/templates"))
            (yatemplate-fill-alist)
            (auto-insert-mode 1)
            (defun after-save-hook--yatemplate ()
              (when (string-match "emacs.*/templates/" buffer-file-name)
                (yatemplate-fill-alist)))
            (add-hook 'after-save-hook 'after-save-hook--yatemplate)
            ))


(use-package esup :ensure t)

(use-package whitespace
  :config (progn
            (global-whitespace-mode 1)
            (set-face-foreground 'whitespace-space "LightSlateGray")
            (set-face-background 'whitespace-space "DarkSlateGray")
            (set-face-foreground 'whitespace-tab "LightSlateGray")
            (set-face-background 'whitespace-tab "DarkSlateGray")
            )
  )

(use-package ucs-normalize)

(use-package cmake-mode
  :init  (progn
           (setq auto-mode-alist (cons '("CMakeLists.txt" . cmake-mode) auto-mode-alist))
           (setq auto-mode-alist (cons '("\\.cmake$" . cmake-mode) auto-mode-alist))
           (defun get-cmake-project-name ()
             (interactive)              ;for debug
             (let* ((full-current-file-name (buffer-file-name))
                    (file-name (file-name-nondirectory full-current-file-name)))
               (file-name-nondirectory
                ;; Remove the tailing '/'
                (substring (file-name-directory full-current-file-name) 0 -1))
               ))
           )
  )

(use-package wdired
  :config (progn
            (setq wdired-allow-to-change-permissions t)
            (define-key dired-mode-map "e" 'wdired-change-to-wdired-mode)
            )
  )

(use-package hl-line
  :if nil
  :config (progn
            (defun global-hl-line-timer-function ()
              "Callback function for hl-line timer."
              (global-hl-line-unhighlight-all)
              (let ((global-hl-line-mode t))
                (global-hl-line-highlight)))
            (setq global-hl-line-timer
                  (run-with-idle-timer 0.03 t 'global-hl-line-timer-function))
            ;; http://bit.ly/2FqHdIK
            ;; is it required?
            (add-hook 'after-make-frame-functions
                      (lambda (frame)
                        (message "after-make-frame-functions")
                        (hl-line-color-on-after-init frame)))
            )
  )

(use-package cmuscheme
  :init (progn
          (autoload 'scheme-mode "cmuscheme" "Major mode for Scheme." t)
          (autoload 'run-scheme "cmuscheme" "Run an inferior Scheme process." t))
  :config (progn
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
  )

(use-package euslisp-mode
  :init (setq auto-mode-alist (cons (cons "\\.l$" 'euslisp-mode) auto-mode-alist))
  :config (progn
            (defvar inferior-euslisp-program)
            (defun lisp-other-window ()
              "Run Lisp on other window."
              (interactive)
              (if (not (string= (buffer-name) "*inferior-lisp*"))
                  (switch-to-buffer-other-window (get-buffer-create "*inferior-lisp*")))
              (run-lisp inferior-euslisp-program))

            (set-variable 'inferior-euslisp-program "~/.emacs.d/roseus.sh")

            ;; Do not set C-cE for lisp-other-window
            ;; (global-set-key "\C-cE" 'lisp-other-window)
            )
  )

(use-package goby
  :defer t
  :init (autoload 'goby "goby" nil t))

(use-package ansi-color
  :init (progn
          (defun endless/colorize-compilation ()
            "Colorize from `compilation-filter-start' to `point'."
            (let ((inhibit-read-only t))
              (ansi-color-apply-on-region
               compilation-filter-start (point))))

          (add-hook 'compilation-filter-hook
                    #'endless/colorize-compilation)
          )
  )

(use-package clang-format :ensure t
  :bind (:map c-mode-base-map
              ("C-c f" . 'clang-format-buffer)))

(if (not (file-directory-p "~/.emacs.d/plugins/"))
    (make-directory "~/.emacs.d/plugins/"))
(if (not (file-exists-p "~/.emacs.d/plugins/emacs-clang-rename.el"))
    (url-copy-file
     "https://raw.githubusercontent.com/nilsdeppe/emacs-clang-rename/master/emacs-clang-rename.el"
     "~/.emacs.d/plugins/emacs-clang-rename.el"))
(use-package emacs-clang-rename
  :if (file-exists-p "~/.emacs.d/plugins/emacs-clang-rename.el")
  :bind (:map c-mode-base-map
              ("C-c c p" . emacs-clang-rename-at-point)
              ("C-c c q" . emacs-clang-rename-qualified-name)
              ("C-c c a" . emacs-clang-rename-qualified-name-all))
  :config (progn
            (if (executable-find "clang-rename-6.0")
                (setq emacs-clang-rename-binary "clang-rename-6.0"))
            )
  )

(use-package py-yapf :ensure t
  :hook ((python-mode . (lambda () (define-key python-mode-map "\C-cf" 'py-yapf-buffer))))
  )

(use-package qml-mode :ensure t
  :config (progn
            (setq js-indent-level 2)
            )
  )

(use-package dictionary :ensure t
  :config (progn
            (setq dictionary-server "localhost")
            (setq dictionary-default-strategy "prefix")
            (defun dictionary-popup-matching-region-or-words ()
              (interactive)
              (let ((word
                     (if (use-region-p)
                         (buffer-substring (region-beginning) (region-end) )
                       (current-word))))
                (dictionary-popup-matching-words word)
                ))
            (global-set-key "\C-cs" 'dictionary-popup-matching-region-or-words)
            )
  )

(use-package emojify :ensure t
  :if (display-graphic-p)
  :hook (after-init . global-emojify-mode)
  :bind
  ("C-x e" . 'emojify-insert-emoji)
  )

(use-package gcmh :ensure t
  :config (gcmh-mode 1)
  )

(use-package transpose-frame :ensure t
  :bind (("C-x C-o" . 'rotate-frame-clockwise))
  )

(use-package prettier-js :ensure t
  :bind
  (:map typescript-mode-map
   ("C-c f" . 'prettier-js)
   :map js-mode-map
   ("C-c f" . 'lsp-format-buffer)
   )
  )

(use-package rosemacs-config
  :config (progn
            (global-set-key "\C-x\C-r" ros-keymap)
            )
  :load-path "/opt/ros/melodic/share/emacs/site-lisp"
  :if (file-exists-p "/opt/ros/melodic/share/emacs/site-lisp/rosemacs-config.el")
  )

(use-package systemd :ensure t)

(use-package projectile :ensure t
  :config
  (projectile-mode +1)
  (define-key projectile-mode-map (kbd "s-p") 'projectile-command-map)
  (define-key projectile-mode-map (kbd "C-c p") 'projectile-command-map)
  ;; projectile-add-known-project
  ;; (defun catkin-packages-list ()
  ;;   "List all the catkin packages in catkin workspace"
  ;;   (let ((cmake-prefix-path (getenv "CMAKE_PREFIX_PATH"))
  ;;         (catkin-root nil))
  ;;     (when cmake-prefix-path
  ;;       (setq catkin-root
  ;;             (format "%s/../src" (car (split-string cmake-prefix-path ":")))))
  ;;     (let ((string-output
  ;;            (shell-command-to-string
  ;;             (format "find %s -name package.xml -exec dirname {} \\\;"
  ;;                     catkin-root))))
  ;;       (let ((dirs (split-string string-output "\n")))
  ;;         dirs))))
  (dolist (proj (catkin-packages-list))
    (projectile-add-known-project proj))
  )

(use-package counsel-projectile :ensure t)

;; See http://lists.gnu.org/archive/html/bug-gnu-emacs/2019-04/msg01249.html
(setq inhibit-compacting-font-caches t)

;; Run emacsserver if not started.
(unless (server-running-p)
  (server-start))

(provide 'dot)

;; (require 'garaemon-project-setting)

;; load machine local setup
(if (file-exists-p "~/.emacs.d/dot.emacs.local.el")
    (load "~/.emacs.d/dot.emacs.local.el"))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(mode-line ((t (:background "color-16" :foreground "gray60" :inverse-video nil :box nil))))
 '(rainbow-delimiters-depth-1-face ((t (:foreground "#7f8c8d")))))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(avy-migemo-function-names
   '(swiper--make-overlays-migemo
     (swiper--re-builder :around swiper--re-builder-migemo-around)
     (ivy--regex :around ivy--regex-migemo-around)
     (ivy--regex-ignore-order :around ivy--regex-ignore-order-migemo-around)
     (ivy--regex-plus :around ivy--regex-plus-migemo-around)
     ivy--highlight-default-migemo ivy-occur-revert-buffer-migemo ivy-occur-press-migemo avy-migemo-goto-char avy-migemo-goto-char-2 avy-migemo-goto-char-in-line avy-migemo-goto-char-timer avy-migemo-goto-subword-1 avy-migemo-goto-word-1 avy-migemo-isearch avy-migemo-org-goto-heading-timer avy-migemo--overlay-at avy-migemo--overlay-at-full))
 '(custom-safe-themes
   '("3c83b3676d796422704082049fc38b6966bcad960f896669dfc21a7a37a748fa" default))
 '(lsp-pyls-plugins-jedi-completion-enabled t)
 '(lsp-pyls-plugins-jedi-hover-enabled t)
 '(lsp-pyls-plugins-pylint-enabled nil)
 '(lsp-pyls-plugins-yapf-enabled t)
 '(package-selected-packages
   '(counsel-projectile systemd company-statistics ivy-prescient udev-mode prettier-js capf typescript lsp-python-ms forge magit-gh-pulls transpose-frame gcmh switch-buffer-functions avy-migemo py-yapf lsp-treemacs dictionary auto-package-update org-download clang-format ivy-posframe esup counsel use-package cquery slack modern-cpp-font-lock total-lines solarized-theme origami nlinum minimap imenus imenu-list company base16-theme)))
(put 'upcase-region 'disabled nil)
(put 'downcase-region 'disabled nil)
