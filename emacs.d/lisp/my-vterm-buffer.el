;;; my-vterm-buffer.el --- vterm-only buffer switching -*- lexical-binding: t; -*-

;;; Commentary:
;; `C-x b' is `consult-buffer' here, and it offers every buffer.  Once a
;; few terminals are open, reaching one means typing enough of its name
;; to lift it above every other candidate.  `my-vterm-switch-to-buffer'
;; is the same picker restricted to vterm buffers, so the terminals are
;; the whole candidate list.
;;
;; The buffer list lives in `my-vterm-list-buffers' rather than in the
;; `consult-buffer' source so that tests/my-vterm-buffer-test.el can
;; exercise it without consult, which CI does not install.  Nothing here
;; loads consult or vterm; the consult symbols are resolved when the
;; command runs.

;;; Code:

(require 'seq)

(declare-function consult-buffer "consult" (&optional sources))
(declare-function consult--buffer-pair "consult" (buffer))
(declare-function consult--buffer-state "consult" ())

(defun my-vterm-buffer-p (buffer)
  "Return non-nil when BUFFER runs a terminal.
Modes derived from `vterm-mode' count as terminals too."
  (provided-mode-derived-p (buffer-local-value 'major-mode buffer) 'vterm-mode))

(defun my-vterm-list-buffers ()
  "Return the live vterm buffers, most recently used first."
  (seq-filter #'my-vterm-buffer-p (buffer-list)))

(defvar my-vterm-buffer-source
  `( :name     "Vterm"
     :narrow   ?v
     :category buffer
     :face     consult-buffer
     :history  buffer-name-history
     :state    ,#'consult--buffer-state
     :default  t
     :items    ,(lambda ()
                  (mapcar #'consult--buffer-pair (my-vterm-list-buffers))))
  "`consult-buffer' source that offers vterm buffers only.")

(defun my-vterm-switch-to-buffer ()
  "Switch to a vterm buffer, the way `C-x b' switches to any buffer.
Signal an error when no terminal is running, because an empty picker
would only offer to create a buffer that is not a terminal."
  (interactive)
  (unless (my-vterm-list-buffers)
    (user-error "No vterm buffer"))
  (consult-buffer (list my-vterm-buffer-source)))

(provide 'my-vterm-buffer)
;;; my-vterm-buffer.el ends here
