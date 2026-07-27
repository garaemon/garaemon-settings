;;; my-vterm-toggle.el --- vterm toggle aware of claude-code-ide and frames -*- lexical-binding: t; -*-

;;; Commentary:
;; A vterm-toggle dispatch that fixes shortcomings of the stock
;; `vterm-toggle' command for this setup:
;;
;; 1. claude-code-ide sessions run inside vterm buffers, so the stock
;;    toggle happily lands on (or hides) a Claude session.  The
;;    predicates here identify those buffers; init-prog.el registers
;;    them in `vterm-toggle-togglable-buffer-functions' so vterm-toggle
;;    skips them everywhere.
;;
;; 2. The stock dispatch hides the vterm whenever a vterm window is
;;    visible on the selected frame, even when focus is on another
;;    window, and it never looks at other frames at all.  The dispatch
;;    here implements a three-state machine instead:
;;    - focus on the vterm: hide it
;;    - vterm visible elsewhere (another window or another frame):
;;      move input focus to it
;;    - vterm not visible: show it
;;
;; 3. `vterm-toggle-hide' with the `delete-window' hide method calls
;;    `delete-window' whenever `window-deletable-p' is non-nil, but that
;;    predicate returns the symbol `frame' for a frame's sole ordinary
;;    window, and `delete-window' then signals "Attempt to delete
;;    minibuffer or sole ordinary window".  The hide path here deletes
;;    the frame in that case.

;;; Code:

(require 'cl-lib)

(declare-function vterm "vterm")
(declare-function vterm-toggle-show "vterm-toggle")
(declare-function vterm-toggle-hide "vterm-toggle")
(declare-function vterm-toggle--get-window "vterm-toggle")
(declare-function vterm-toggle-togglable-buffer-p "vterm-toggle")
(declare-function claude-code-ide--session-buffer-p "claude-code-ide")

(defvar vterm-buffer-name)
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

(defun my-vterm-toggle--hide-focused-vterm ()
  "Hide the vterm window that holds input focus.
When the vterm is the sole ordinary window of its frame,
`window-deletable-p' returns the symbol `frame' and `vterm-toggle-hide'
would signal an error from `delete-window'; delete the frame instead.
On the last visible frame `window-deletable-p' returns nil and
`vterm-toggle-hide' safely falls back to burying the buffer."
  (if (eq (window-deletable-p) 'frame)
      (delete-frame)
    (vterm-toggle-hide)))

(defun my-vterm-toggle (&optional args)
  "Toggle the vterm as a three-state dispatch.
Hide the vterm when focus is already on it, move focus to a visible
vterm window (on this or another frame) otherwise, and show the vterm
when it is not visible anywhere.  claude-code-ide session buffers are
not togglable, so the toggle never hides or lands on them.  With
prefix argument ARGS other than 1 inside a vterm, spawn a new vterm;
with prefix argument 4 while no vterm is visible, toggle
`vterm-toggle-fullscreen-p' for this show."
  (interactive "P")
  (let* ((focused-on-vterm (vterm-toggle-togglable-buffer-p (current-buffer)))
         (current-frame-window (and (not focused-on-vterm)
                                    (vterm-toggle--get-window)))
         (other-frame-window (and (not focused-on-vterm)
                                  (not current-frame-window)
                                  (my-vterm-toggle--get-other-frame-window))))
    (cond
     (focused-on-vterm
      (if (equal (prefix-numeric-value args) 1)
          (my-vterm-toggle--hide-focused-vterm)
        (vterm vterm-buffer-name)))
     (current-frame-window
      (select-window current-frame-window))
     (other-frame-window
      (select-frame-set-input-focus (window-frame other-frame-window))
      (select-window other-frame-window))
     ((equal (prefix-numeric-value args) 4)
      (let ((vterm-toggle-fullscreen-p
             (not vterm-toggle-fullscreen-p)))
        (vterm-toggle-show)))
     (t
      (vterm-toggle-show)))))

(provide 'my-vterm-toggle)
;;; my-vterm-toggle.el ends here
