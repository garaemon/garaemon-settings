;;; my-treesit-auto-cache.el --- Cache the treesit-auto major mode remaps -*- lexical-binding: t; -*-

;;; Commentary:
;; `global-treesit-auto-mode' advises `set-auto-mode-0', so opening a file
;; rebuilds `major-mode-remap-alist' from scratch.  The rebuild asks
;; `treesit-ready-p' about every entry of `treesit-auto-langs', and a language
;; whose grammar is not installed costs a failed dlopen: 4.25 ms against
;; 0.78 ms for one that is.  With 50 of 62 languages missing the rebuild takes
;; roughly 220 ms, and `set-auto-mode-0' runs three times per file, so opening
;; a file stalls for about 840 ms.
;;
;; The answer set changes only when a grammar is installed, so this module
;; keeps the first result and hands it back until something installs one.
;;
;; treesit-auto declines to cache, and says why:
;;
;;   ;; For this mode to keep a cached copy is dangerous as it will be a global
;;   ;; replacement and ignores all changes while this mode is active
;;
;; That risk is real for a package that cannot know when the user edits
;; `major-mode-remap-alist' by hand.  A configuration can know: this one sets
;; the variable nowhere else, and `my-treesit-auto-invalidate-remap-cache'
;; covers the one event that does change the answer.

;;; Code:

(defconst my-treesit-auto-cache--unset 'my-treesit-auto-cache--unset
  "Marker distinguishing an empty cache from a cached empty result.")

(defvar my-treesit-auto-cache--remap-alist my-treesit-auto-cache--unset
  "The `major-mode-remap-alist' that treesit-auto last built.")

(defun my-treesit-auto-invalidate-remap-cache (&rest _)
  "Drop the cached remap alist so the next file open rebuilds it."
  (setq my-treesit-auto-cache--remap-alist my-treesit-auto-cache--unset))

(defun my-treesit-auto-cache-remap-alist (build-remap-alist &rest args)
  "Return the cached remap alist, calling BUILD-REMAP-ALIST on ARGS to fill it.

Meant as `:around' advice for `treesit-auto--build-major-mode-remap-alist'.

The builder appends to whatever `major-mode-remap-alist' currently holds, and
the treesit-auto advice that calls it assigns the result buffer-locally.  A
second call in the same buffer would therefore fold the previous result into
the new one, so the builder runs against the global value."
  (when (eq my-treesit-auto-cache--remap-alist my-treesit-auto-cache--unset)
    (setq my-treesit-auto-cache--remap-alist
          (let ((major-mode-remap-alist (default-value 'major-mode-remap-alist)))
            (apply build-remap-alist args))))
  my-treesit-auto-cache--remap-alist)

(defun my-treesit-auto-enable-remap-cache ()
  "Serve the treesit-auto remap alist from a cache.
Call this after `global-treesit-auto-mode', which installs the advice that
rebuilds the alist."
  (advice-add 'treesit-auto--build-major-mode-remap-alist
              :around #'my-treesit-auto-cache-remap-alist)
  ;; Installing a grammar is the one event that changes which languages are
  ;; ready, and treesit-auto installs them through this function.
  (advice-add 'treesit-install-language-grammar
              :after #'my-treesit-auto-invalidate-remap-cache))

(provide 'my-treesit-auto-cache)
;;; my-treesit-auto-cache.el ends here
