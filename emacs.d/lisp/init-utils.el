;;; init-utils.el --- Custom utility functions and helper commands -*- lexical-binding: t -*-

;;; Commentary:
;; Custom utility functions and helper commands.

;;; Code:

;;; System compatibility utilities

(defun cocoa-emacs-p ()
  (and (= emacs-major-version 23) (eq window-system 'ns)))

(defun carbon-emacs-p ()
  (and (= emacs-major-version 22) (eq window-system 'mac)))

(defun meadowp ()
  (eq system-type 'windows-nt))

(defun cygwinp ()
  (eq system-type 'cygwin))

(defun emacs22p ()
  (= emacs-major-version 22))

(defun emacs23p ()
  (= emacs-major-version 23))

(defmacro when-gui (&rest bodies)
  `(when window-system
     ,@bodies))

(defmacro when-meadow (&rest bodies)
  `(when (meadowp)
     ,@bodies))

(defmacro when-darwin (&rest bodies)
  `(when (eq system-type 'darwin)
     ,@bodies))

(defmacro when-cygwin (&rest bodies)
  `(when (cygwinp)
     ,@bodies))

(defmacro when-carbon (&rest bodies)
  `(when (carbon-emacs-p)
     ,@bodies))

(defmacro when-cocoa (&rest bodies)
  `(when (cocoa-emacs-p)
     ,@bodies))

(defmacro when-emacs22 (&rest bodies)
  `(when (emacs22p)
     ,@bodies))

(defmacro when-emacs23 (&rest bodies)
  `(when (emacs23p)
     ,@bodies))

(defmacro unless-gui (&rest bodies)
  `(unless window-system
     ,@bodies))

(defmacro unless-meadow (&rest bodies)
  `(unless (meadowp)
     ,@bodies))

(defmacro unless-cygwin (&rest bodies)
  `(unless (cygwinp)
     ,@bodies))

(defmacro unless-carbon (&rest bodies)
  `(unless (carbon-emacs-p)
     ,@bodies))

(defmacro unless-cocoa (&rest bodies)
  `(unless (cocoa-emacs-p)
     ,@bodies))

(defmacro unless-emacs22 (&rest bodies)
  `(unless (emacs22p)
     ,@bodies))

(defmacro unless-emacs23 (&rest bodies)
  `(unless (emacs23p)
     ,@bodies))

(defun my-find-file-under-directories (file dirs)
  "Find FILE recursively under DIRS.
Returns non-nil if FILE is found in any of the directories in DIRS."
  (if (null dirs)
      nil
    (let ((target-dir (car dirs))
          (rest-dirs (cdr dirs)))
      (or (and (file-exists-p target-dir)
               (directory-files-recursively target-dir (regexp-quote file)))
          (my-find-file-under-directories file rest-dirs)))))

;;; File and buffer management

(defun open-setting-file ()
  "Open this file."
  (interactive)
  (find-file "~/.emacs./lisp/garaemon-dot-emacs.el"))

(defun save-all ()
  "Save all buffers without y-or-n asking."
  (interactive)
  (save-some-buffers t))
(global-set-key "\C-xs" 'save-all)

(defun reopen-file ()
  (interactive)
  (find-file (buffer-file-name)))

(defun revert-buffer-no-confirm (&optional force-reverting)
  "Force to reload buffer if the file is modified or FORCE-REVREZTING is t.

Ignoring the auto-save file and not requesting for confirmation.
When the current buffer is modified, the command refuses to revert it,
unless you specify the optional argument: FORCE-REVERTING to true."
  (interactive "P")
  ;;(message "force-reverting value is %s" force-reverting)
  (if (or force-reverting
          (not (buffer-modified-p)))
      (revert-buffer
       :ignore-auto
       :noconfirm)
    (error
     "The buffer has been modified")))
(global-set-key "\M-r" 'revert-buffer-no-confirm)

;;; Mathematical conversion utilities

(defun rad2deg (rad)
  "Convert radian RAD to degree."
  (* (/ rad pi) 180))

(defun deg2rad (deg)
  "Convert degree DEG to radian."
  (* (/ deg 180.0) pi))

(defun rad2deg-interactive (rad)
  "Convert radian RAD to degree."
  (interactive "nrad ")
  (message "%f rad -> %f deg" rad (rad2deg rad)))

(defun deg2rad-interactive (deg)
  "Convert degree DEG to radian."
  (interactive "ndeg ")
  (message "%f deg -> %f rad" deg (deg2rad deg)))

;;; Navigation utilities

(defun jump-to-corresponding-brace ()
  "Move to corresponding brace."
  (interactive)
  (let ((c (following-char))
        (p (preceding-char)))
    (if (eq (char-syntax c) 40) (forward-list)
      (if (eq (char-syntax p) 41) (backward-list)
        (backward-up-list)))))
(global-set-key (kbd "C-,") 'jump-to-corresponding-brace)

;;; Text insertion utilities

(defun insert-date ()
  "Insert date at current cursor."
  (interactive)
  (insert (format-time-string "%Y-%m-%dT%H:%M:%SZ\n" nil t)))

;;; Number manipulation utilities

(defun increment-number-at-point ()
  "Increase number at current cursor."
  (interactive)
  (skip-chars-backward "0123456789")
  (or (looking-at "[0123456789]+")
      (error
       "No number at point"))
  (replace-match (number-to-string (1+ (string-to-number (match-string 0))))))

(defun decrement-number-at-point ()
  "Decrease number at current cursor."
  (interactive)
  (skip-chars-backward "0123456789")
  (or (looking-at "[0123456789]+")
      (error
       "No number at point"))
  (replace-match (number-to-string (1- (string-to-number (match-string 0))))))

(global-set-key (kbd "C-c C-+") 'increment-number-at-point)
(global-set-key (kbd "C-c C-;") 'increment-number-at-point)
(global-set-key (kbd "C-c C--") 'decrement-number-at-point)

;;; Tmux integration utilities

(defun open-current-file-in-tmux ()
  "Open current file in tmux."
  (interactive)
  (let ((file-path (buffer-file-name)))
    (let ((target-dir (if (file-directory-p file-path)
                          file-path
                        (file-name-directory file-path))))
      (message (format "Opening directory %s in tmux" target-dir))
      (call-process-shell-command (format
                                   "tmux new-window -a -t $(tmux ls -F \"#S\") -c %s"
                                   target-dir) nil "*tmux-output*" nil
                                   ))))

(global-set-key "\M-t" 'open-current-file-in-tmux)

;;; Profiler utilities

(defun profiler-auto-start-and-report (duration-seconds)
  "Starts the Emacs profiler and automatically stops it after a specified duration,
then generates a report. Prompts the user for the duration in seconds."
  (interactive "nNumber of seconds to profile: ")
  (unless (> duration-seconds 0)
    (user-error "Duration must be a positive number."))

  (message "Profiler started for %s seconds..." duration-seconds)
  (profiler-start 'cpu+mem)

  ;; Set a timer to stop the profiler and generate a report after the specified time
  (run-at-time
   (format "%s sec" duration-seconds) ; Time specification
   nil                             ; Do not repeat (nil)
   (lambda ()
     (message "Stopping profiler and generating report...")
     (profiler-stop)
     (profiler-report)
     (message "Profiling complete."))
   )
  (message "Profiler is running. It will stop and report automatically in %s seconds." duration-seconds))

;;; Frame settings

(when (display-graphic-p)
  (setq initial-frame-alist
        '((top . 0)
          ;; Start Emacs with the window snapped to the right edge.
          (left . 1.0)
          ;; The screen size should use the right half.
          (width . 0.5)
          ;; We use a value slightly smaller than 1.0. This is because even if `top`
          ;; is set to 0.0 in MacOS, the window is displayed slightly lower, and as a result,
          ;; if `height` is set to 1.0, the bottom of the window becomes invisible.
          (height . 0.9)
          ))
  )

(provide 'init-utils)
;;; init-utils.el ends here
