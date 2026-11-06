;;; my-tty-faces-test.el --- Tests for my-tty-faces -*- lexical-binding: t; -*-

;;; Commentary:
;; The batch frame has no window system, so it matches the `tty' display
;; condition in the face specs.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-tty-faces-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'hl-line)
(require 'paren)
(require 'my-tty-faces)

(defun my-tty-faces-test--chosen-attribute (face attribute)
  "Return ATTRIBUTE of FACE as its spec resolves on the batch frame."
  (plist-get (face-spec-choose (get face 'face-defface-spec)
                               (selected-frame))
             attribute))

(ert-deftest my-tty-faces-should-use-dark-background-for-hl-line ()
  (my-tty-faces-apply)
  (should (equal (my-tty-faces-test--chosen-attribute 'hl-line :background)
                 my-tty-faces-line-background)))

(ert-deftest my-tty-faces-should-use-subtle-background-for-paren-match ()
  (my-tty-faces-apply)
  (should (equal (my-tty-faces-test--chosen-attribute 'show-paren-match
                                                      :background)
                 my-tty-faces-paren-background)))

(ert-deftest my-tty-faces-should-keep-hl-line-inherit-highlight-on-gui ()
  (my-tty-faces-apply)
  (should (eq (plist-get (cdr (assq t (get 'hl-line 'face-defface-spec)))
                         :inherit)
              'highlight)))

(provide 'my-tty-faces-test)
;;; my-tty-faces-test.el ends here
