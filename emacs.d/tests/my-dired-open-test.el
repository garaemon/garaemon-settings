;;; my-dired-open-test.el --- Tests for opening dired files with the OS opener -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for `my-dired-open-externally'.  A recording stub replaces
;; `start-process', so the tests run on any OS without launching
;; applications.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert -l tests/my-dired-open-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-dired-open)

(defmacro my-dired-open-test--with-recorded-processes (&rest body)
  "Run BODY with `start-process' calls collected in `recorded-calls'.
`recorded-calls' lists the calls oldest first."
  (declare (indent 0))
  `(let ((recorded-calls nil))
     (cl-letf (((symbol-function 'start-process)
                (lambda (&rest args) (push args recorded-calls))))
       ,@body
       (setq recorded-calls (nreverse recorded-calls)))))

(ert-deftest my-dired-open-should-use-open-on-macos ()
  (let ((system-type 'darwin))
    (should (equal (my-dired-open-command) "open"))))

(ert-deftest my-dired-open-should-use-xdg-open-on-linux ()
  (let ((system-type 'gnu/linux))
    (should (equal (my-dired-open-command) "xdg-open"))))

(ert-deftest my-dired-open-should-pass-file-to-the-opener ()
  (my-dired-open-test--with-recorded-processes
    (let ((system-type 'gnu/linux))
      (my-dired-open-files '("/tmp/a.pdf")))
    (should (equal (nthcdr 2 (car recorded-calls)) '("xdg-open" "/tmp/a.pdf")))))

(ert-deftest my-dired-open-should-start-one-process-per-file ()
  ;; xdg-open accepts a single file per invocation.
  (my-dired-open-test--with-recorded-processes
    (my-dired-open-files '("/tmp/a.pdf" "/tmp/b.png"))
    (should (= (length recorded-calls) 2))))

(ert-deftest my-dired-open-should-expand-relative-paths ()
  ;; An absolute path also keeps a name such as "-a" from being read as an
  ;; option of the opener.
  (my-dired-open-test--with-recorded-processes
    (let ((default-directory "/tmp/"))
      (my-dired-open-files '("-a")))
    (should (equal (car (last (car recorded-calls))) "/tmp/-a"))))

(ert-deftest my-dired-open-should-open-marked-files-from-dired ()
  (my-dired-open-test--with-recorded-processes
    (cl-letf (((symbol-function 'dired-get-marked-files)
               (lambda (&rest _) '("/tmp/m1.txt" "/tmp/m2.txt"))))
      (my-dired-open-externally))
    (should (equal (mapcar #'car (mapcar #'last recorded-calls))
                   '("/tmp/m1.txt" "/tmp/m2.txt")))))

(provide 'my-dired-open-test)

;;; my-dired-open-test.el ends here
