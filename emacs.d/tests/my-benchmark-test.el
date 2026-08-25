;;; my-benchmark-test.el --- Tests for the benchmark harness -*- lexical-binding: t; -*-

;;; Commentary:
;; The harness reports timings into a pull request comment, so the parts that
;; decide what a reader sees are worth pinning down: the median of a sample,
;; and the Markdown table that compares a base run against a head run.  The
;; timings themselves are not asserted because they are not reproducible.
;;
;; Run with:
;;
;;   emacs -Q --batch -L lisp -L benchmarks -l ert \
;;     -l tests/my-benchmark-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'my-benchmark)

(ert-deftest my-benchmark-median-should-return-the-middle-of-an-odd-sample ()
  (should (equal (my-benchmark-median '(3.0 1.0 2.0)) 2.0)))

(ert-deftest my-benchmark-median-should-average-the-middle-pair-of-an-even-sample ()
  (should (equal (my-benchmark-median '(4.0 1.0 3.0 2.0)) 2.5)))

(ert-deftest my-benchmark-median-should-return-nil-for-an-empty-sample ()
  (should (null (my-benchmark-median '()))))

(ert-deftest my-benchmark-run-should-skip-a-scenario-that-is-unavailable ()
  (let ((my-benchmark-scenarios nil))
    (my-benchmark-define "absent"
                         :available-p (lambda () nil)
                         :thunk (lambda () (error "An unavailable scenario must not run")))
    (should (null (my-benchmark-run-all 1)))))

(ert-deftest my-benchmark-run-should-skip-a-scenario-that-signals-an-error ()
  (let ((my-benchmark-scenarios nil))
    (my-benchmark-define "broken" :thunk (lambda () (error "Boom")))
    (my-benchmark-define "sound" :thunk #'ignore)
    (should (equal (mapcar #'car (my-benchmark-run-all 1)) '("sound")))))

(ert-deftest my-benchmark-run-should-report-a-scenario-that-is-available ()
  (let ((my-benchmark-scenarios nil))
    (my-benchmark-define "present" :thunk #'ignore)
    (let ((results (my-benchmark-run-all 1)))
      (should (equal (mapcar #'car results) '("present")))
      (should (numberp (cdr (assoc "present" results)))))))

(ert-deftest my-benchmark-run-should-report-scenarios-in-registration-order ()
  (let ((my-benchmark-scenarios nil))
    (my-benchmark-define "first" :thunk #'ignore)
    (my-benchmark-define "second" :thunk #'ignore)
    (should (equal (mapcar #'car (my-benchmark-run-all 1)) '("first" "second")))))

(ert-deftest my-benchmark-render-comparison-should-report-a-speedup-as-a-negative-delta ()
  (should (string-match-p
           (regexp-quote "| collect | 200.0 ms | 50.0 ms | -75.0% |")
           (my-benchmark-render-comparison '(("collect" . 200.0)) '(("collect" . 50.0))))))

(ert-deftest my-benchmark-render-comparison-should-report-a-slowdown-as-a-positive-delta ()
  (should (string-match-p
           (regexp-quote "| collect | 50.0 ms | 75.0 ms | +50.0% |")
           (my-benchmark-render-comparison '(("collect" . 50.0)) '(("collect" . 75.0))))))

(ert-deftest my-benchmark-render-comparison-should-mark-a-scenario-missing-from-base ()
  (should (string-match-p
           (regexp-quote "| added | n/a | 10.0 ms | n/a |")
           (my-benchmark-render-comparison nil '(("added" . 10.0))))))

(ert-deftest my-benchmark-render-comparison-should-mark-a-scenario-missing-from-head ()
  (should (string-match-p
           (regexp-quote "| dropped | 10.0 ms | n/a | n/a |")
           (my-benchmark-render-comparison '(("dropped" . 10.0)) nil))))

(ert-deftest my-benchmark-render-comparison-should-list-head-scenarios-before-base-only-ones ()
  (let ((table (my-benchmark-render-comparison '(("dropped" . 1.0) ("kept" . 1.0))
                                               '(("kept" . 1.0)))))
    (should (< (string-search "| kept |" table)
               (string-search "| dropped |" table)))))

(ert-deftest my-benchmark-render-comparison-should-survive-a-zero-baseline ()
  (should (string-match-p
           (regexp-quote "| instant | 0.0 ms | 5.0 ms | n/a |")
           (my-benchmark-render-comparison '(("instant" . 0.0)) '(("instant" . 5.0))))))

(provide 'my-benchmark-test)
;;; my-benchmark-test.el ends here
