;;; my-vterm-buffer-test.el --- Tests for vterm-only buffer switching -*- lexical-binding: t; -*-

;;; Commentary:
;; Regression tests for the buffer list behind the vterm-only `C-x b'.
;;
;; `my-vterm-list-buffers' must:
;;
;; 1. Keep vterm buffers and drop everything else.
;; 2. Recognize modes derived from `vterm-mode', not just `vterm-mode'
;;    itself.
;; 3. Preserve the `buffer-list' order, which puts the most recently used
;;    buffer first.
;;
;; The tests stub `buffer-list' with `cl-letf' so the candidate order is
;; deterministic, and fake the major modes so that neither vterm nor
;; consult has to be installed.  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-vterm-buffer-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-vterm-buffer)

;; multi-vterm buffers use `vterm-mode' itself, but a mode derived from
;; it must count as a terminal too.  vterm is absent in batch runs, so
;; declare the parent link by hand.
(put 'my-vterm-buffer-test--child-mode 'derived-mode-parent 'vterm-mode)

(defmacro my-vterm-buffer-test--with-buffers (modes &rest body)
  "Create one buffer per major mode in MODES and run BODY.
BODY can inspect the created buffers, in the order of MODES, in the
variable `buffers'.  `buffer-list' returns exactly those buffers."
  (declare (indent 1))
  `(let ((buffers (mapcar (lambda (mode)
                            (let ((buffer (generate-new-buffer " *vterm-test*")))
                              (with-current-buffer buffer (setq major-mode mode))
                              buffer))
                          ,modes)))
     (unwind-protect
         (cl-letf (((symbol-function 'buffer-list) (lambda (&optional _frame) buffers)))
           ,@body)
       (mapc #'kill-buffer buffers))))

;;; my-vterm-buffer-p: what counts as a terminal.

(ert-deftest my-vterm-buffer-p-should-accept-a-vterm-buffer ()
  (my-vterm-buffer-test--with-buffers '(vterm-mode)
    (should (my-vterm-buffer-p (car buffers)))))

(ert-deftest my-vterm-buffer-p-should-reject-an-ordinary-buffer ()
  (my-vterm-buffer-test--with-buffers '(text-mode)
    (should-not (my-vterm-buffer-p (car buffers)))))

(ert-deftest my-vterm-buffer-p-should-accept-a-derived-mode ()
  (my-vterm-buffer-test--with-buffers '(my-vterm-buffer-test--child-mode)
    (should (my-vterm-buffer-p (car buffers)))))

;;; my-vterm-list-buffers: which buffers the picker offers.

(ert-deftest my-vterm-list-buffers-should-keep-vterm-buffers ()
  (my-vterm-buffer-test--with-buffers '(vterm-mode text-mode)
    (should (memq (nth 0 buffers) (my-vterm-list-buffers)))))

(ert-deftest my-vterm-list-buffers-should-drop-other-buffers ()
  (my-vterm-buffer-test--with-buffers '(vterm-mode text-mode)
    (should-not (memq (nth 1 buffers) (my-vterm-list-buffers)))))

(ert-deftest my-vterm-list-buffers-should-keep-the-buffer-list-order ()
  ;; `buffer-list' is ordered most recently used first, which is the
  ;; order the picker should offer the terminals in.
  (my-vterm-buffer-test--with-buffers '(vterm-mode text-mode vterm-mode)
    (should (equal (my-vterm-list-buffers)
                   (list (nth 0 buffers) (nth 2 buffers))))))

(ert-deftest my-vterm-list-buffers-should-be-empty-without-terminals ()
  (my-vterm-buffer-test--with-buffers '(text-mode fundamental-mode)
    (should (equal (my-vterm-list-buffers) '()))))

(provide 'my-vterm-buffer-test)
;;; my-vterm-buffer-test.el ends here
