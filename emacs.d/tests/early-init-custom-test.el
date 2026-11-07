;;; early-init-custom-test.el --- Tests for early-custom.el loading -*- lexical-binding: t; -*-

;;; Commentary:
;; early-init.el loads a per-machine early-custom.el from
;; `user-emacs-directory' after its own defaults, so a local file can
;; override them before init.el runs.  Run with:
;;
;;   emacs -Q --batch -l ert -l tests/early-init-custom-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)

(defconst early-init-custom-test-early-init-file
  (expand-file-name "../early-init.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Path of the early-init.el under test.")

(defvar early-init-custom-test-marker nil
  "Value that the early-custom.el fixture assigns.")

(defconst early-init-custom-test-touched-variables
  '(gc-cons-threshold gc-cons-percentage default-frame-alist
    package-enable-at-startup load-prefer-newer
    inhibit-startup-screen inhibit-startup-message
    native-comp-deferred-compilation native-comp-async-report-warnings-errors)
  "Variables that early-init.el assigns.
CI loads every test file into one Emacs, so the helper restores these.")

(defun early-init-custom-test--save-variables ()
  "Return the global state of `early-init-custom-test-touched-variables'."
  (mapcar (lambda (variable)
            (list variable (boundp variable)
                  (and (boundp variable) (default-value variable))))
          early-init-custom-test-touched-variables))

(defun early-init-custom-test--restore-variables (saved-states)
  "Restore the global state that SAVED-STATES records."
  (dolist (saved-state saved-states)
    (pcase-let ((`(,variable ,was-bound ,saved-value) saved-state))
      (if was-bound
          (set-default variable saved-value)
        (makunbound variable)))))

(defun early-init-custom-test--load-early-init (early-custom-content)
  "Load early-init.el against a temporary `user-emacs-directory'.
Write EARLY-CUSTOM-CONTENT to early-custom.el there unless it is nil.
Restore `early-init-custom-test-touched-variables' afterwards, so read the
values that early-custom.el assigns from a variable outside that list."
  (let* ((temp-emacs-directory (file-name-as-directory
                                (make-temp-file "early-init-test" t)))
         (user-emacs-directory temp-emacs-directory)
         (saved-states (early-init-custom-test--save-variables)))
    (unwind-protect
        (progn
          (when early-custom-content
            (with-temp-file (expand-file-name "early-custom.el"
                                              temp-emacs-directory)
              (insert early-custom-content)))
          (load early-init-custom-test-early-init-file nil t))
      (early-init-custom-test--restore-variables saved-states)
      (delete-directory temp-emacs-directory t))))

(ert-deftest should_load_early_custom_after_early_init_defaults ()
  ;; early-custom.el sees the default that early-init.el assigned, so a setq
  ;; in early-custom.el overrides that default.  No Emacs default of
  ;; gc-cons-percentage equals the 0.6 that early-init.el assigns.
  ;; Arrange
  (setq early-init-custom-test-marker nil)
  ;; Act
  (early-init-custom-test--load-early-init
   "(setq early-init-custom-test-marker gc-cons-percentage)")
  ;; Assert
  (should (equal early-init-custom-test-marker 0.6)))

(ert-deftest should_start_without_error_when_early_custom_is_missing ()
  ;; Arrange
  (setq early-init-custom-test-marker nil)
  ;; Act
  (early-init-custom-test--load-early-init nil)
  ;; Assert
  (should-not early-init-custom-test-marker))

;;; early-init-custom-test.el ends here
