;;; org-roam-dailies-binding-test.el --- Tests for the C-c n d binding -*- lexical-binding: t; -*-

;;; Commentary:
;; `C-c n d' opens the org-roam dailies prefix, which carries the daily
;; capture on `C-c n d n'.  use-package installs the keys of a block
;; deferred with `:after org-roam' only once org-roam loads, and the
;; org-roam block defers too, so a fresh session reaches the prefix only
;; after some other key, such as `C-c n f', has pulled org-roam in.
;;
;; The test reads the `use-package' form that owns the binding from
;; lisp/init-org.el and evaluates it in an Emacs without org-roam, which
;; is what CI provides.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/org-roam-dailies-binding-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'bind-key)
(require 'cl-lib)
(require 'use-package)

(defconst org-roam-dailies-binding-test-init-org-file
  (expand-file-name "../lisp/init-org.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Init file that carries the org-roam `use-package' blocks.")

(defun org-roam-dailies-binding-test--read-use-package-form (name)
  "Return the `use-package' form for NAME read from lisp/init-org.el."
  (with-temp-buffer
    (insert-file-contents org-roam-dailies-binding-test-init-org-file)
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

(ert-deftest org-roam-dailies-binding-should-bind-c-c-n-d-without-org-roam-loaded ()
  ;; Arrange
  (let ((dailies-form (org-roam-dailies-binding-test--read-use-package-form
                       'org-roam-dailies))
        (global-map (make-sparse-keymap))
        (after-load-alist (copy-alist after-load-alist))
        (personal-keybindings (copy-sequence personal-keybindings))
        ;; `:ensure' would reach for the package archives.
        (use-package-ensure-function 'ignore))
    ;; A loaded org-roam would satisfy `:after org-roam', so the regression this
    ;; test looks for could not appear.
    (skip-unless (not (featurep 'org-roam)))
    (should dailies-form)
    ;; Act
    (eval dailies-form t)
    ;; Assert
    (should (commandp (lookup-key global-map (kbd "C-c n d"))))))

(provide 'org-roam-dailies-binding-test)
;;; org-roam-dailies-binding-test.el ends here
