(message "Loading init.el")
(setq package-archives
      '(("gnu" . "http://elpa.gnu.org/packages/")
        ("melpa" . "http://melpa.org/packages/")
        ("org" . "http://orgmode.org/elpa/")))
(package-initialize)
(call-interactively 'package-refresh-contents)
(package-install 'use-package)
(use-package auto-package-update
  :ensure t)
(auto-package-update-now)
(add-to-list 'load-path "~/.emacs.d")
(load "init.el")
