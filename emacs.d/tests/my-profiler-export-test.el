;;; my-profiler-export-test.el --- Tests for profiler report export -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for `my-profiler-export'.  Each test profiles a small busy loop
;; so that a real report buffer exists.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert -l tests/my-profiler-export-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'profiler)
(require 'my-profiler-export)

(defun my-profiler-export-test--busy-work ()
  "Burn CPU long enough for the sampler to record a few stacks."
  (let ((deadline (+ (float-time) 0.3)))
    (while (< (float-time) deadline)
      (make-list 1000 nil))))

(defun my-profiler-export-test--make-report-buffer ()
  "Return a fresh, collapsed CPU profiler report buffer."
  (profiler-reset)
  (profiler-start 'cpu)
  (my-profiler-export-test--busy-work)
  (profiler-stop)
  (profiler-report)
  (cl-find-if (lambda (buf)
                (string-prefix-p "*CPU-Profiler-Report" (buffer-name buf)))
              (buffer-list)))

(defmacro my-profiler-export-test--with-report (buffer-var &rest body)
  "Run BODY with BUFFER-VAR bound to a profiler report buffer."
  (declare (indent 1))
  `(let ((,buffer-var (my-profiler-export-test--make-report-buffer)))
     (unwind-protect (progn ,@body)
       (when (buffer-live-p ,buffer-var)
         (kill-buffer ,buffer-var)))))

(ert-deftest should_return_more_lines_when_report_is_expanded ()
  (my-profiler-export-test--with-report report
    (let* ((collapsed-line-count
            (with-current-buffer report (count-lines (point-min) (point-max))))
           (expanded-text (my-profiler-export-expanded-text report))
           (expanded-line-count (length (split-string expanded-text "\n" t))))
      (should (> expanded-line-count collapsed-line-count)))))

(ert-deftest should_not_contain_collapse_marker_when_report_is_expanded ()
  (my-profiler-export-test--with-report report
    (should-not (string-match-p
                 "\\+ "
                 (my-profiler-export-expanded-text report)))))

(ert-deftest should_mention_busy_function_when_report_is_expanded ()
  (my-profiler-export-test--with-report report
    (should (string-match-p
             "my-profiler-export-test--busy-work"
             (my-profiler-export-expanded-text report)))))

(ert-deftest should_put_expanded_text_on_kill_ring_when_copying ()
  (my-profiler-export-test--with-report report
    (let ((kill-ring nil))
      (with-current-buffer report
        (my-profiler-export-copy-report))
      (should (string-match-p "my-profiler-export-test--busy-work"
                              (car kill-ring))))))

(defun my-profiler-export-test--kill-report-buffers ()
  "Kill every profiler report buffer."
  (dolist (buf (buffer-list))
    (when (provided-mode-derived-p
           (buffer-local-value 'major-mode buf) 'profiler-report-mode)
      (kill-buffer buf))))

(defun my-profiler-export-test--profile-cpu-and-memory ()
  "Profile a busy loop and open both the CPU and the memory report."
  (my-profiler-export-test--kill-report-buffers)
  (profiler-reset)
  (profiler-start 'cpu+mem)
  (my-profiler-export-test--busy-work)
  (profiler-stop)
  (profiler-report))

(ert-deftest should_copy_cpu_and_memory_reports_when_called_outside_report ()
  (my-profiler-export-test--profile-cpu-and-memory)
  (unwind-protect
      (let ((kill-ring nil))
        (with-temp-buffer (my-profiler-export-copy-report))
        (should (string-match-p "CPU-Profiler-Report" (car kill-ring)))
        (should (string-match-p "Memory-Profiler-Report" (car kill-ring))))
    (my-profiler-export-test--kill-report-buffers)))

(ert-deftest should_copy_cpu_and_memory_reports_when_called_inside_report ()
  (my-profiler-export-test--profile-cpu-and-memory)
  (unwind-protect
      (let ((kill-ring nil))
        (with-current-buffer
            (cl-find-if (lambda (buf)
                          (string-prefix-p "*CPU-Profiler-Report"
                                           (buffer-name buf)))
                        (buffer-list))
          (my-profiler-export-copy-report))
        (should (string-match-p "Memory-Profiler-Report" (car kill-ring))))
    (my-profiler-export-test--kill-report-buffers)))

(ert-deftest should_signal_user_error_when_no_report_buffer_exists ()
  (dolist (buf (buffer-list))
    (when (provided-mode-derived-p
           (buffer-local-value 'major-mode buf) 'profiler-report-mode)
      (kill-buffer buf)))
  (with-temp-buffer
    (should-error (my-profiler-export-copy-report) :type 'user-error)))

(provide 'my-profiler-export-test)
;;; my-profiler-export-test.el ends here
