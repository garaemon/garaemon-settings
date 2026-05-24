;;; profile-org-agenda.el --- Profile org-agenda-quick -*- lexical-binding: t -*-

;;; Commentary:
;; Batch-mode profiler for the same code path that
;; `org-agenda-quick' triggers, so we can find what is still slow.
;;
;; Run with:
;;   /Applications/Emacs.app/Contents/MacOS/Emacs --batch \
;;     -l ~/.emacs.d/init.el \
;;     -l scripts/profile-org-agenda.el
;;
;; Outputs:
;;   /tmp/org-agenda-profile-bench.txt   per-phase wall-clock timings
;;   /tmp/org-agenda-profile-cold.txt    CPU profile, cold run (no buffers)
;;   /tmp/org-agenda-profile-warm.txt    CPU profile, warm run (buffers cached)

;;; Code:

(require 'cl-lib)
(require 'benchmark)
(require 'profiler)
(require 'org)
(require 'org-agenda)

(defvar profile-org-agenda-output-dir "/tmp"
  "Directory where profile reports are written.")

;; --- Helpers ---------------------------------------------------------------

(defun profile-org-agenda--kill-org-buffers ()
  "Kill every Org-mode buffer to simulate a cold run."
  (let ((killed 0))
    (dolist (buf (buffer-list))
      (when (and (buffer-live-p buf)
                 (buffer-file-name buf)
                 (not (buffer-modified-p buf))
                 (with-current-buffer buf (derived-mode-p 'org-mode)))
        (kill-buffer buf)
        (cl-incf killed)))
    killed))

(defmacro profile-org-agenda--with-quick-bindings (&rest body)
  "Run BODY with the same suppressions as `define-org-quick-command'."
  (declare (indent 0))
  `(let ((gc-cons-threshold (* 500 1024 1024))
         (org-modules nil)
         (org-element-cache-persistent nil)
         (org-inhibit-startup t)
         (org-startup-with-inline-images nil)
         (org-startup-indented nil)
         (org-startup-with-latex-preview nil)
         (org-startup-folded 'showall)
         (org-agenda-inhibit-startup t)
         (magit-refresh-status-buffer nil)
         (magit-auto-revert-mode nil)
         (vc-handled-backends nil)
         (treesit-auto-langs nil))
     ,@body))

(defun profile-org-agenda--run-target ()
  "Non-interactive equivalent of dispatching `a' in `org-agenda'."
  (org-agenda-list nil))

(defun profile-org-agenda--cleanup-report-buffers ()
  "Kill any leftover profiler report buffers."
  (dolist (buf (buffer-list))
    (when (string-match-p "\\*[CM][PE][UM]-Profiler-Report"
                          (buffer-name buf))
      (kill-buffer buf))))

(defun profile-org-agenda--save-report (path)
  "Generate a fully expanded profiler report and write it to PATH.
`profiler-report' does not return the buffer, so we locate it by
name afterwards."
  (profile-org-agenda--cleanup-report-buffers)
  (profiler-report)
  (let ((report-buf
         (cl-find-if (lambda (buf)
                       (string-prefix-p "*CPU-Profiler-Report"
                                        (buffer-name buf)))
                     (buffer-list))))
    (unless report-buf
      (error "No CPU profiler report buffer was created"))
    (with-current-buffer report-buf
      (goto-char (point-min))
      ;; `profiler-report-expand-entry' with a non-nil arg expands the
      ;; full subtree below the current line. Walking every line guarantees
      ;; we cover branches that only appear after parent expansion.
      (while (not (eobp))
        (ignore-errors (profiler-report-expand-entry t))
        (forward-line 1))
      (let ((coding-system-for-write 'utf-8))
        (write-region (point-min) (point-max) path nil 'silent)))
    (kill-buffer report-buf)))

(defun profile-org-agenda--format-bench (label result)
  "Format LABEL and a `benchmark-run' RESULT triple."
  (format "%-40s %.3fs total / %d GCs / %.3fs in GC"
          label (nth 0 result) (nth 1 result) (nth 2 result)))

;; --- Driver ----------------------------------------------------------------

(defvar profile-org-agenda--bench-lines nil
  "Accumulator for bench output, written to disk before profiling.")

(defun profile-org-agenda--record-line (line)
  "Record LINE in the bench accumulator and echo it."
  (push line profile-org-agenda--bench-lines)
  (message ">> %s" line))

(defun profile-org-agenda--record-bench (label result)
  "Record a `benchmark-run' RESULT under LABEL."
  (profile-org-agenda--record-line
   (profile-org-agenda--format-bench label result)))

(defun profile-org-agenda-run ()
  "Run the full benchmark + profile sweep."
  (setq profile-org-agenda--bench-lines nil)

  (let* ((files-bench
          (benchmark-run 1
            (profile-org-agenda--with-quick-bindings
              (org-agenda-files))))
         (n-files (length (org-agenda-files))))
    (profile-org-agenda--record-line (format "agenda files: %d" n-files))
    (profile-org-agenda--record-bench "(org-agenda-files)" files-bench))

  (let ((killed (profile-org-agenda--kill-org-buffers)))
    (profile-org-agenda--record-line
     (format "killed %d preloaded org buffer(s) before cold run" killed)))

  (let ((cold-bench
         (benchmark-run 1
           (profile-org-agenda--with-quick-bindings
             (profile-org-agenda--run-target)))))
    (profile-org-agenda--record-bench "agenda cold (no buffers)" cold-bench))

  (let ((warm-bench
         (benchmark-run 1
           (profile-org-agenda--with-quick-bindings
             (profile-org-agenda--run-target)))))
    (profile-org-agenda--record-bench "agenda warm (buffers reused)" warm-bench))

  ;; Persist bench summary up-front so it survives a later crash.
  (let* ((bench-text (mapconcat #'identity
                                (nreverse profile-org-agenda--bench-lines)
                                "\n"))
         (bench-path (expand-file-name "org-agenda-profile-bench.txt"
                                       profile-org-agenda-output-dir)))
    (with-temp-file bench-path (insert bench-text "\n"))
    (message "\n=== Bench summary ===\n%s\n" bench-text)
    (message "Wrote bench to %s" bench-path))

    ;; CPU profile: cold
    (message ">> profiling cold run...")
    (profile-org-agenda--kill-org-buffers)
    (garbage-collect)
    (profiler-reset)
    (profiler-start 'cpu)
    (profile-org-agenda--with-quick-bindings
      (profile-org-agenda--run-target))
    (profiler-stop)
    (profile-org-agenda--save-report
     (expand-file-name "org-agenda-profile-cold.txt"
                       profile-org-agenda-output-dir))
    (message ">> wrote cold CPU profile")

    ;; CPU profile: warm
    (message ">> profiling warm run...")
    (garbage-collect)
    (profiler-reset)
    (profiler-start 'cpu)
    (profile-org-agenda--with-quick-bindings
      (profile-org-agenda--run-target))
    (profiler-stop)
    (profile-org-agenda--save-report
     (expand-file-name "org-agenda-profile-warm.txt"
                       profile-org-agenda-output-dir))
    (message ">> wrote warm CPU profile"))

;; Suppress interactive tramp prompts that init.el triggers.
(advice-add 'yes-or-no-p :override (lambda (&rest _) t))
(advice-add 'y-or-n-p :override (lambda (&rest _) t))

(profile-org-agenda-run)
(kill-emacs 0)

(provide 'profile-org-agenda)
;;; profile-org-agenda.el ends here
