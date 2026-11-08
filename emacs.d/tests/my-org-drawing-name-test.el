;;; my-org-drawing-name-test.el --- Tests for drawing file names -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-drawing-name.el.  The path tests run against a
;; temporary directory.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-org-drawing-name-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'my-org-drawing-name)

(defmacro my-org-drawing-name-test-with-directory (directory &rest body)
  "Bind DIRECTORY to a fresh temporary directory while BODY runs."
  (declare (indent 1))
  `(let ((,directory (file-name-as-directory
                      (make-temp-file "drawing-name-test" t))))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,directory t))))

(ert-deftest my-org-drawing-name-test-stem-uses-file-base-name ()
  (should (equal (my-org-drawing-name-stem "/org/daily/2026-10-25.org" nil)
                 "2026-10-25")))

(ert-deftest my-org-drawing-name-test-stem-appends-label ()
  (should (equal (my-org-drawing-name-stem "/org/2026-10-25.org" "flow")
                 "2026-10-25-flow")))

(ert-deftest my-org-drawing-name-test-stem-replaces-unsafe-characters ()
  (should (equal (my-org-drawing-name-stem "/org/a.org" " robot arm/v2 ")
                 "a-robot-arm-v2")))

(ert-deftest my-org-drawing-name-test-stem-ignores-blank-label ()
  (should (equal (my-org-drawing-name-stem "/org/a.org" "  ") "a")))

(ert-deftest my-org-drawing-name-test-unused-path-starts-at-one ()
  (my-org-drawing-name-test-with-directory directory
    (should (equal (my-org-drawing-name-unused-path directory "a" nil ".excalidraw")
                   (concat directory "a-1.excalidraw")))))

(ert-deftest my-org-drawing-name-test-unused-path-skips-taken-numbers ()
  (my-org-drawing-name-test-with-directory directory
    (write-region "" nil (concat directory "a-1.excalidraw"))
    (write-region "" nil (concat directory "a-2.excalidraw"))
    (should (equal (my-org-drawing-name-unused-path directory "a" nil ".excalidraw")
                   (concat directory "a-3.excalidraw")))))

(ert-deftest my-org-drawing-name-test-unused-path-tries-bare-stem-first ()
  (my-org-drawing-name-test-with-directory directory
    (should (equal (my-org-drawing-name-unused-path directory "a-flow" t ".excalidraw")
                   (concat directory "a-flow.excalidraw")))))

(ert-deftest my-org-drawing-name-test-unused-path-numbers-taken-bare-stem ()
  (my-org-drawing-name-test-with-directory directory
    (write-region "" nil (concat directory "a-flow.excalidraw"))
    (should (equal (my-org-drawing-name-unused-path directory "a-flow" t ".excalidraw")
                   (concat directory "a-flow-2.excalidraw")))))

(ert-deftest my-org-drawing-name-test-source-file-reads-base-buffer ()
  (let* ((visiting-buffer (generate-new-buffer "visiting"))
         (capture-buffer nil))
    (unwind-protect
        (progn
          (with-current-buffer visiting-buffer
            (setq buffer-file-name "/org/daily/2026-10-25.org"))
          (setq capture-buffer
                (make-indirect-buffer visiting-buffer "CAPTURE-2026-10-25.org"))
          (with-current-buffer capture-buffer
            (should (equal (my-org-drawing-name-source-file)
                           "/org/daily/2026-10-25.org"))))
      (when (buffer-live-p capture-buffer)
        (kill-buffer capture-buffer))
      (with-current-buffer visiting-buffer
        (setq buffer-file-name nil))
      (kill-buffer visiting-buffer))))

(ert-deftest my-org-drawing-name-test-unused-path-uses-given-extension ()
  (my-org-drawing-name-test-with-directory directory
    (should (equal (my-org-drawing-name-unused-path directory "a" nil ".drawio.svg")
                   (concat directory "a-1.drawio.svg")))))

(ert-deftest my-org-drawing-name-test-new-path-numbers-unlabeled-drawing ()
  (my-org-drawing-name-test-with-directory directory
    (should (equal (my-org-drawing-name-new-path
                    "/org/2026-10-25.org" nil directory ".drawio.svg")
                   (concat directory "2026-10-25-1.drawio.svg")))))

(ert-deftest my-org-drawing-name-test-new-path-tries-bare-labeled-name ()
  (my-org-drawing-name-test-with-directory directory
    (should (equal (my-org-drawing-name-new-path
                    "/org/2026-10-25.org" "flow" directory ".drawio.svg")
                   (concat directory "2026-10-25-flow.drawio.svg")))))

(provide 'my-org-drawing-name-test)

;;; my-org-drawing-name-test.el ends here
