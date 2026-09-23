;;; my-grip-refresh.el --- Debounced grip preview refresh -*- lexical-binding: t; -*-

;;; Commentary:
;; With `grip-real-time-refresh', grip-mode rewrites the preview file on
;; every buffer change, and go-grip tells the browser to reload after
;; each write.  go-grip (through github.com/aarol/reload) delivers the
;; reload only to a page whose WebSocket is already open.  A write that
;; lands while the page is still reloading from the previous one gets
;; dropped, so the preview stays one edit behind until the next change.
;;
;; `my-grip-refresh-defer' wraps `grip--refresh' and writes once after
;; Emacs has been idle for `my-grip-refresh-idle-delay' seconds.  Two
;; writes are then far enough apart for the page to reconnect in between.

;;; Code:

(defgroup my-grip-refresh nil
  "Debounced preview refresh for grip-mode."
  :group 'grip)

(defcustom my-grip-refresh-idle-delay 0.5
  "Seconds of idle time before the preview file is rewritten.
A local go-grip page reconnects in roughly 300 ms, so values below
that bring back the dropped reloads."
  :type 'number
  :group 'my-grip-refresh)

(defvar-local my-grip-refresh--timer nil
  "Idle timer that runs the pending preview refresh of this buffer.")

(defun my-grip-refresh-defer (refresh &rest args)
  "Postpone REFRESH with ARGS until Emacs goes idle.
Meant as `:around' advice for `grip--refresh'.  A new call replaces
the refresh that the current buffer still has pending."
  (when (timerp my-grip-refresh--timer)
    (cancel-timer my-grip-refresh--timer))
  (setq my-grip-refresh--timer
        (run-with-idle-timer my-grip-refresh-idle-delay nil
                             #'my-grip-refresh--run
                             (current-buffer) refresh args)))

(defun my-grip-refresh--run (buffer refresh args)
  "Apply REFRESH to ARGS in BUFFER if its preview is still running."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq my-grip-refresh--timer nil)
      ;; `grip-mode' is off once the preview stops, and the refresh would
      ;; then recreate the temporary file that grip-mode just deleted.
      (when (bound-and-true-p grip-mode)
        (apply refresh args)))))

(provide 'my-grip-refresh)

;;; my-grip-refresh.el ends here
