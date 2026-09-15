;;; my-vterm-toggle-binding-test.el --- Tests for the C-c t binding -*- lexical-binding: t; -*-

;;; Commentary:
;; `C-c t' starts the first vterm of a session, so the key has to be
;; bound before vterm is loaded.  use-package installs the keys of a
;; block deferred with `:after vterm' only once vterm loads, and nothing
;; else in the init loads vterm, so a `:bind' placed there leaves the key
;; undefined for the whole session.
;;
;; The test reads the `use-package' form that owns the binding from
;; lisp/init-prog.el and evaluates it in an Emacs without vterm, which is
;; what CI provides.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-vterm-toggle-binding-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'bind-key)
(require 'cl-lib)
(require 'use-package)

(defconst my-vterm-toggle-binding-test-init-prog-file
  (expand-file-name "../lisp/init-prog.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Init file that carries the vterm `use-package' blocks.")

(defun my-vterm-toggle-binding-test--read-use-package-form (name)
  "Return the `use-package' form for NAME read from lisp/init-prog.el."
  (with-temp-buffer
    (insert-file-contents my-vterm-toggle-binding-test-init-prog-file)
    (goto-char (point-min))
    ;; A fresh symbol marks the end of the file, which a plain nil could not:
    ;; `read' returns nil for a top-level nil form too.
    (let ((end-of-forms (make-symbol "end-of-forms")))
      (cl-loop for form = (condition-case nil
                              (read (current-buffer))
                            (end-of-file end-of-forms))
               until (eq form end-of-forms)
               when (and (eq (car-safe form) 'use-package)
                         (eq (cadr form) name))
               return form))))

(ert-deftest my-vterm-toggle-binding-should-bind-c-c-t-without-vterm-loaded ()
  ;; Arrange
  (let ((toggle-form (my-vterm-toggle-binding-test--read-use-package-form
                      'my-vterm-toggle))
        (global-map (make-sparse-keymap))
        (after-load-alist (copy-alist after-load-alist))
        (personal-keybindings (copy-sequence personal-keybindings))
        (real-require (symbol-function 'require))
        ;; `:ensure' would reach for the package archives.
        (use-package-ensure-function 'ignore))
    ;; A loaded vterm would satisfy `:after vterm', so the regression this test
    ;; looks for could not appear.
    (skip-unless (not (featurep 'vterm)))
    (should toggle-form)
    ;; Act
    ;; A full-suite run has already loaded my-vterm-toggle through
    ;; tests/my-vterm-toggle-test.el, so `:config' fires at once. Keep the
    ;; require from asking for vterm-toggle, which CI does not install.
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest args)
                 (unless (eq feature 'vterm-toggle)
                   (apply real-require feature args)))))
      (eval toggle-form t))
    ;; Assert
    (should (eq (lookup-key global-map (kbd "C-c t")) 'my-vterm-toggle))))

(provide 'my-vterm-toggle-binding-test)
;;; my-vterm-toggle-binding-test.el ends here
