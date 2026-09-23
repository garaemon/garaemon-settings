;;; my-grip-refresh-test.el --- Tests for the debounced grip preview refresh -*- lexical-binding: t; -*-

;;; Commentary:
;; Regression tests for `my-grip-refresh-defer', the around advice that
;; batches grip-mode's per-keystroke preview writes.  go-grip lost the
;; last reload of a typing burst and left the browser one edit behind.
;;
;; The tests call the advice with a recording stub in place of
;; `grip--refresh' and fire the pending idle timer by hand, so neither
;; grip-mode nor a real idle period is needed.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert -l tests/my-grip-refresh-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'my-grip-refresh)

(defvar grip-mode)

(defmacro my-grip-refresh-test--with-buffer (&rest body)
  "Run BODY in a temporary buffer where `grip-mode' is on.
BODY can read the number of stub refreshes from `refresh-count' and
pass `record-refresh' to the advice as the original function."
  (declare (indent 0))
  `(let* ((refresh-count 0)
          (record-refresh (lambda (&rest _) (setq refresh-count (1+ refresh-count)))))
     (with-temp-buffer
       (setq-local grip-mode t)
       (unwind-protect
           (progn ,@body)
         (when (timerp my-grip-refresh--timer)
           (cancel-timer my-grip-refresh--timer))))))

(defun my-grip-refresh-test--fire-pending-timer ()
  "Run the refresh that the current buffer has scheduled."
  (let ((timer my-grip-refresh--timer))
    (cancel-timer timer)
    (apply (timer--function timer) (timer--args timer))))

(ert-deftest my-grip-refresh-should-defer-refresh-until-idle ()
  (my-grip-refresh-test--with-buffer
    (my-grip-refresh-defer record-refresh)
    (should (= refresh-count 0))))

(ert-deftest my-grip-refresh-should-schedule-an-idle-timer ()
  (my-grip-refresh-test--with-buffer
    (my-grip-refresh-defer record-refresh)
    (should (timerp my-grip-refresh--timer))))

(ert-deftest my-grip-refresh-should-refresh-once-per-burst ()
  (my-grip-refresh-test--with-buffer
    (dotimes (_ 5)
      (my-grip-refresh-defer record-refresh))
    (my-grip-refresh-test--fire-pending-timer)
    (should (= refresh-count 1))))

(ert-deftest my-grip-refresh-should-clear-timer-after-refresh ()
  (my-grip-refresh-test--with-buffer
    (my-grip-refresh-defer record-refresh)
    (my-grip-refresh-test--fire-pending-timer)
    (should (null my-grip-refresh--timer))))

(ert-deftest my-grip-refresh-should-skip-refresh-when-grip-mode-is-off ()
  (my-grip-refresh-test--with-buffer
    (my-grip-refresh-defer record-refresh)
    (setq-local grip-mode nil)
    (my-grip-refresh-test--fire-pending-timer)
    (should (= refresh-count 0))))

(ert-deftest my-grip-refresh-should-skip-refresh-when-buffer-is-killed ()
  (let* ((refresh-count 0)
         (record-refresh (lambda (&rest _) (setq refresh-count (1+ refresh-count))))
         (buffer (generate-new-buffer " *grip-refresh-test*"))
         (timer (with-current-buffer buffer
                  (setq-local grip-mode t)
                  (my-grip-refresh-defer record-refresh)
                  my-grip-refresh--timer)))
    (cancel-timer timer)
    (kill-buffer buffer)
    (apply (timer--function timer) (timer--args timer))
    (should (= refresh-count 0))))

(provide 'my-grip-refresh-test)

;;; my-grip-refresh-test.el ends here
