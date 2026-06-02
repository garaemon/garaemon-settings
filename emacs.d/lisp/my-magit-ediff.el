;;; my-magit-ediff.el --- Multi-file ediff for Magit -*- lexical-binding: t; -*-

;;; Commentary:
;; Provides functions to ediff all changed files sequentially.
;; When you quit one ediff session, a navigation prompt lets you go
;; to the next/previous file or quit the review.

;;; Code:

(require 'magit)
(require 'ediff)

;;;; State variables

(defvar my-magit-ediff--files nil
  "All files to ediff.")

(defvar my-magit-ediff--current-index 0
  "Current file index (0-based).")

(defvar my-magit-ediff--rev-a nil
  "Revision A for comparison.")

(defvar my-magit-ediff--rev-b nil
  "Revision B for comparison. nil means working tree, `index' means staged.")

(defvar my-magit-ediff--total-count 0
  "Total number of files for progress display.")

(defvar my-magit-ediff--active nil
  "Non-nil when multi-file ediff session is running.")

(defvar my-magit-ediff--temp-buffers nil
  "Temporary revision buffers to kill on navigation or cleanup.")

;; These two buffer locals bridge this generic ediff engine and the
;; `my-forge-ediff-review' layer.  Ediff itself only shows two anonymous
;; buffers side by side; it has no notion of which file each buffer holds
;; or which side (base vs head) it represents.  By stamping the file path
;; and revision onto each revision buffer here, the review layer can derive
;; the (path, line, side) a comment targets: `--buf-file' gives the path,
;; and matching `--buf-rev' against the session's base-rev / head-rev gives
;; the LEFT / RIGHT side required by the GitHub Reviews API.
(defvar-local my-magit-ediff--buf-file nil
  "Repository-relative path of the file shown in this revision buffer.")

(defvar-local my-magit-ediff--buf-rev nil
  "Git revision (commit SHA / `index' / nil) shown in this revision buffer.")

(defvar my-magit-ediff--saved-window-config nil
  "Window configuration captured at session start, restored on cleanup.")

(defvar my-magit-ediff--control-buffer nil
  "The ediff control buffer of the file currently under comparison.
Captured from `ediff-buffers' so callers such as the review sidebar can
quit the active comparison without being inside one of its buffers.")

(defvar my-magit-ediff--pending-index nil
  "File index to open after the current comparison quits, or nil.
Set by `my-magit-ediff-goto-index' so a jump requested while a file is
open is performed once `ediff-quit-hook' has torn that file down.")

;; Extension points for layers built on top of this engine (e.g. the
;; forge review sidebar).  Kept as plain variables/hooks rather than
;; subclasses so the engine stays unaware of any particular consumer.
(defvar my-magit-ediff-navigation-function
  #'my-magit-ediff--prompt-navigation
  "Function called after a file is quit to choose the next action.
Defaults to the built-in `completing-read' prompt.  A consumer may bind
it to keep its own UI (such as a persistent sidebar) in control.")

(defvar my-magit-ediff-start-hook nil
  "Hook run once the first file of a session has been opened.")

(defvar my-magit-ediff-cleanup-hook nil
  "Hook run by `my-magit-ediff--cleanup' before session state is reset.")

;;;; Entry point functions

;;;###autoload
(defun my-magit-ediff-all-unstaged ()
  "Ediff all unstaged files against HEAD sequentially."
  (interactive)
  (let ((files (magit-unstaged-files)))
    (if (null files)
        (message "No unstaged changes.")
      (my-magit-ediff--start files "HEAD" nil))))

;;;###autoload
(defun my-magit-ediff-all-staged ()
  "Ediff all staged files against HEAD sequentially."
  (interactive)
  (let ((files (magit-staged-files)))
    (if (null files)
        (message "No staged changes.")
      (my-magit-ediff--start files "HEAD" 'index))))

;;;###autoload
(defun my-magit-ediff-all-compare (rev-a rev-b)
  "Ediff all changed files between REV-A and REV-B sequentially."
  (interactive
   (let ((rev-a (magit-read-branch-or-commit "Revision A"))
         (rev-b (magit-read-branch-or-commit "Revision B")))
     (list rev-a rev-b)))
  (let ((files (magit-changed-files rev-a rev-b)))
    (if (null files)
        (message "No changes between %s and %s." rev-a rev-b)
      (my-magit-ediff--start files rev-a rev-b))))

;;;; Core engine functions

(defun my-magit-ediff--start (files rev-a rev-b)
  "Initialize state and begin ediff session for FILES between REV-A and REV-B."
  (setq my-magit-ediff--files files
        my-magit-ediff--current-index 0
        my-magit-ediff--rev-a rev-a
        my-magit-ediff--rev-b rev-b
        my-magit-ediff--total-count (length files)
        my-magit-ediff--active t
        my-magit-ediff--saved-window-config (current-window-configuration))
  (my-magit-ediff--hide-side-windows)
  (add-hook 'ediff-quit-hook #'my-magit-ediff--on-quit)
  (my-magit-ediff--open-current)
  (run-hooks 'my-magit-ediff-start-hook))

(defun my-magit-ediff--open-current ()
  "Open ediff for the file at current index."
  (let ((file (nth my-magit-ediff--current-index my-magit-ediff--files)))
    (message "Ediff [%d/%d]: %s"
             (1+ my-magit-ediff--current-index)
             my-magit-ediff--total-count
             file)
    (my-magit-ediff--open-file file)))

;; Workaround for this config's `my-magit-status-side-window' (C-c L) in
;; init-ui.el, which opens magit via `display-buffer-in-side-window'.
;; Side windows carry the `window-side' parameter, and ediff's plain
;; window setup (`delete-other-windows' then `split-window') cannot
;; operate while one is present -- it errors with "Cannot make side
;; window the only window" / "Cannot split side window...".  Hiding the
;; side windows for the duration of the review sidesteps both; the
;; original layout is restored in `my-magit-ediff--cleanup'.  Frames
;; without side windows are unaffected.
(defun my-magit-ediff--hide-side-windows ()
  "Hide any side windows so ediff can take over the whole frame."
  (when (window-with-parameter 'window-side nil nil)
    (window-toggle-side-windows)))

(defun my-magit-ediff--select-content-window ()
  "Select a normal window so ediff never tries to set up in a side window.
A side window (such as the review sidebar) cannot be split or made the
sole window, which would make ediff's plain window setup error out."
  (when (window-parameter (selected-window) 'window-side)
    (let ((normal (seq-find
                   (lambda (window)
                     (not (window-parameter window 'window-side)))
                   (window-list))))
      (when normal
        (select-window normal)))))

(defun my-magit-ediff--capture-side-windows ()
  "Return a spec describing the frame's side windows for later restoration.
Each entry is (BUFFER SIDE SLOT WIDTH) so `my-magit-ediff--restore-side-windows'
can recreate the window in the same slot."
  (let ((spec nil))
    (dolist (window (window-list nil 'no-mini))
      (when (window-parameter window 'window-side)
        (push (list (window-buffer window)
                    (window-parameter window 'window-side)
                    (window-parameter window 'window-slot)
                    (window-total-width window))
              spec)))
    spec))

(defun my-magit-ediff--restore-side-windows (spec)
  "Recreate the side windows captured in SPEC.
SPEC comes from `my-magit-ediff--capture-side-windows'."
  (dolist (entry spec)
    (when (buffer-live-p (nth 0 entry))
      (display-buffer-in-side-window
       (nth 0 entry)
       `((side . ,(nth 1 entry))
         (slot . ,(nth 2 entry))
         (window-width . ,(nth 3 entry))
         (window-parameters . ((no-delete-other-windows . t))))))))

(defun my-magit-ediff--open-file (file)
  "Open ediff for a single FILE using current rev-a/rev-b.
Stores the resulting control buffer in `my-magit-ediff--control-buffer'.

Side windows (the review sidebar) are removed for the duration of ediff's
window setup and recreated afterward.  Ediff's plain setup clears the frame
with `delete-other-windows' before laying out its panes, but that is a no-op
while a side window is present, so the previous file's windows survive and
pile up with every navigation.  Tearing the side windows down lets ediff
start from a single clean window."
  (my-magit-ediff--kill-stale-revision-buffers)
  (let ((side-spec (my-magit-ediff--capture-side-windows)))
    (dolist (window (window-list nil 'no-mini))
      (when (window-parameter window 'window-side)
        (ignore-errors (delete-window window))))
    (my-magit-ediff--select-content-window)
    (delete-other-windows)
    (let ((buf-a (my-magit-ediff--create-revision-buffer
                  file my-magit-ediff--rev-a))
          (buf-b (my-magit-ediff--create-revision-buffer
                  file my-magit-ediff--rev-b)))
      (setq my-magit-ediff--control-buffer (ediff-buffers buf-a buf-b)))
    (my-magit-ediff--restore-side-windows side-spec)))

(defun my-magit-ediff--create-revision-buffer (file rev)
  "Create a buffer with FILE content at REV.
If REV is nil, return the working tree file buffer.
If REV is `index', return the staged content.
If REV is a string, return that revision's content."
  (let ((default-directory (magit-toplevel)))
    (cond
     ((null rev)
      (let ((buf (find-file-noselect (expand-file-name file))))
        (with-current-buffer buf
          (setq-local my-magit-ediff--buf-file file
                      my-magit-ediff--buf-rev nil))
        buf))
     ((eq rev 'index)
      (let ((buf (generate-new-buffer
                  (format "%s (index)" file))))
        (with-current-buffer buf
          (magit-git-insert "cat-file" "-p" (concat ":0:" file))
          (let ((buffer-file-name (expand-file-name file)))
            (set-auto-mode))
          (setq buffer-read-only t)
          (setq-local my-magit-ediff--buf-file file
                      my-magit-ediff--buf-rev 'index)
          (goto-char (point-min)))
        (push buf my-magit-ediff--temp-buffers)
        buf))
     ((stringp rev)
      (let ((buf (generate-new-buffer
                  (format "%s (%s)" file (substring rev 0 (min 7 (length rev)))))))
        (with-current-buffer buf
          (magit-git-insert "cat-file" "-p" (concat rev ":" file))
          (let ((buffer-file-name (expand-file-name file)))
            (set-auto-mode))
          (setq buffer-read-only t)
          (setq-local my-magit-ediff--buf-file file
                      my-magit-ediff--buf-rev rev)
          (goto-char (point-min)))
        (push buf my-magit-ediff--temp-buffers)
        buf)))))

(defun my-magit-ediff--kill-temp-buffers ()
  "Kill all temporary revision buffers."
  (dolist (buf my-magit-ediff--temp-buffers)
    (when (buffer-live-p buf)
      (kill-buffer buf)))
  (setq my-magit-ediff--temp-buffers nil))

(defun my-magit-ediff--kill-stale-revision-buffers ()
  "Kill leftover revision buffers generated for earlier files.
Only buffers built from a git revision (a non-nil `my-magit-ediff--buf-rev',
i.e. a commit SHA or `index') are killed, so the working-tree file buffer
\(nil rev) is never touched and unsaved edits are preserved.  This guards
against revision buffers piling up when navigation skips the normal quit
path, such as rapid file switches from the review sidebar."
  (dolist (buffer (buffer-list))
    (when (and (buffer-live-p buffer)
               (buffer-local-value 'my-magit-ediff--buf-rev buffer))
      (kill-buffer buffer)))
  (setq my-magit-ediff--temp-buffers nil))

(defun my-magit-ediff--on-quit ()
  "Hook called when ediff session ends. Show navigation prompt if active."
  (when my-magit-ediff--active
    ;; Delay to let ediff finish cleanup before killing temp buffers.
    (run-at-time 0.1 nil #'my-magit-ediff--after-quit)))

(defun my-magit-ediff--after-quit ()
  "Kill temp buffers, then jump to a pending file or run navigation.
When `my-magit-ediff--pending-index' is set (a jump requested from the
sidebar), open that file.  Otherwise delegate to
`my-magit-ediff-navigation-function'.  If that navigation is aborted
\(e.g. `C-g'), run cleanup so the session state and `ediff-quit-hook' do
not leak into later, unrelated ediff sessions."
  (my-magit-ediff--kill-temp-buffers)
  (if my-magit-ediff--pending-index
      (let ((index my-magit-ediff--pending-index))
        (setq my-magit-ediff--pending-index nil
              my-magit-ediff--current-index index)
        (my-magit-ediff--open-current))
    (condition-case nil
        (funcall my-magit-ediff-navigation-function)
      (quit
       (my-magit-ediff--cleanup)
       (message "Review ended.")))))

(defun my-magit-ediff-goto-index (index)
  "Switch the active multi-file session to the file at INDEX.
If a comparison is open, quit it first; the jump then happens in
`my-magit-ediff--after-quit'.  Otherwise open the file directly."
  (unless my-magit-ediff--active
    (user-error "No active multi-file ediff session"))
  (let ((control my-magit-ediff--control-buffer))
    (if (and control (buffer-live-p control))
        ;; A comparison is open, so we cannot stack the next ediff on top
        ;; of it.  Record the target and quit; quitting runs `ediff-quit-hook'
        ;; -> `my-magit-ediff--on-quit' -> `my-magit-ediff--after-quit', which
        ;; opens `my-magit-ediff--pending-index'.  The next ediff is therefore
        ;; launched through the quit hook, not synchronously here.
        (progn
          (setq my-magit-ediff--pending-index index)
          (with-current-buffer control (ediff-really-quit nil)))
      (setq my-magit-ediff--current-index index)
      (my-magit-ediff--open-current))))

(defun my-magit-ediff--build-file-labels ()
  "Build labeled file list for `completing-read'."
  (let ((total my-magit-ediff--total-count)
        (result nil)
        (i 0))
    (dolist (file my-magit-ediff--files (nreverse result))
      (push (format "[%d/%d] %s" (1+ i) total file) result)
      (setq i (1+ i)))))

(defun my-magit-ediff--ordered-collection (candidates)
  "Return a completion table over CANDIDATES that preserves their order.
Stops completion frameworks like vertico from re-sorting by history
or length, so files stay in their natural 1..N order."
  (lambda (string pred action)
    (if (eq action 'metadata)
        '(metadata (display-sort-function . identity)
                   (cycle-sort-function . identity))
      (complete-with-action action candidates string pred))))

(defun my-magit-ediff--prompt-navigation ()
  "Show file list using `completing-read' for navigation.
Candidates stay in strict 1..N order followed by the quit entry.  No
default is passed because completion UIs (vertico) hoist the default
candidate to the top, which scrambles the visual order."
  (let* ((idx my-magit-ediff--current-index)
         (total my-magit-ediff--total-count)
         (quit-label "[Done] Quit review")
         (file-labels (my-magit-ediff--build-file-labels))
         (candidates (append file-labels (list quit-label)))
         (selection (completing-read
                     (format "Ediff [%d/%d done]: " (1+ idx) total)
                     (my-magit-ediff--ordered-collection candidates)
                     nil t nil nil)))
    (if (string= selection quit-label)
        (progn
          (my-magit-ediff--cleanup)
          (message "Review ended. %d/%d files reviewed." (1+ idx) total))
      (let ((pos (seq-position file-labels selection #'string=)))
        (when pos
          (setq my-magit-ediff--current-index pos)
          (my-magit-ediff--open-current))))))

(defun my-magit-ediff--cleanup ()
  "Reset state variables, restore windows, and remove hook.
`my-magit-ediff-cleanup-hook' runs first so consumers can tear down
their own UI (such as the review sidebar) while session state is intact."
  (run-hooks 'my-magit-ediff-cleanup-hook)
  (my-magit-ediff--kill-temp-buffers)
  (setq my-magit-ediff--files nil
        my-magit-ediff--current-index 0
        my-magit-ediff--rev-a nil
        my-magit-ediff--rev-b nil
        my-magit-ediff--total-count 0
        my-magit-ediff--active nil
        my-magit-ediff--control-buffer nil
        my-magit-ediff--pending-index nil)
  (remove-hook 'ediff-quit-hook #'my-magit-ediff--on-quit)
  (when my-magit-ediff--saved-window-config
    (set-window-configuration my-magit-ediff--saved-window-config)
    (setq my-magit-ediff--saved-window-config nil)))

;;;; Keybindings

(with-eval-after-load 'magit-ediff
  (transient-append-suffix 'magit-ediff '(0 -1)
    ["All files"
     ("A u" "All unstaged" my-magit-ediff-all-unstaged)
     ("A s" "All staged" my-magit-ediff-all-staged)
     ("A r" "All revisions" my-magit-ediff-all-compare)]))

(provide 'my-magit-ediff)
;;; my-magit-ediff.el ends here
