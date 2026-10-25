;;; my-org-excalidraw-name-test.el --- Tests for automatic excalidraw file names -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-excalidraw-name.el.  The path tests run against a
;; temporary directory.  The command test stubs the org-excalidraw entry
;; points with `cl-letf', so org-excalidraw itself stays unloaded.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-org-excalidraw-name-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-org-excalidraw-name)

(defvar org-excalidraw-default-directory)
(defvar org-excalidraw-default-template)

(defmacro my-org-excalidraw-name-test-with-directory (directory &rest body)
  "Bind DIRECTORY to a fresh temporary directory while BODY runs."
  (declare (indent 1))
  `(let ((,directory (file-name-as-directory
                      (make-temp-file "excalidraw-name-test" t))))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,directory t))))

(ert-deftest my-org-excalidraw-name-test-stem-uses-file-base-name ()
  (should (equal (my-org-excalidraw-name-stem "/org/daily/2026-10-25.org" nil)
                 "2026-10-25")))

(ert-deftest my-org-excalidraw-name-test-stem-appends-label ()
  (should (equal (my-org-excalidraw-name-stem "/org/2026-10-25.org" "flow")
                 "2026-10-25-flow")))

(ert-deftest my-org-excalidraw-name-test-stem-replaces-unsafe-characters ()
  (should (equal (my-org-excalidraw-name-stem "/org/a.org" " robot arm/v2 ")
                 "a-robot-arm-v2")))

(ert-deftest my-org-excalidraw-name-test-stem-ignores-blank-label ()
  (should (equal (my-org-excalidraw-name-stem "/org/a.org" "  ") "a")))

(ert-deftest my-org-excalidraw-name-test-unused-path-starts-at-one ()
  (my-org-excalidraw-name-test-with-directory directory
    (should (equal (my-org-excalidraw-name-unused-path directory "a" nil)
                   (concat directory "a-1.excalidraw")))))

(ert-deftest my-org-excalidraw-name-test-unused-path-skips-taken-numbers ()
  (my-org-excalidraw-name-test-with-directory directory
    (write-region "" nil (concat directory "a-1.excalidraw"))
    (write-region "" nil (concat directory "a-2.excalidraw"))
    (should (equal (my-org-excalidraw-name-unused-path directory "a" nil)
                   (concat directory "a-3.excalidraw")))))

(ert-deftest my-org-excalidraw-name-test-unused-path-tries-bare-stem-first ()
  (my-org-excalidraw-name-test-with-directory directory
    (should (equal (my-org-excalidraw-name-unused-path directory "a-flow" t)
                   (concat directory "a-flow.excalidraw")))))

(ert-deftest my-org-excalidraw-name-test-unused-path-numbers-taken-bare-stem ()
  (my-org-excalidraw-name-test-with-directory directory
    (write-region "" nil (concat directory "a-flow.excalidraw"))
    (should (equal (my-org-excalidraw-name-unused-path directory "a-flow" t)
                   (concat directory "a-flow-2.excalidraw")))))

(ert-deftest my-org-excalidraw-name-test-source-file-reads-base-buffer ()
  (let* ((visiting-buffer (generate-new-buffer "visiting"))
         (capture-buffer nil))
    (unwind-protect
        (progn
          (with-current-buffer visiting-buffer
            (setq buffer-file-name "/org/daily/2026-10-25.org"))
          (setq capture-buffer
                (make-indirect-buffer visiting-buffer "CAPTURE-2026-10-25.org"))
          (with-current-buffer capture-buffer
            (should (equal (my-org-excalidraw-name-source-file)
                           "/org/daily/2026-10-25.org"))))
      (when (buffer-live-p capture-buffer)
        (kill-buffer capture-buffer))
      (with-current-buffer visiting-buffer
        (setq buffer-file-name nil))
      (kill-buffer visiting-buffer))))

(ert-deftest my-org-excalidraw-name-test-create-drawing-inserts-link ()
  (my-org-excalidraw-name-test-with-directory directory
    (let ((org-excalidraw-default-directory directory)
          (org-excalidraw-default-template "{}")
          (opened-path nil))
      (cl-letf (((symbol-function 'org-excalidraw-link-open)
                 (lambda (path) (setq opened-path path))))
        (with-temp-buffer
          (setq buffer-file-name "/org/daily/2026-10-25.org")
          (my-org-excalidraw-name-create-drawing nil)
          (let ((inserted-text (buffer-string)))
            (setq buffer-file-name nil)
            (should (equal (list inserted-text opened-path)
                           (list (format "[[excalidraw:%s2026-10-25-1.excalidraw]]"
                                         directory)
                                 (concat directory
                                         "2026-10-25-1.excalidraw"))))))))))

(ert-deftest my-org-excalidraw-name-test-create-drawing-writes-template ()
  (my-org-excalidraw-name-test-with-directory directory
    (let ((org-excalidraw-default-directory directory)
          (org-excalidraw-default-template "{}"))
      (cl-letf (((symbol-function 'org-excalidraw-link-open) #'ignore))
        (with-temp-buffer
          (setq buffer-file-name "/org/a.org")
          (my-org-excalidraw-name-create-drawing nil)
          (setq buffer-file-name nil))
        (should (equal (with-temp-buffer
                         (insert-file-contents
                          (concat directory "a-1.excalidraw"))
                         (buffer-string))
                       "{}"))))))

(provide 'my-org-excalidraw-name-test)

;;; my-org-excalidraw-name-test.el ends here
