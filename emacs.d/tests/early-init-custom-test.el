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

(defun early-init-custom-test--load-early-init (early-custom-content)
  "Load early-init.el against a temporary `user-emacs-directory'.
Write EARLY-CUSTOM-CONTENT to early-custom.el there unless it is nil.
Restore the variables that early-init.el touches afterwards."
  (let* ((temp-emacs-directory (file-name-as-directory
                                (make-temp-file "early-init-test" t)))
         (user-emacs-directory temp-emacs-directory)
         (gc-cons-threshold gc-cons-threshold)
         (gc-cons-percentage gc-cons-percentage)
         (default-frame-alist default-frame-alist)
         (package-enable-at-startup package-enable-at-startup)
         (load-prefer-newer load-prefer-newer))
    (unwind-protect
        (progn
          (when early-custom-content
            (with-temp-file (expand-file-name "early-custom.el"
                                              temp-emacs-directory)
              (insert early-custom-content)))
          (load early-init-custom-test-early-init-file nil t))
      (delete-directory temp-emacs-directory t))))

(ert-deftest should_load_early_custom_when_file_exists ()
  ;; Arrange
  (setq early-init-custom-test-marker nil)
  ;; Act
  (early-init-custom-test--load-early-init
   "(setq early-init-custom-test-marker 'loaded)")
  ;; Assert
  (should (eq early-init-custom-test-marker 'loaded)))

(ert-deftest should_override_early_init_defaults_with_early_custom ()
  ;; Arrange
  (let ((inhibit-startup-screen nil))
    ;; Act
    (early-init-custom-test--load-early-init
     "(setq inhibit-startup-screen 'overridden)")
    ;; Assert
    (should (eq inhibit-startup-screen 'overridden))))

(ert-deftest should_start_without_error_when_early_custom_is_missing ()
  ;; Arrange
  (setq early-init-custom-test-marker nil)
  ;; Act
  (early-init-custom-test--load-early-init nil)
  ;; Assert
  (should-not early-init-custom-test-marker))

;;; early-init-custom-test.el ends here
