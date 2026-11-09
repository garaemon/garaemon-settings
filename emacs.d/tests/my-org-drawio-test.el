;;; my-org-drawio-test.el --- Tests for draw.io drawings in Org -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-drawio.el.  The tests write drawings to a
;; temporary directory and stub `my-org-drawio-open-file', so no draw.io
;; process starts.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-org-drawio-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-org-drawio)

(defmacro my-org-drawio-test-with-directory (directory &rest body)
  "Bind DIRECTORY to a fresh temporary directory while BODY runs."
  (declare (indent 1))
  `(let ((,directory (file-name-as-directory
                      (make-temp-file "drawio-test" t))))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,directory t))))

(defun my-org-drawio-test-create-in (directory source-file label)
  "Run `my-org-drawio-create-drawing' with LABEL in a buffer of SOURCE-FILE.
Drawings land in DIRECTORY.  Return the inserted text and the opened path."
  (let ((my-org-drawio-directory directory)
        (opened-path nil))
    (cl-letf (((symbol-function 'my-org-drawio-open-file)
               (lambda (path) (setq opened-path path)))
              ((symbol-function 'my-org-drawio-preview-region) #'ignore))
      (with-temp-buffer
        (setq buffer-file-name source-file)
        (unwind-protect
            (progn
              (my-org-drawio-create-drawing label)
              (list (buffer-string) opened-path))
          (setq buffer-file-name nil))))))

(ert-deftest my-org-drawio-test-link-is-relative-to-source-file ()
  (should (equal (my-org-drawio-link "/org/drawio/a-1.drawio.svg"
                                     "/org/daily/a.org")
                 "[[file:../drawio/a-1.drawio.svg]]")))

(ert-deftest my-org-drawio-test-create-drawing-inserts-relative-link ()
  (my-org-drawio-test-with-directory directory
    (let ((source-file (concat directory "daily/2026-10-25.org")))
      (should (equal (car (my-org-drawio-test-create-in
                           (concat directory "drawio/") source-file nil))
                     "[[file:../drawio/2026-10-25-1.drawio.svg]]")))))

(ert-deftest my-org-drawio-test-create-drawing-opens-new-file ()
  (my-org-drawio-test-with-directory directory
    (should (equal (cadr (my-org-drawio-test-create-in
                          directory (concat directory "a.org") "flow"))
                   (concat directory "a-flow.drawio.svg")))))

(ert-deftest my-org-drawio-test-create-drawing-writes-template ()
  (my-org-drawio-test-with-directory directory
    (my-org-drawio-test-create-in directory (concat directory "a.org") nil)
    (should (equal (with-temp-buffer
                     (insert-file-contents (concat directory "a-1.drawio.svg"))
                     (buffer-string))
                   my-org-drawio-template))))

(ert-deftest my-org-drawio-test-create-drawing-makes-missing-directory ()
  (my-org-drawio-test-with-directory directory
    (my-org-drawio-test-create-in (concat directory "new/")
                                  (concat directory "a.org") nil)
    (should (file-exists-p (concat directory "new/a-1.drawio.svg")))))

(ert-deftest my-org-drawio-test-create-drawing-previews-inserted-link ()
  (my-org-drawio-test-with-directory directory
    (let ((my-org-drawio-directory directory)
          (previewed-text nil))
      (cl-letf (((symbol-function 'my-org-drawio-open-file) #'ignore)
                ((symbol-function 'my-org-drawio-preview-region)
                 (lambda (beg end)
                   (setq previewed-text (buffer-substring beg end)))))
        (with-temp-buffer
          (setq buffer-file-name (concat directory "a.org"))
          (insert "Before ")
          (unwind-protect
              (my-org-drawio-create-drawing nil)
            (setq buffer-file-name nil))))
      (should (equal previewed-text "[[file:a-1.drawio.svg]]")))))

(ert-deftest my-org-drawio-test-template-embeds-diagram ()
  (should (string-match-p "content=\"&lt;mxfile" my-org-drawio-template)))

(ert-deftest my-org-drawio-test-open-file-appends-path-to-command ()
  (let ((my-org-drawio-open-command '("open" "-a" "draw.io"))
        (started-command nil))
    (cl-letf (((symbol-function 'executable-find) (lambda (_name) t))
              ((symbol-function 'make-process)
               (lambda (&rest args)
                 (setq started-command (plist-get args :command)))))
      (my-org-drawio-open-file "/org/drawio/a-1.drawio.svg"))
    (should (equal started-command
                   '("open" "-a" "draw.io" "/org/drawio/a-1.drawio.svg")))))

(ert-deftest my-org-drawio-test-open-file-reports-missing-program ()
  (let ((my-org-drawio-open-command '("no-such-drawio-program")))
    (should-error (my-org-drawio-open-file "/org/a.drawio.svg")
                  :type 'user-error)))

(provide 'my-org-drawio-test)

;;; my-org-drawio-test.el ends here
