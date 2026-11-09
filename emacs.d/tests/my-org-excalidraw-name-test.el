;;; my-org-excalidraw-name-test.el --- Tests for automatic excalidraw file names -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-excalidraw-name.el.  The tests write drawings to a
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
