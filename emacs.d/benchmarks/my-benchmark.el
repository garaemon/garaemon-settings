;;; my-benchmark.el --- Timing harness for the Emacs Lisp modules -*- lexical-binding: t; -*-

;;; Commentary:
;; A scenario registry that times each scenario and renders the result as a
;; Markdown table.  The CI workflow runs the whole registry twice, once
;; against the base branch and once against the pull request, then posts the
;; comparison as a comment.
;;
;; A scenario that cannot run reports nothing rather than zero: the module it
;; measures may not exist on the base branch, and a missing measurement must
;; not read as an instant one.  Such a scenario renders as `n/a'.
;;
;; Run the registry by hand with:
;;
;;   emacs -Q --batch -L lisp -L benchmarks \
;;     -l my-consult-benchmark.el -f my-benchmark-run-batch results.json
;;
;; and compare two result files with:
;;
;;   emacs -Q --batch -L benchmarks -l my-benchmark.el \
;;     -f my-benchmark-render-batch base.json head.json

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)

(defconst my-benchmark-default-iterations 9
  "Times each scenario runs when the caller names no other count.
Roughly one run in five stalls on a garbage collection that doubles the
measurement, so the sample has to be wide enough for the median to step over
those runs.  Nine keeps the median within about 5% across processes.")

(defvar my-benchmark-scenarios nil
  "Registered scenarios, oldest first.
Each entry is a plist as described in `my-benchmark-define'.")

(defun my-benchmark-define (name &rest keys)
  "Register the benchmark scenario NAME, a string used as the table row label.

KEYS accepts:

:thunk        Function of no arguments.  Only this call is timed.
:setup        Function of no arguments, called once before the timed runs.
              Build fixtures here so their cost stays out of the measurement.
:available-p  Predicate.  When it returns nil the scenario is skipped and
              reports no timing, which is how a scenario whose module the
              base branch lacks stays out of the comparison."
  (setq my-benchmark-scenarios
        (append my-benchmark-scenarios (list (append (list :name name) keys)))))

(defun my-benchmark-median (samples)
  "Return the median of SAMPLES, a list of numbers, or nil when it is empty.
The median resists the occasional slow run of a shared CI machine, which a
mean does not."
  (when samples
    (let* ((sorted (sort (copy-sequence samples) #'<))
           (count (length sorted))
           (middle (/ count 2)))
      (if (cl-oddp count)
          (nth middle sorted)
        (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2.0)))))

(defun my-benchmark--available-p (scenario)
  "Return non-nil when SCENARIO can run in this Emacs."
  (let ((predicate (plist-get scenario :available-p)))
    (or (null predicate) (funcall predicate))))

(defun my-benchmark--measure (scenario iterations)
  "Return the median milliseconds of SCENARIO over ITERATIONS timed runs."
  (when-let* ((setup (plist-get scenario :setup)))
    (funcall setup))
  (let ((thunk (plist-get scenario :thunk)))
    (my-benchmark-median
     (cl-loop repeat iterations
              collect (* 1000 (car (benchmark-run 1 (funcall thunk))))))))

(defun my-benchmark--try-measure (scenario iterations)
  "Return the median milliseconds of SCENARIO, or nil when it cannot run.
A scenario that signals is reported rather than raised: the base branch of a
pull request may lack what the scenario touches, and losing one row beats
losing the whole comparison."
  (when (my-benchmark--available-p scenario)
    (condition-case err
        (my-benchmark--measure scenario iterations)
      (error
       (message "benchmark scenario %s failed: %s"
                (plist-get scenario :name) (error-message-string err))
       nil))))

(defun my-benchmark-run-all (&optional iterations)
  "Time every available scenario and return an alist of name to milliseconds.
ITERATIONS defaults to `my-benchmark-default-iterations'.  Scenarios keep
their registration order, and the ones that cannot run are absent from the
result rather than present with a zero."
  (let ((iterations (or iterations my-benchmark-default-iterations)))
    (cl-loop for scenario in my-benchmark-scenarios
             for milliseconds = (my-benchmark--try-measure scenario iterations)
             when milliseconds
             collect (cons (plist-get scenario :name) milliseconds))))

(defun my-benchmark--format-milliseconds (value)
  "Format VALUE for a table cell, or return \"n/a\" when VALUE is nil."
  (if (numberp value) (format "%.1f ms" value) "n/a"))

(defun my-benchmark--format-delta (base head)
  "Format the change from BASE to HEAD as a signed percentage.
Return \"n/a\" unless both sides ran and BASE is large enough to divide by."
  (if (and (numberp base) (numberp head) (> base 0.05))
      (format "%+.1f%%" (* 100 (/ (- head base) base)))
    "n/a"))

(defun my-benchmark--comparison-order (base head)
  "Return the scenario names of BASE and HEAD, head order first."
  (append (mapcar #'car head)
          (seq-remove (lambda (name) (assoc name head)) (mapcar #'car base))))

(defun my-benchmark-render-comparison (base head)
  "Return a Markdown table comparing the BASE and HEAD result alists.
Both alists map a scenario name to its median milliseconds.  A scenario the
pull request adds or removes exists on one side only and renders as `n/a'."
  (string-join
   (append
    (list "| scenario | base | head | delta |"
          "|---|---:|---:|---:|")
    (mapcar (lambda (name)
              (let ((base-time (cdr (assoc name base)))
                    (head-time (cdr (assoc name head))))
                (format "| %s | %s | %s | %s |"
                        name
                        (my-benchmark--format-milliseconds base-time)
                        (my-benchmark--format-milliseconds head-time)
                        (my-benchmark--format-delta base-time head-time))))
            (my-benchmark--comparison-order base head)))
   "\n"))

(defun my-benchmark-write-results (results path)
  "Write RESULTS, an alist of name to milliseconds, to PATH as JSON.
`json-encode-alist' rather than `json-encode' so that a run in which every
scenario was skipped writes an empty object instead of `null'."
  (with-temp-file path
    (insert (json-encode-alist results) "\n")))

(defun my-benchmark-read-results (path)
  "Read the JSON benchmark results at PATH into an alist of name to number."
  (with-temp-buffer
    (insert-file-contents path)
    (let ((json-object-type 'alist)
          (json-key-type 'string))
      (json-read))))

(defun my-benchmark-run-batch ()
  "Run every registered scenario and write the results to the first argument.
Intended for `emacs --batch -f my-benchmark-run-batch OUTPUT.json'."
  (let ((output (or (pop command-line-args-left) "benchmark.json"))
        (results (my-benchmark-run-all)))
    (my-benchmark-write-results results output)
    (message "%s" (my-benchmark-render-comparison nil results))))

(defun my-benchmark-render-batch ()
  "Print the comparison of the two result files named on the command line.
Intended for `emacs --batch -f my-benchmark-render-batch BASE.json HEAD.json'."
  (let* ((base (my-benchmark-read-results (pop command-line-args-left)))
         (head (my-benchmark-read-results (pop command-line-args-left))))
    (princ (my-benchmark-render-comparison base head))
    (princ "\n")))

(provide 'my-benchmark)
;;; my-benchmark.el ends here
