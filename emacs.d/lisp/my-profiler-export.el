;;; my-profiler-export.el --- copy fully expanded profiler reports -*- lexical-binding: t; -*-

;;; Commentary:
;; `profiler-report' opens a report whose call trees are collapsed, so
;; the text a coding agent needs is hidden behind `+' markers.  Pasting
;; the buffer as is yields only the top-level entries.
;;
;; `my-profiler-export-copy-report' expands every entry and puts the
;; plain text of all open report buffers (CPU and memory) on the kill
;; ring, separated by their buffer names.  The copy omits lines that
;; show 0%, which only add length without changing the diagnosis.
;; `my-profiler-export-min-percent' raises that threshold.

;;; Code:

(require 'profiler)

(defconst my-profiler-export--report-separator-format "===== %s =====\n"
  "Format of the heading placed before each report in a combined copy.")

(defun my-profiler-export--expand-all-entries ()
  "Expand every call tree entry in the current profiler report buffer.
Walk each line because expanding an entry inserts new lines that may
carry collapsed children of their own."
  (save-excursion
    (goto-char (point-min))
    (while (not (eobp))
      ;; Leaf lines signal an error, which only means nothing is left to
      ;; expand there.
      (ignore-errors (profiler-report-expand-entry t))
      (forward-line 1))))

(defun my-profiler-export-expanded-text (report-buffer)
  "Return the fully expanded text of REPORT-BUFFER.
Expand the entries in REPORT-BUFFER itself so that the visible report
matches the copied text."
  (with-current-buffer report-buffer
    (my-profiler-export--expand-all-entries)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun my-profiler-export--report-buffers ()
  "Return the live profiler report buffers, sorted by name.
The sort puts the CPU report before the memory report."
  (sort (seq-filter (lambda (buf)
                      (provided-mode-derived-p
                       (buffer-local-value 'major-mode buf)
                       'profiler-report-mode))
                    (buffer-list))
        (lambda (a b) (string< (buffer-name a) (buffer-name b)))))

(defun my-profiler-export--select-buffers ()
  "Return every open report buffer, or signal when none is open."
  (or (my-profiler-export--report-buffers)
      (user-error
       "No profiler report buffer found; run `profiler-report' first")))

(defgroup my-profiler-export nil
  "Copy fully expanded profiler reports."
  :group 'profiler)

(defcustom my-profiler-export-min-percent 1
  "Smallest percent a report line needs to appear in the copy.
The profiler rounds its percent column, so the default 1 drops the
lines that show 0%, which stand for under 0.5% of the total.  Raise the
value to shorten the copy further; 0 keeps every line."
  :type 'natnum
  :group 'my-profiler-export)

(defconst my-profiler-export--percent-line-regexp
  "^ *[0-9,]+ +\\([0-9]+\\)% "
  "Match a report line and capture its percent column.")

(defun my-profiler-export--line-below-threshold-p (line min-percent)
  "Return non-nil when LINE shows a percent under MIN-PERCENT."
  (and (string-match my-profiler-export--percent-line-regexp line)
       (< (string-to-number (match-string 1 line)) min-percent)))

(defun my-profiler-export-prune-text (text &optional min-percent)
  "Return TEXT without the report lines under MIN-PERCENT.
MIN-PERCENT defaults to `my-profiler-export-min-percent'.  A child never
exceeds its parent, which makes every descendant of a dropped line a
dropped line too, and the remaining tree stays intact."
  (let ((threshold (or min-percent my-profiler-export-min-percent)))
    (mapconcat #'identity
               (seq-remove (lambda (line)
                             (my-profiler-export--line-below-threshold-p
                              line threshold))
                           (split-string text "\n"))
               "\n")))

(defun my-profiler-export--format-section (report-buffer)
  "Return the pruned, expanded text of REPORT-BUFFER under a heading."
  (concat (format my-profiler-export--report-separator-format
                  (buffer-name report-buffer))
          (my-profiler-export-prune-text
           (my-profiler-export-expanded-text report-buffer))))

;;;###autoload
(defun my-profiler-export-copy-report ()
  "Copy the fully expanded profiler report to the kill ring.
Copy every open report (CPU and memory) with a heading per buffer,
whichever buffer is current."
  (interactive)
  (let* ((buffers (my-profiler-export--select-buffers))
         (text (if (cdr buffers)
                   (mapconcat #'my-profiler-export--format-section buffers "\n")
                 (my-profiler-export-prune-text
                  (my-profiler-export-expanded-text (car buffers))))))
    (kill-new text)
    (message "Copied %d profiler report(s), %d lines"
             (length buffers)
             (length (split-string text "\n" t)))))

(provide 'my-profiler-export)
;;; my-profiler-export.el ends here
