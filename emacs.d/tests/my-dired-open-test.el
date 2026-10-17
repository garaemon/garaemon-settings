;;; my-dired-open-test.el --- Tests for opening dired files with macOS open -*- lexical-binding: t; -*-

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

(defmacro my-dired-open-test--with-recorded-process (&rest body)
  "Run BODY with `start-process' recording its arguments in `recorded-args'."
  (declare (indent 0))
  `(let ((recorded-args nil))
     (cl-letf (((symbol-function 'start-process)
                (lambda (&rest args) (setq recorded-args args))))
       ,@body)))

(ert-deftest my-dired-open-should-run-open-command ()
  (my-dired-open-test--with-recorded-process
    (my-dired-open-files '("/tmp/a.pdf"))
    (should (equal (nth 2 recorded-args) "open"))))

(ert-deftest my-dired-open-should-pass-all-files ()
  (my-dired-open-test--with-recorded-process
    (my-dired-open-files '("/tmp/a.pdf" "/tmp/b.png"))
    (should (equal (nthcdr 4 recorded-args) '("/tmp/a.pdf" "/tmp/b.png")))))

(ert-deftest my-dired-open-should-end-option-parsing-before-files ()
  ;; A file named "-a" must not be read as an option of `open'.
  (my-dired-open-test--with-recorded-process
    (my-dired-open-files '("-a"))
    (should (equal (nth 3 recorded-args) "--"))))

(ert-deftest my-dired-open-should-expand-relative-paths ()
  (my-dired-open-test--with-recorded-process
    (let ((default-directory "/tmp/"))
      (my-dired-open-files '("a.pdf"))
      (should (equal (nthcdr 4 recorded-args) '("/tmp/a.pdf"))))))

(ert-deftest my-dired-open-should-open-marked-files-from-dired ()
  (my-dired-open-test--with-recorded-process
    (cl-letf (((symbol-function 'dired-get-marked-files)
               (lambda (&rest _) '("/tmp/m1.txt" "/tmp/m2.txt"))))
      (my-dired-open-externally)
      (should (equal (nthcdr 4 recorded-args) '("/tmp/m1.txt" "/tmp/m2.txt"))))))

(provide 'my-dired-open-test)

;;; my-dired-open-test.el ends here
