;;; init-startup-test.el --- Tests for the startup path of init.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Startup and configuration faults this suite pins down.  The first three
;; surface as errors in *Messages* on a fresh Emacs 31 start, while the last
;; two stay silent:
;;
;; - `tsx-mode' cannot activate while `treesit-fold' stays uninstallable,
;;   which happens when `package-archives' drops the NonGNU ELPA entry that
;;   Emacs ships by default.
;; - Package autoload files that call `treesit-ready-p' at top level fail
;;   with `void-function' unless treesit is loaded before the activation
;;   pass of `package-initialize'.
;; - `yas-global-mode' warns once for every entry of `yas-snippet-dirs' that
;;   is not a directory.
;; - A `use-package' :hook entry that names `<mode>-hook' registers
;;   `<mode>-hook-hook', a hook that nothing ever runs.
;; - A `use-package' form with both :after and :bind-keymap leaves its
;;   prefix key unbound until another command loads the :after package.
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

(ert-deftest init-should-load-treesit-before-package-initialize ()
  ;; Arrange
  (let ((forms (init-startup-test--read-forms "init.el")))
    ;; Act
    (let ((treesit-position
           (init-startup-test--form-position
            forms
            (lambda (form)
              (and (eq (car-safe form) 'require)
                   (equal (cadr form) '(quote treesit))))))
          (initialize-position
           (init-startup-test--form-position
            forms
            (lambda (form) (eq (car-safe form) 'package-initialize)))))
      ;; Assert
      (should treesit-position)
      (should initialize-position)
      (should (< treesit-position initialize-position)))))

(ert-deftest init-prog-should-keep-snippet-dirs-under-user-emacs-directory ()
  ;; Arrange
  (let* ((forms (init-startup-test--read-forms "lisp/init-prog.el"))
         (dirs-form (init-startup-test--setq-value forms 'yas-snippet-dirs))
         (user-emacs-directory "/tmp/init-startup-test-emacs.d/"))
    ;; Act
    (let ((dirs (eval dirs-form t)))
      ;; Assert
      (should dirs)
      (should (cl-every (lambda (dir)
                          (string-prefix-p user-emacs-directory dir))
                        dirs)))))

(defun init-startup-test--list-configuration-files ()
  "Return the names of the files that configure Emacs, relative to emacs.d/."
  (append '("init.el" "early-init.el")
          (mapcar (lambda (absolute-name)
                    (concat "lisp/" (file-name-nondirectory absolute-name)))
                  (directory-files
                   (expand-file-name "../lisp" init-startup-test-directory)
                   t "\\.el\\'"))))

(defun init-startup-test--walk-conses (form visit)
  "Call VISIT on FORM and on every cons cell nested inside FORM.
Recursing through `car' and `cdr' keeps dotted pairs such as a :hook entry
intact; a list traversal would reject them."
  (funcall visit form)
  (when (consp form)
    (init-startup-test--walk-conses (car form) visit)
    (init-startup-test--walk-conses (cdr form) visit)))

(defun init-startup-test--collect-use-package-forms (forms)
  "Return every `use-package' form within FORMS, at any depth."
  (let ((found nil))
    (init-startup-test--walk-conses
     forms
     (lambda (form)
       (when (eq (car-safe form) 'use-package)
         (push form found))))
    (nreverse found)))

(defun init-startup-test--list-entry-modes (entry)
  "Return the mode symbols that a single `use-package' :hook ENTRY names.
ENTRY is a mode symbol, a (MODES . FUNCTION) pair, or a list of such pairs.
A list of pairs is proper, whereas the pair ((c-mode c++-mode) . FUNCTION)
is dotted, which tells the two shapes apart."
  (cond
   ((symbolp entry) (list entry))
   ((not (consp (car entry))) (list (car entry)))
   ((proper-list-p entry)
    (cl-loop for pair in entry append (init-startup-test--list-entry-modes pair)))
   (t (car entry))))

(defun init-startup-test--list-hook-modes (use-package-form)
  "Return the mode symbols that USE-PACKAGE-FORM binds through :hook."
  (let ((entries (cl-loop for element in (cdr (memq :hook use-package-form))
                          until (keywordp element)
                          collect element)))
    (cl-loop for entry in entries
             append (init-startup-test--list-entry-modes entry))))

(ert-deftest init-should-name-use-package-hooks-without-the-hook-suffix ()
  ;; Arrange
  ;; `use-package' appends `use-package-hook-name-suffix', which is "-hook",
  ;; to every :hook entry.  An entry written as `dired-mode-hook' therefore
  ;; ends up on `dired-mode-hook-hook' and never runs.
  (let ((misnamed-hooks nil))
    ;; Act
    (dolist (relative-name (init-startup-test--list-configuration-files))
      (dolist (use-package-form
               (init-startup-test--collect-use-package-forms
                (init-startup-test--read-forms relative-name)))
        (dolist (mode (init-startup-test--list-hook-modes use-package-form))
          (when (string-suffix-p "-hook" (symbol-name mode))
            (push (format "%s: %s" relative-name mode) misnamed-hooks)))))
    ;; Assert
    (should (null misnamed-hooks))))

(ert-deftest init-should-not-defer-bind-keymap-behind-after ()
  ;; Arrange
  ;; `use-package' wraps the whole form, :bind-keymap included, in
  ;; `eval-after-load' for every :after package.  The prefix key therefore
  ;; stays unbound until something else loads that package.
  (let ((deferred-prefixes nil))
    ;; Act
    (dolist (relative-name (init-startup-test--list-configuration-files))
      (dolist (use-package-form
               (init-startup-test--collect-use-package-forms
                (init-startup-test--read-forms relative-name)))
        (when (and (memq :after use-package-form)
                   (memq :bind-keymap use-package-form))
          (push (format "%s: %s" relative-name (cadr use-package-form))
                deferred-prefixes))))
    ;; Assert
    (should (null deferred-prefixes))))

(provide 'init-startup-test)
;;; init-startup-test.el ends here
