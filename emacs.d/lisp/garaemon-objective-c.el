;;; garaemon-objective-c.el --- Objective-C and Xcode helpers -*- lexical-binding: t -*-

;;; Commentary:
;; Objective-C mode setup plus small wrappers around the xcode-*.sh scripts.
;; Not loaded by init.el; require it explicitly when doing iOS work.

;;; Code:

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
;;; garaemon-objective-c.el ends here
