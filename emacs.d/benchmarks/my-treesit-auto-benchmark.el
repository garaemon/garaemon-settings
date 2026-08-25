;;; my-treesit-auto-benchmark.el --- Timings for the treesit-auto remap -*- lexical-binding: t; -*-

;;; Commentary:
;; `global-treesit-auto-mode' rebuilds `major-mode-remap-alist' from inside its
;; `set-auto-mode-0' advice, so this rebuild runs several times per file open.
;; Its cost comes from probing every entry of `treesit-auto-langs', and a
;; language whose grammar is missing costs several times one that is present.
;; A CI runner has no grammar installed at all, so it pays the full price and
;; measures the worst case a workstation approaches.
;;
;; The scenario enables whatever the branch does to that rebuild, which is how
;; a branch that caches the answer separates itself from one that does not.

;;; Code:

(require 'my-benchmark)

(declare-function treesit-auto--build-major-mode-remap-alist "treesit-auto" ())
(declare-function my-treesit-auto-enable-remap-cache "my-treesit-auto-cache" ())

(defun my-treesit-auto-benchmark--available-p ()
  "Return non-nil when treesit-auto exposes the rebuild this scenario times."
  (and (require 'treesit-auto nil 'noerror)
       (fboundp 'treesit-auto--build-major-mode-remap-alist)))

(defun my-treesit-auto-benchmark--apply-branch-configuration ()
  "Apply what this branch does to the remap rebuild, if it does anything.
A branch without `my-treesit-auto-cache' leaves the rebuild alone, which is
the comparison this scenario exists to draw."
  (when (require 'my-treesit-auto-cache nil 'noerror)
    (my-treesit-auto-enable-remap-cache)))

(my-benchmark-define
 "treesit-auto-remap"
 :available-p #'my-treesit-auto-benchmark--available-p
 :setup #'my-treesit-auto-benchmark--apply-branch-configuration
 :thunk (lambda () (treesit-auto--build-major-mode-remap-alist)))

(provide 'my-treesit-auto-benchmark)
;;; my-treesit-auto-benchmark.el ends here
