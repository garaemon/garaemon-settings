;;; my-forge-ediff-review.el --- Comment on GitHub PRs from ediff -*- lexical-binding: t; -*-

;;; Commentary:
;; Companion to `my-magit-ediff' for reviewing forge pull requests in a
;; true side-by-side view.  While walking through hunks in ediff, capture
;; per-line comments against the PR's head commit, then submit them as a
;; single GitHub PR review (event = COMMENT / APPROVE / REQUEST_CHANGES).
;;
;; Workflow:
;;   1. `my-forge-ediff-review-start' on a `forge-pullreq' (called by
;;      `my-forge-ediff-pullreq-at-point').  Records the PR context and
;;      launches `my-magit-ediff-all-compare' between base and head.
;;   2. In any ediff revision buffer, `my-forge-ediff-review-add-comment'
;;      grabs the current file/line/side from the buffer locals set by
;;      `my-magit-ediff--create-revision-buffer' and pops up a comment
;;      editor (markdown-mode, `C-c C-c' to save, `C-c C-k' to cancel).
;;   3. `my-forge-ediff-review-list-comments' shows pending comments.
;;   4. `my-forge-ediff-review-submit' POSTs them all as one review via
;;      ghub against /repos/<owner>/<repo>/pulls/<num>/reviews.

;;; Code:

(require 'cl-lib)
(require 'ghub)
(require 'my-magit-ediff)

(defvar my-forge-ediff-review--session nil
  "Plist for the active review session, or nil.
Keys: :owner :repo :num :head-rev :base-rev :host :comments.
Each comment is a plist with :path :line :side :body.")

;;;; Session lifecycle

;; TODO(agent): The ediff control window is tiny and hard to use during
;; reviews.  Drive multi-file navigation (next/prev hunk, next/prev file,
;; quit) from the revision buffers directly so the control frame can be
;; hidden or replaced with a thin header line.  Look at
;; `ediff-window-setup-function' and `ediff-make-wide-display' for the
;; entry points.
(defun my-forge-ediff-review-start (pullreq)
  "Start an ediff-based review session for forge PULLREQ.
Verifies that the PR commits are fetched, records the session, and
launches multi-file ediff between PR base and head."
  (unless (forge-pullreq-p pullreq)
    (user-error "Not a forge pull request"))
  (let* ((repo (forge-get-repository pullreq))
         (base-rev (oref pullreq base-rev))
         (head-rev (oref pullreq head-rev)))
    (unless (and base-rev (magit-rev-verify base-rev))
      (user-error "PR base commit %s not fetched; run `forge-pull' first"
                  (or base-rev "<unknown>")))
    (unless (and head-rev (magit-rev-verify head-rev))
      (user-error "PR head commit %s not fetched; run `forge-pull' first"
                  (or head-rev "<unknown>")))
    (when (and my-forge-ediff-review--session
               (plist-get my-forge-ediff-review--session :comments)
               (not (yes-or-no-p
                     (format "Discard %d pending review comment(s)? "
                             (length (plist-get my-forge-ediff-review--session
                                                :comments))))))
      (user-error "Aborted"))
    (setq my-forge-ediff-review--session
          (list :owner (oref repo owner)
                :repo (oref repo name)
                :num (oref pullreq number)
                :head-rev head-rev
                :base-rev base-rev
                :host (my-forge-ediff-review--host-for repo)
                :comments nil))
    (message
     "Review session for PR #%s started. C-c M c to comment, C-c M C to submit."
     (oref pullreq number))
    (my-magit-ediff-all-compare base-rev head-rev)))

(defun my-forge-ediff-review--host-for (repo)
  "Return the API host to use for REPO, or nil for ghub's default."
  (when (and (fboundp 'forge-github-repository-p)
             (forge-github-repository-p repo))
    ;; nil makes ghub default to `ghub-default-host' which is api.github.com.
    nil))

(defun my-forge-ediff-review--ensure-session ()
  "Signal an error if no review session is active."
  (unless my-forge-ediff-review--session
    (user-error "No active forge ediff review session")))

;;;; Overlays in ediff buffers

(defface my-forge-ediff-review-comment-face
  '((((background light)) :background "#fff8c5" :foreground "#24292f")
    (((background dark))  :background "#3a3a00" :foreground "#ffffff"))
  "Face for lines with pending review comments and inline body display."
  :group 'my-forge-ediff-review)

(defun my-forge-ediff-review--side-for-rev (rev)
  "Return \"LEFT\" / \"RIGHT\" for REV in the current session, or nil."
  (let ((s my-forge-ediff-review--session))
    (cond
     ((equal rev (plist-get s :base-rev)) "LEFT")
     ((equal rev (plist-get s :head-rev)) "RIGHT"))))

(defun my-forge-ediff-review--format-overlay-body (body)
  "Indent every line of BODY for inline overlay display."
  (mapconcat (lambda (l) (concat "    | " l))
             (split-string body "\n")
             "\n"))

(defun my-forge-ediff-review--put-overlay (buf line body)
  "Append BODY as a highlighted after-string overlay below LINE in BUF.
The commented source line is left untouched; only the comment text
itself is highlighted.  The overlay is anchored at end-of-line so it
does not shift `display-line-numbers-mode' or `nlinum-mode' counts."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (let* ((eol (line-end-position))
             (ov (make-overlay eol eol nil t nil)))
        (overlay-put ov 'my-forge-ediff-review t)
        (overlay-put ov 'priority 100)
        (overlay-put ov 'after-string
                     (propertize
                      (concat
                       "\n"
                       (my-forge-ediff-review--format-overlay-body body))
                      'face 'my-forge-ediff-review-comment-face))))))

(defun my-forge-ediff-review--clear-overlays (&optional buf)
  "Remove all review overlays from BUF (defaults to current buffer)."
  (with-current-buffer (or buf (current-buffer))
    (remove-overlays (point-min) (point-max) 'my-forge-ediff-review t)))

(defun my-forge-ediff-review--reapply-overlays ()
  "Reapply overlays in current buffer for comments matching its file/side."
  (when (and my-forge-ediff-review--session
             my-magit-ediff--buf-file
             my-magit-ediff--buf-rev)
    (my-forge-ediff-review--clear-overlays)
    (let* ((file my-magit-ediff--buf-file)
           (rev  my-magit-ediff--buf-rev)
           (side (my-forge-ediff-review--side-for-rev rev)))
      (when side
        (dolist (c (plist-get my-forge-ediff-review--session :comments))
          (when (and (string= (plist-get c :path) file)
                     (string= (plist-get c :side) side))
            (my-forge-ediff-review--put-overlay
             (current-buffer)
             (plist-get c :line)
             (plist-get c :body))))))))

(defun my-forge-ediff-review--refresh-all-buffers ()
  "Reapply overlays in every live ediff revision buffer of the session."
  (dolist (buf my-magit-ediff--temp-buffers)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (my-forge-ediff-review--reapply-overlays)))))

;; Hook so that comments persist when ediff revisits a file.
(add-hook 'ediff-prepare-buffer-hook
          #'my-forge-ediff-review--reapply-overlays)

;;;; Context detection

(defun my-forge-ediff-review--current-context ()
  "Return plist (:path :line :side) for point in current buffer, or nil.
Side is \"LEFT\" when the buffer shows the PR base commit, \"RIGHT\"
when it shows the head."
  (when my-forge-ediff-review--session
    (let ((file my-magit-ediff--buf-file)
          (rev  my-magit-ediff--buf-rev)
          (line (line-number-at-pos)))
      (when (and file rev)
        (let* ((s my-forge-ediff-review--session)
               (side (cond
                      ((equal rev (plist-get s :base-rev)) "LEFT")
                      ((equal rev (plist-get s :head-rev)) "RIGHT"))))
          (when side
            (list :path file :line line :side side)))))))

;;;; Adding comments

(defvar my-forge-ediff-review--editor-ctx nil
  "Buffer-local context plist while editing a comment.")

;; TODO(agent): Bind RET in the ediff revision buffers to this command
;; while a review session is active, so commenting is one keystroke.
;; The buffers are read-only and RET is unbound there, so a buffer-local
;; keymap set in `my-magit-ediff--create-revision-buffer' (only when a
;; session exists) should be safe.
(defun my-forge-ediff-review-add-comment ()
  "Add a PR review comment for the line at point in this ediff buffer."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let ((ctx (my-forge-ediff-review--current-context)))
    (unless ctx
      (user-error
       "Not in a review ediff revision buffer (no file/rev context)"))
    (my-forge-ediff-review--open-editor ctx)))

(defun my-forge-ediff-review--open-editor (ctx)
  "Pop up an editor buffer for a comment described by CTX."
  (let ((buf (generate-new-buffer "*forge-review-comment*")))
    (with-current-buffer buf
      (when (fboundp 'markdown-mode)
        (markdown-mode))
      (insert (format
               "<!-- %s:%d (%s) — C-c C-c to save, C-c C-k to cancel. \
HTML comments are stripped. -->\n\n"
               (plist-get ctx :path)
               (plist-get ctx :line)
               (plist-get ctx :side)))
      (setq-local my-forge-ediff-review--editor-ctx ctx)
      (local-set-key (kbd "C-c C-c") #'my-forge-ediff-review--save-comment)
      (local-set-key (kbd "C-c C-k") #'my-forge-ediff-review--cancel-comment)
      (goto-char (point-max)))
    (pop-to-buffer buf)))

(defun my-forge-ediff-review--strip-html-comments (text)
  "Remove `<!-- ... -->' blocks from TEXT."
  (replace-regexp-in-string "<!--\\(.\\|\n\\)*?-->" "" text))

(defun my-forge-ediff-review--save-comment ()
  "Finalize the comment in the current editor buffer and store it."
  (interactive)
  (let* ((ctx my-forge-ediff-review--editor-ctx)
         (raw (buffer-string))
         (body (string-trim
                (my-forge-ediff-review--strip-html-comments raw))))
    (when (string-empty-p body)
      (user-error "Comment body is empty"))
    (unless my-forge-ediff-review--session
      (user-error "Review session disappeared; not saving"))
    (let ((comment (append ctx (list :body body))))
      (setf (plist-get my-forge-ediff-review--session :comments)
            (cons comment
                  (plist-get my-forge-ediff-review--session :comments))))
    (let ((buf (current-buffer)))
      (quit-window)
      (kill-buffer buf))
    (my-forge-ediff-review--refresh-all-buffers)
    (message "Comment saved (%d pending)."
             (length (plist-get my-forge-ediff-review--session :comments)))))

(defun my-forge-ediff-review--cancel-comment ()
  "Discard the in-progress comment editor."
  (interactive)
  (let ((buf (current-buffer)))
    (quit-window)
    (kill-buffer buf))
  (message "Comment cancelled."))

;;;; Listing / discarding

(defun my-forge-ediff-review-list-comments ()
  "Show pending review comments in a dedicated buffer."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let* ((comments (reverse
                    (plist-get my-forge-ediff-review--session :comments)))
         (buf (get-buffer-create "*forge-review-pending*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (if (null comments)
            (insert "No pending comments.\n")
          (let ((i 0))
            (dolist (c comments)
              (setq i (1+ i))
              (insert (format "[%d] %s:%d (%s)\n%s\n\n"
                              i
                              (plist-get c :path)
                              (plist-get c :line)
                              (plist-get c :side)
                              (plist-get c :body))))))
        (insert
         (format "\n-- PR #%s — d <n> discard, s submit --\n"
                 (plist-get my-forge-ediff-review--session :num))))
      (special-mode)
      (local-set-key "d" #'my-forge-ediff-review-discard-comment)
      (local-set-key "s" #'my-forge-ediff-review-submit)
      (local-set-key "g" #'my-forge-ediff-review-list-comments))
    (pop-to-buffer buf)))

(defun my-forge-ediff-review-discard-comment (n)
  "Discard pending comment number N (1-based, as shown in the list)."
  (interactive "nDiscard comment #: ")
  (my-forge-ediff-review--ensure-session)
  (let* ((comments (reverse
                    (plist-get my-forge-ediff-review--session :comments)))
         (len (length comments)))
    (unless (and (>= n 1) (<= n len))
      (user-error "Out of range (1..%d)" len))
    (let* ((target (nth (1- n) comments))
           (remaining (cl-remove target comments :count 1 :test #'eq)))
      (setf (plist-get my-forge-ediff-review--session :comments)
            (reverse remaining)))
    (my-forge-ediff-review--refresh-all-buffers)
    (message "Discarded comment #%d. %d pending." n
             (length (plist-get my-forge-ediff-review--session :comments)))
    (when (get-buffer "*forge-review-pending*")
      (my-forge-ediff-review-list-comments))))

;;;; Submit

(defun my-forge-ediff-review--build-payload (event summary)
  "Build the JSON payload for a PR review POST."
  (let* ((s my-forge-ediff-review--session)
         (comments (reverse (plist-get s :comments))))
    `((commit_id . ,(plist-get s :head-rev))
      (event    . ,event)
      (body     . ,(or summary ""))
      (comments . ,(vconcat
                    (mapcar
                     (lambda (c)
                       `((path . ,(plist-get c :path))
                         (line . ,(plist-get c :line))
                         (side . ,(plist-get c :side))
                         (body . ,(plist-get c :body))))
                     comments))))))

;; TODO(agent): Replace the `read-string' summary prompt with a dedicated
;; markdown editor buffer (modeled on `my-forge-ediff-review--open-editor'
;; for per-line comments).  Submission should happen when the user hits
;; `C-c C-c' in that buffer, with `C-c C-k' to cancel.  The minibuffer is
;; too small for any non-trivial review summary.
(defun my-forge-ediff-review-submit (event &optional summary)
  "Submit pending comments to GitHub as a PR review.
EVENT is one of \"COMMENT\", \"APPROVE\", \"REQUEST_CHANGES\".
SUMMARY is the optional top-level review body."
  (interactive
   (let ((event (completing-read
                 "Event: " '("COMMENT" "APPROVE" "REQUEST_CHANGES")
                 nil t nil nil "COMMENT")))
     (list event (read-string "Top-level summary (optional): "))))
  (my-forge-ediff-review--ensure-session)
  (let* ((s my-forge-ediff-review--session)
         (comments (plist-get s :comments))
         (summary-trim (string-trim (or summary ""))))
    (when (and (string= event "COMMENT")
               (null comments)
               (string-empty-p summary-trim))
      (user-error "Nothing to submit"))
    (ghub-post
     (format "/repos/%s/%s/pulls/%s/reviews"
             (plist-get s :owner)
             (plist-get s :repo)
             (plist-get s :num))
     (my-forge-ediff-review--build-payload event summary-trim)
     :auth 'forge
     :host (plist-get s :host)
     :callback (lambda (_value &rest _)
                 (message "Review submitted: %s (%d comments)"
                          event (length comments))
                 (setf (plist-get my-forge-ediff-review--session :comments)
                       nil)
                 (my-forge-ediff-review--refresh-all-buffers)
                 (when (get-buffer "*forge-review-pending*")
                   (my-forge-ediff-review-list-comments)))
     :errorback (lambda (err &rest _)
                  (message "Review submission failed: %S" err)))))

(provide 'my-forge-ediff-review)
;;; my-forge-ediff-review.el ends here
