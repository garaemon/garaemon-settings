;;; my-vterm-toggle.el --- vterm toggle aware of claude-code-ide and frames -*- lexical-binding: t; -*-

;;; Commentary:
;; A vterm-toggle dispatch that fixes two shortcomings of the stock
;; `vterm-toggle' command for this setup:
;;
;; 1. claude-code-ide sessions run inside vterm buffers, so the stock
;;    toggle happily lands on (or hides) a Claude session.  The
;;    predicates here identify those buffers so the toggle skips them.
;;
;; 2. `vterm-toggle--get-window' only inspects the selected frame.  When
;;    the vterm buffer is visible on another frame, the stock dispatch
;;    falls through to `vterm-toggle-show', whose `pop-to-buffer' path
;;    can select the other frame's window without transferring input
;;    focus; a follow-up toggle then deletes that window.  The dispatch
;;    here detects a vterm window on another visible frame and moves
;;    input focus to it instead.

;;; Code:

(require 'cl-lib)

(declare-function vterm "vterm")
(declare-function vterm-toggle-show "vterm-toggle")
(declare-function vterm-toggle-hide "vterm-toggle")
(declare-function vterm-toggle--get-window "vterm-toggle")
(declare-function vterm-toggle-togglable-buffer-p "vterm-toggle")
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

(defun my-vterm-toggle--get-other-frame-window ()
  "Return a window on another visible frame showing a togglable vterm."
  (cl-find-if (lambda (window)
                (and (not (eq (window-frame window) (selected-frame)))
                     (vterm-toggle-togglable-buffer-p (window-buffer window))))
              (window-list-1 nil nil 'visible)))

(defun my-vterm-toggle (&optional args)
  "Vterm toggle that ignores claude-code-ide session buffers.
When the vterm is visible on another frame and the selected frame has
no vterm window, move input focus to that frame instead of hiding or
re-showing the buffer.  When the user is currently inside a
claude-code-ide buffer, do not hide it; instead pop up another vterm
\(or spawn a new one) so the claude-code-ide window stays out of the
way.  Optional argument ARGS is passed through as the prefix argument."
  (interactive "P")
  (let ((other-frame-window (and (not (vterm-toggle--get-window))
                                 (my-vterm-toggle--get-other-frame-window))))
    (cond
     (other-frame-window
      (select-frame-set-input-focus (window-frame other-frame-window))
      (select-window other-frame-window))
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
        (vterm-toggle-show))))))

(provide 'my-vterm-toggle)
;;; my-vterm-toggle.el ends here
