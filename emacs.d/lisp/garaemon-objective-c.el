;; -*- mode: emacs-lisp -*-
(setq auto-mode-alist
      (append auto-mode-alist '(("\\.h$" . objc-mode)
                                ("\\.m$" . objc-mode))))

;; (require 'flymake)

;; (defvar flymake-compiler "gcc")
;; (defvar flymake-compile-options nil)
;; (defvar flymake-compile-default-options
;;         (list "-Wall" "-Wextra" "-fsyntax-only"))

;; (defun flymake-objc-init ()
;;   (let* ((temp-file   (flymake-init-create-temp-buffer-copy
;;                        'flymake-create-temp-inplace))
;;          (local-file  (file-relative-name
;;                        temp-file
;;                        (file-name-directory buffer-file-name)))
;; 	 (options flymake-compile-default-options))
;;     (list flymake-compiler (append options (list local-file)))))

;; (push '("\\.m$" flymake-objc-init) flymake-allowed-file-name-masks)
;; (push '("\\.h$" flymake-objc-init) flymake-allowed-file-name-masks)

;; (add-hook 'objc-mode-hook
;;           '(lambda ()
;; 	     (flymake-mode t)))

;;(provide 'flymake-objc)

;; clipboard
;; (if (not window-system)
;;     (progn
;;       (defun copy-from-osx ()
;;         (shell-command-to-string "pbpaste"))
;;       (defun paste-to-osx (text &optional push)
;;         (let ((process-connection-type nil))
;;           (let ((proc (start-process "pbcopy" "*Messages*" "pbcopy")))
;;             (process-send-string proc text)
;;             (process-send-eof proc))))
;;       (setq interprogram-cut-function 'paste-to-osx)
;;       (setq interprogram-paste-function 'copy-from-osx)))
;; objc, Xcode
(setq auto-mode-alist (append (list '("\\.h$" . objc-mode)
                                    '("\\.m$" . objc-mode))
                              auto-mode-alist))
(add-hook 'objc-mode-hook
          #'(lambda ()
              (define-key objc-mode-map "\C-c\C-b" 'compile)
              (define-key objc-mode-map "\C-c\C-r" 'run)
              (define-key objc-mode-map "\C-c\C-x" 'xcode)
              (define-key objc-mode-map "\C-c\C-d" 'doc)
              (define-key objc-mode-map "\C-c\C-c" 'comment-region)
              (define-key objc-mode-map "\C-cc"    'uncomment-region)
              (setq compile-command
                    "xcodebuild -project ../*.xcodeproj -configuration Debug -sdk iphonesimulator5.0 ")
                    ;;"xcodebuild -project ../*.xcodeproj -configuration Debug -sdk iphonesimulator4.3 ")
              (setq compilation-scroll-output t)))

(defun doc ()
  (interactive)
  (shell-command-to-string "/usr/local/bin/xcode-show-doc.sh"))

(defun xcode ()
  (interactive)
  (shell-command-to-string "/usr/local/bin/xcode-show-proj.sh"))

(defun run ()
  (interactive)
  (shell-command-to-string "/usr/local/bin/xcode-run.sh"))
(provide 'garaemon-objective-c)
