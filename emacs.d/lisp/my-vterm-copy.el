;;; my-vterm-copy.el --- region-only copy commands for vterm -*- lexical-binding: t; -*-

;;; Commentary:
;; `C-w' and `M-w' cannot copy just the selected region in a vterm
;; buffer.  Both of its states get in the way:
;;
;; 1. In `vterm-copy-mode', `vterm--enter-copy-mode' drops the local
;;    keymap, so `C-w' and `M-w' reach the global `kill-region' and
;;    `kill-ring-save'.  Those commands act on the region between mark
;;    and point even when the region is inactive, and the mark is often
;;    left over from an earlier `vterm-copy-mode-done', which parks it at
;;    the beginning of a line.  The copy then spans the whole line
;;    instead of the selection.
;; 2. Outside `vterm-copy-mode', `vterm-mode-map' binds every key that is
;;    not listed in `vterm-keymap-exceptions' to `vterm--self-insert'.
;;    `C-w' and `M-w' therefore go straight to the shell, and a region
;;    selected with the mouse cannot be copied with them at all.
;;
;; The commands here copy exactly the active region and refuse to copy
;; anything when no region is active.  Unlike the tmux `C-w' this
;; configuration imitates, they stay in `vterm-copy-mode' so that a
;; single visit to copy mode can yield several copies.

;;; Code:

(declare-function vterm-send-key "vterm"
                  (key &optional shift meta ctrl accept-proc-output))

(defun my-vterm-copy-region ()
  "Copy the active region to the kill ring, staying in `vterm-copy-mode'.
Signal an error when no region is active.  `vterm-copy-mode-done' copies
the whole current line in that case, which is almost never the intended
copy."
  (interactive)
  (unless (use-region-p)
    (user-error "No active region to copy"))
  (kill-ring-save (region-beginning) (region-end))
  (deactivate-mark))

(defun my-vterm-copy-region-or-send-key ()
  "Copy the active region, or send the invoking key to libvterm.
Without a region the key keeps its terminal meaning: `C-w' still
triggers the readline `unix-word-rubout'."
  (interactive)
  (if (use-region-p)
      (my-vterm-copy-region)
    (let ((modifiers (event-modifiers last-command-event)))
      (vterm-send-key (char-to-string (event-basic-type last-command-event))
                      (and (memq 'shift modifiers) t)
                      (and (memq 'meta modifiers) t)
                      (and (memq 'control modifiers) t)
                      t))))

(provide 'my-vterm-copy)
;;; my-vterm-copy.el ends here
