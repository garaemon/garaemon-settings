;;; my-vterm-toggle.el --- frame-aware vterm toggle -*- lexical-binding: t; -*-

;;; Commentary:
;; A vterm-toggle dispatch that fixes shortcomings of the stock
;; `vterm-toggle' command for this setup:
;;
;; 1. The stock dispatch hides the vterm whenever a vterm window is
;;    visible on the selected frame, even when focus is on another
;;    window, and it never looks at other frames at all.  The dispatch
;;    here implements a three-state machine instead:
;;    - focus on the vterm: hide it
;;    - vterm visible elsewhere (another window or another frame):
;;      move input focus to it
;;    - vterm not visible: show it
;;
;; 2. `vterm-toggle-hide' with the `delete-window' hide method calls
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

(defvar vterm-buffer-name)
(defvar vterm-toggle-fullscreen-p)

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
when it is not visible anywhere.  With prefix argument ARGS other than
1 inside a vterm, spawn a new vterm; with prefix argument 4 while no
vterm is visible, toggle
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
