;;; init-startup-test.el --- Tests for the startup path of init.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Startup failures this suite pins down, all reported as errors in
;; *Messages* on a fresh Emacs 30 start:
;;
;; - `tsx-mode' cannot activate while `treesit-fold' stays uninstallable,
;;   which happens when `package-archives' drops the NonGNU ELPA entry that
;;   Emacs ships by default.
;;
;; The tests read the init files instead of loading them, because loading
;; them reaches for the package archives.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/init-startup-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(defconst init-startup-test-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory that holds this test file.")

(defun init-startup-test--read-forms (relative-name)
  "Return the top-level forms of RELATIVE-NAME, relative to emacs.d/."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name (concat "../" relative-name) init-startup-test-directory))
    (goto-char (point-min))
    ;; A fresh symbol marks the end of the file, which a plain nil could not:
    ;; `read' returns nil for a top-level nil form too.
    (let ((end-of-forms (make-symbol "end-of-forms")))
      (cl-loop for form = (condition-case nil
                              (read (current-buffer))
                            (end-of-file end-of-forms))
               until (eq form end-of-forms)
               collect form))))

(defun init-startup-test--find-form (forms predicate)
  "Return the first form within FORMS, at any depth, that satisfies PREDICATE."
  (cl-loop for form in forms
           for found = (cond
                        ((funcall predicate form) form)
                        ((consp form)
                         (init-startup-test--find-form form predicate)))
           when found return found))

(defun init-startup-test--setq-value (forms variable)
  "Return the value expression VARIABLE is assigned in FORMS."
  (let ((setq-form (init-startup-test--find-form
                    forms
                    (lambda (form)
                      (and (eq (car-safe form) 'setq)
                           (eq (cadr form) variable))))))
    (nth 2 setq-form)))

(defun init-startup-test--form-position (forms predicate)
  "Return the index of the first top-level form of FORMS matching PREDICATE."
  (cl-position-if predicate forms))

(ert-deftest init-should-keep-nongnu-in-package-archives ()
  ;; Arrange
  (let* ((forms (init-startup-test--read-forms "init.el"))
         (archives (eval (init-startup-test--setq-value forms 'package-archives) t)))
    ;; Act
    (let ((names (mapcar #'car archives)))
      ;; Assert
      (should (member "nongnu" names)))))

(ert-deftest init-should-fetch-every-archive-over-https ()
  ;; Arrange
  (let* ((forms (init-startup-test--read-forms "init.el"))
         (archives (eval (init-startup-test--setq-value forms 'package-archives) t)))
    ;; Act
    (let ((plain-http (cl-remove-if-not
                       (lambda (archive) (string-prefix-p "http://" (cdr archive)))
                       archives)))
      ;; Assert
      (should (null plain-http)))))

(provide 'init-startup-test)
;;; init-startup-test.el ends here
