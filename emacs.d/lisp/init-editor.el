;;; init-editor.el --- Editor features and enhancements -*- lexical-binding: t -*-

;;; Commentary:
;; Editor features, completion, search, navigation, and editing enhancements.

;;; Code:

;;; Delete trailing whitespaces when saving the file
(add-hook 'before-save-hook 'delete-trailing-whitespace)

;;; query-replace-regexp
(defalias 'qrr 'query-replace-regexp)
;; for mistype :)
(global-set-key "\M-%" 'query-replace)
(global-set-key "\M-&" 'query-replace)

;;; Show ediff with horizontal split view
(setq ediff-split-window-function 'split-window-horizontally)

;;; Completion frameworks

(use-package vertico
  :ensure t
  :custom
  ;; (vertico-scroll-margin 0) ;; Different scroll margin
  (vertico-count 20)
  ;; (vertico-resize t) ;; Grow and shrink the Vertico minibuffer
  ;; (vertico-cycle t) ;; Enable cycling for `vertico-next/previous'
  :init
  (vertico-mode)
  :bind (:map vertico-map
              ("C-s" . 'vertico-next)
              ("C-r" . 'vertico-previous)
              )
  )

(use-package vertico-posframe :ensure t
  :after (vertico)
  :config
  (vertico-posframe-mode)
  )

(use-package corfu
  :ensure t
  ;; Optional customizations
  :custom
  (corfu-auto t)
  (corfu-cycle t)                ;; Enable cycling for `corfu-next/previous'
  (corfu-quit-at-boundary t)
  (corfu-quit-no-match t)
  (corfu-preview-current nil)    ;; Disable current candidate preview
  (corfu-preselect 'prompt)      ;; Preselect the prompt
  (corfu-on-exact-match nil)     ;; Configure handling of exact matches

  ;; Recommended: Enable Corfu globally.  This is recommended since Dabbrev can
  ;; be used globally (M-/).  See also the customization variable
  ;; `global-corfu-modes' to exclude certain modes.
  :init
  (global-corfu-mode)
  (corfu-popupinfo-mode)
  :bind (:map corfu-map
              ;; Do not allow corfu to steal C-a and C-e
              ([remap move-end-of-line] . nil)
              ([remap move-beginning-of-line] . nil)
              ([remap beginning-of-buffer] . nil)
              ([remap end-of-buffer] . nil)
              ([remap next-line] . nil)
              ([remap previous-line] . nil)
              ([remap scroll-down-command] . nil)
              ([remap scroll-up-command] . nil)
              ("<tab>" . corfu-next)
              ("S-<tab>" . corfu-previous)
              )
  )

(use-package cape
  :after corfu
  :ensure t
  :config
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-emoji)
  (add-hook 'completion-at-point-functions #'cape-file)
  )

(use-package marginalia
  :ensure t
  :config
  (marginalia-mode 1))

(use-package orderless
  :ensure t
  :custom
  ;; Configure a custom style dispatcher (see the Consult wiki)
  ;; (orderless-style-dispatchers '(+orderless-consult-dispatch orderless-affix-dispatch))
  ;; (orderless-component-separator #'orderless-escapable-split-on-space)
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

;;; Search and navigation

(use-package consult
  :ensure t
  :bind
  ("C-x b" . consult-buffer)
  ("M-s" . consult-ripgrep)
  :config
  (defun my-get-git-files ()
    (let ((root-dir (magit-toplevel "")))
      (when root-dir
        (with-temp-buffer
          (let ((default-directory root-dir))
            ;; Change default-directory to the root directory of the git project. This is because
            ;; git ls-files returns the paths relative from the current working directory.
            (vc-git-command (current-buffer) t nil "ls-files"))
          (let ((local-file-names (split-string (buffer-string) "\n" t)))
            ;; local-file-names is a relative path from root-dir.
            (mapcar #'(lambda (local-file)
                        (file-name-concat root-dir local-file))
                    local-file-names))))))

  (setq my-git-files-source
        `( :name "Git Files"
           :narrow ?g
           :category 'file
           :items ,#'my-get-git-files
           :state ,#'consult--file-state))

  (defun my-get-ghq-repositories ()
    "Get list of ghq repositories."
    (when (executable-find "ghq")
      (with-temp-buffer
        (call-process "ghq" nil (current-buffer) nil "list" "-p")
        (split-string (buffer-string) "\n" t))))

  (setq my-ghq-repositories-source
        `( :name "Ghq Repositories"
           :narrow ?q
           :category 'file
           :items ,#'my-get-ghq-repositories
           :state ,#'consult--file-state))

  (setq consult-buffer-sources (append consult-buffer-sources '(my-git-files-source my-ghq-repositories-source)))

  (defun my-consult-async-process (program process-function &rest program-args)
    "Create a consult dynamic collection by running PROGRAM asynchronously.

PROGRAM is the executable file path (can be local or remote via Tramp).
PROCESS-FUNCTION is a function called with the raw string output of PROGRAM.
It should return a list of candidate strings.
PROGRAM-ARGS are the command-line arguments passed to PROGRAM.

The collection runs PROGRAM, processes its output with PROCESS-FUNCTION,
filters the results based on user input, and passes them to the callback."
    (lexical-let ((local-program (if (file-remote-p program)
                                     (tramp-file-name-localname (tramp-dissect-file-name program))
                                   program))
                  (program program)
                  (program-args program-args)
                  (process-function process-function))
      (consult--dynamic-collection
          (lambda (input callback)
            (with-temp-buffer
              ;; if program is a remote file, we have to set default-directory to run process on the
              ;; remote host.
              (let ((default-directory (or (file-remote-p program) default-directory)))
                (apply #'process-file local-program nil (current-buffer) nil program-args)
                ;; TODO: check return code
                (let* ((program-output (buffer-string))
                       (items (funcall process-function program-output))
                       ;; find the path matches input. Why cannott consult-buffer handle matching?
                       (filtered-items (cl-remove-if-not (lambda (path) (string-match-p input path))
                                                         items)))
                  (funcall callback filtered-items))))))))


  (defun my-process-rospack-list (env-sh program-output)
    "Process PROGRAM-OUTPUT from a 'rospack list'-like command.

ENV-SH is a path used to determine if the context is remote (e.g., a ROS setup script).
PROGRAM-OUTPUT is the raw string output, expected to contain lines of
'package_name /path/to/package'.

Returns a list of full package paths, adding a remote prefix
if ENV-SH indicates a remote path. Relies on the helper function
`my-separate-rospack-package-name-and-path`."
    (let* ((rospackage-paths
            (mapcar #'(lambda (rospack-line)
                        ;; rospack-line := pacakge_name path/to/package
                        (cadr (string-split rospack-line " ")))
                    (split-string program-output "\n" t)))
           ;; Append remote prefix if needed
           (file-prefix (or (file-remote-p env-sh) ""))
           (full-matched-package-paths
            (mapcar #'(lambda (path) (format "%s%s" file-prefix path))
                    rospackage-paths)))
      full-matched-package-paths))
  )

(use-package embark
  :ensure t
  :bind (("C-." . embark-act)
         :map minibuffer-local-map
         ("C-c C-c" . embark-collect)
         ("C-c C-e" . embark-export)))

(use-package embark-consult :ensure t)

(use-package swiper :ensure t
  :bind
  ("C-s" . 'swiper-isearch)
  :config
  (setopt ivy-use-virtual-buffers t)
  (setopt enable-recursive-minibuffers t)
  )

;;; Query-replace enhancements

(use-package anzu :ensure t
  :defer t
  :config
  (global-anzu-mode +1)
  (setq anzu-search-threshold 1000))

;;; Multiple cursors

(use-package multiple-cursors :ensure t
  :bind
  (("<C-M-return>" . 'mc/edit-lines)
   ("C-M-j" . 'mc/edit-lines)
   ("<C-M-down>" . 'mc/mark-next-like-this)
   ("<C-M-up>" . 'mc/mark-previous-like-this)
   )
  )

;;; Region expansion

(use-package expreg
  :ensure t
  :bind (("\C-^" . 'expreg-expand))
  )

;;; Spell checking

(use-package jinx
  :ensure t
  :if (my-find-file-under-directories "enchant.h"
                                      '("/usr/include" "/usr/local/include" "/opt/homebrew"))
  :config
  ;; Ignore non-English words.
  (add-to-list 'jinx-exclude-regexps '(t ".*[^[:ascii:]].*"))
  ;; Overwrite jinx--check-pending not to raise args-out-of-range errors.
  (defun jinx--check-pending (start end)
    "Check pending visible region between START and END."
    (let ((retry (and (eq (window-buffer) (current-buffer))
                      (symbolp real-last-command)
                      (string-match-p "self-insert-command\\'"
                                      (symbol-name real-last-command))
                      (window-point))))
      (while (< start end)
        (let* ((vfrom (jinx--find-visible start end t))
               (vto (jinx--find-visible vfrom end nil)))
          (while (< vfrom vto)
            ;; Add min with (point-max) for text-property-any not to raise args-out-of-range errors.
            (let* ((pfrom (or (text-property-any (min vfrom (point-max)) (min vto (point-max)) 'jinx--pending t) vto))
                   (pto (or (text-property-not-all (min pfrom (point-max)) (min vto (point-max)) 'jinx--pending t) vto)))
              (when (< pfrom pto)
                (jinx--check-region pfrom pto retry))
              (setq vfrom pto)))
          (setq start vto)))))

  :custom
  (jinx-languages "en_US")
  :bind
  ("\C-cd" . jinx-correct)
  ;; just executing (global-jinx-mode) does not turn on jinx.
  ;; We have to add a hook to emacs-start-hook
  :hook ('emacs-startup-hook . 'global-jinx-mode)
  )

;;; Dictionary

(use-package dictionary :ensure t
  :config
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
  )

;;; Auto-save and backup packages

(use-package backup-each-save :ensure t
  :config
  (setq backup-each-save-mirror-location "~/.emacs.d/backups")
  ;; suffix for backup file
  (setq backup-each-save-time-format "%y%m%d_%H%M%S")
  ;; the size limit of backup files
  (setq backup-each-save-size-limit 5000000)
  ;; backup all the files
  (setq backup-each-save-filter-function 'identity)
  :init (add-hook 'after-save #'backup-each-save)
  )

;;; Buffer management

(use-package bm :ensure t
  :bind ((("M-^" . 'bm-toggle)
          ("C-M-n" . 'bm-next)
          ("C-M-p" . 'bm-previous)))
  :config
  (global-set-key [?\C-\M-\ ] 'bm-toggle) ;not work
  (set-face-background bm-face "orange")
  (set-face-foreground bm-face "black")
  )

(use-package buffer-move :ensure t
  :bind
  ("\C-c <down>" . buf-move-down)
  ("\C-c <up>" . buf-move-up)
  ("\C-c <right>" . buf-move-right)
  ("\C-c <left>" . buf-move-left)
  )

(use-package recentf-ext :ensure t)

(use-package uniquify
  :ensure nil
  :config (setq uniquify-buffer-name-style 'post-forward-angle-brackets)
  )

;;; Window management

(use-package switch-window :ensure t
  :config
  (defun split-window-horizontally-n (num-wins)
    "Split window horizontally into NUM-WINS windows."
    (interactive "p")
    (if (= num-wins 2)
        (split-window-horizontally)
      (progn (split-window-horizontally (- (window-width)
                                           (/ (window-width) num-wins)))
             (split-window-horizontally-n (- num-wins 1)))))

  (defun switch-window-or-split ()
    "Split window if there is enough space and switch to next window."
    (interactive)
    (if (one-window-p)
        ;; 4 is for linum characters.
        (let ((column-width (+ 100 4)))
          (if (>= (window-body-width) (* 3 column-width))
              (let ((split-num (/ (window-body-width) column-width)))
                (split-window-horizontally-n split-num))
            (split-window-horizontally)))
      (switch-window)))
  :bind ("M-o" . 'switch-window-or-split)
  )

;;; Dired enhancements

(use-package dired
  :ensure nil
  :bind (:map dired-mode-map
              ("M-s" . 'consult-grep)
              ("F" . 'magit-pull)
              ("b" . 'magit-branch))
  )

(use-package wdired
  :config
  (setq wdired-allow-to-change-permissions t)
  (define-key dired-mode-map "e" 'wdired-change-to-wdired-mode)
  )

;;; Grep configuration

(use-package grep
  :config
  (add-to-list 'grep-find-ignored-directories "node_modules")
  (add-to-list 'grep-find-ignored-directories "__pycache__")
  (add-to-list 'grep-find-ignored-directories "build")
  (add-to-list 'grep-find-ignored-directories "dist")
  )

;;; Undo/Redo

(use-package undo-tree :ensure t
  :if nil
  :custom
  (undo-tree-visualizer-diff nil)
  (undo-tree-history-directory-alist '(("." . "~/.emacs.d/undo")))
  (undo-tree-visualizer-timestamps t)
  :config
  (global-undo-tree-mode)
  (define-key undo-tree-visualizer-mode-map "\C-m" 'undo-tree-visualizer-quit)
  (add-to-list 'undo-tree-incompatible-major-modes #'magit-status-mode)
  )

(use-package vundo :ensure t
  :bind (
         ("C-x u" . vundo)
         (:map vundo-mode-map
               ("C-f" . 'vundo-forward)
               ("C-b" . 'vundo-backward)
               ("C-p" . 'vundo-previous)
               ("C-n" . 'vundo-next)
               ))
  )

;;; Misc editor enhancements

(use-package volatile-highlights :ensure t
  :config (volatile-highlights-mode))

;; Show candidate of keybinds after prefix keys such as C-c.
(use-package which-key :ensure t
  :config
  (which-key-mode)
  (which-key-setup-side-window-bottom)
  )

(use-package hydra :ensure t
  :config
  (defhydra hydra-zoom (global-map "<f2>")
    "zoom"
    ("g" text-scale-increase "in")
    ("l" text-scale-decrease "out"))
  )

(use-package imenus :ensure t)

(use-package smartrep :ensure t
  :config
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
        ("O"        . 'mc/reverse-regions)
        ("^" . 'enlarge-window)
        ("-" . 'shrink-window)
        ))
    )
  (define-smartrep-keys)
  )

(provide 'init-editor)
;;; init-editor.el ends here
