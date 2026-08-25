;;; my-treesit-auto-cache-test.el --- Tests for the treesit-auto remap cache -*- lexical-binding: t; -*-

;;; Commentary:
;; The cache stands between `treesit-auto' and every file Emacs opens, so the
;; tests pin down when it rebuilds and what it reads.  They drive the advice
;; function directly with a counting stub, which keeps treesit-auto out of the
;; test dependencies.
;;
;; Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-treesit-auto-cache-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'my-treesit-auto-cache)

(defun my-treesit-auto-cache-test--counting-builder (counter result)
  "Return a builder that increments COUNTER and returns RESULT."
  (lambda (&rest _) (cl-incf (car counter)) result))

(ert-deftest my-treesit-auto-cache-should-build-once-for-repeated-calls ()
  (my-treesit-auto-invalidate-remap-cache)
  (let* ((counter (list 0))
         (build (my-treesit-auto-cache-test--counting-builder
                 counter '((python-mode . python-ts-mode)))))
    (my-treesit-auto-cache-remap-alist build)
    (my-treesit-auto-cache-remap-alist build)
    (should (equal (car counter) 1))))

(ert-deftest my-treesit-auto-cache-should-return-the-same-alist-every-call ()
  (my-treesit-auto-invalidate-remap-cache)
  (let* ((counter (list 0))
         (remaps '((python-mode . python-ts-mode)))
         (build (my-treesit-auto-cache-test--counting-builder counter remaps)))
    (should (equal (my-treesit-auto-cache-remap-alist build) remaps))
    (should (equal (my-treesit-auto-cache-remap-alist build) remaps))))

(ert-deftest my-treesit-auto-cache-should-rebuild-after-an-invalidation ()
  (my-treesit-auto-invalidate-remap-cache)
  (let* ((counter (list 0))
         (build (my-treesit-auto-cache-test--counting-builder counter nil)))
    (my-treesit-auto-cache-remap-alist build)
    (my-treesit-auto-invalidate-remap-cache)
    (my-treesit-auto-cache-remap-alist build)
    (should (equal (car counter) 2))))

(ert-deftest my-treesit-auto-cache-should-hold-an-empty-result ()
  (my-treesit-auto-invalidate-remap-cache)
  (let* ((counter (list 0))
         (build (my-treesit-auto-cache-test--counting-builder counter nil)))
    (my-treesit-auto-cache-remap-alist build)
    (my-treesit-auto-cache-remap-alist build)
    (should (equal (car counter) 1))))

(ert-deftest my-treesit-auto-cache-should-build-from-the-global-remap-alist ()
  ;; The treesit-auto builder appends to `major-mode-remap-alist', and the
  ;; advice that calls it assigns the result buffer-locally.  Reading the
  ;; buffer-local value would fold an earlier result into the cached one.
  (my-treesit-auto-invalidate-remap-cache)
  (let ((seen 'never-called))
    (with-temp-buffer
      (setq-local major-mode-remap-alist '((stale-mode . stale-ts-mode)))
      (my-treesit-auto-cache-remap-alist
       (lambda (&rest _) (setq seen major-mode-remap-alist) nil)))
    (should (equal seen (default-value 'major-mode-remap-alist)))))

(ert-deftest my-treesit-auto-cache-should-pass-the-arguments-through ()
  (my-treesit-auto-invalidate-remap-cache)
  (let ((seen 'never-called))
    (my-treesit-auto-cache-remap-alist
     (lambda (&rest args) (setq seen args) nil)
     'first 'second)
    (should (equal seen '(first second)))))

(provide 'my-treesit-auto-cache-test)
;;; my-treesit-auto-cache-test.el ends here
