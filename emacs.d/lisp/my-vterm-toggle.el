;;; my-vterm-toggle.el --- vterm toggle aware of claude-code-ide -*- lexical-binding: t; -*-

;;; Commentary:
;; A vterm-toggle dispatch that skips claude-code-ide sessions.
;; claude-code-ide sessions run inside vterm buffers, so the stock
;; toggle happily lands on (or hides) a Claude session.  The predicates
;; here identify those buffers so the toggle skips them.

;;; Code:

(require 'cl-lib)

(declare-function vterm "vterm")
(declare-function vterm-toggle-show "vterm-toggle")
(declare-function vterm-toggle-hide "vterm-toggle")
(declare-function vterm-toggle--get-window "vterm-toggle")
(declare-function claude-code-ide--session-buffer-p "claude-code-ide")

(defvar vterm-buffer-name)
(defvar vterm-toggle-hide-method)
(defvar vterm-toggle-fullscreen-p)
(defvar claude-code-ide--processes)

(defun my-vterm-toggle-claude-code-ide-buffer-p (buffer)
  "Return non-nil when BUFFER hosts a claude-code-ide session.
The session-buffer-p check fails for vterm buffers that have been
renamed via `vterm-buffer-name-string', so also consult
`claude-code-ide--processes' to identify them by process-buffer."
  (or (and (fboundp 'claude-code-ide--session-buffer-p)
           (claude-code-ide--session-buffer-p buffer))
      (and (boundp 'claude-code-ide--processes)
           (cl-loop for proc being the hash-values of claude-code-ide--processes
                    when (and (process-live-p proc)
                              (eq (process-buffer proc) buffer))
                    return t))))

(defun my-vterm-toggle-non-claude-code-ide-buffer-p (buffer)
  "Return non-nil when BUFFER is not a claude-code-ide session buffer."
  (not (my-vterm-toggle-claude-code-ide-buffer-p buffer)))

(defun my-vterm-toggle (&optional args)
  "Vterm toggle that ignores claude-code-ide session buffers.
When the user is currently inside a claude-code-ide buffer, do not
hide it; instead pop up another vterm \(or spawn a new one) so the
claude-code-ide window stays out of the way.  Optional argument ARGS
is passed through as the prefix argument."
  (interactive "P")
  (cond
   ((my-vterm-toggle-claude-code-ide-buffer-p (current-buffer))
    (vterm-toggle-show))
   ((or (derived-mode-p 'vterm-mode)
        (and (vterm-toggle--get-window)
             vterm-toggle-hide-method))
    (if (equal (prefix-numeric-value args) 1)
        (vterm-toggle-hide)
      (vterm vterm-buffer-name)))
   ((equal (prefix-numeric-value args) 1)
    (vterm-toggle-show))
   ((equal (prefix-numeric-value args) 4)
    (let ((vterm-toggle-fullscreen-p
           (not vterm-toggle-fullscreen-p)))
      (vterm-toggle-show)))))

(provide 'my-vterm-toggle)
;;; my-vterm-toggle.el ends here
