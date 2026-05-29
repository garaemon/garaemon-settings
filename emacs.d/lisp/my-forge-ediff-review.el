;;; my-forge-ediff-review.el --- Comment on GitHub PRs from ediff -*- lexical-binding: t; -*-

;;; Commentary:
;; Companion to `my-magit-ediff' for reviewing forge pull requests in a
;; true side-by-side view.  While walking through hunks in ediff, capture
;; per-line comments against the PR's head commit, then submit them as a
;; single GitHub PR review (event = COMMENT / APPROVE / REQUEST_CHANGES).
;;
;; Data model:
;;   All review state lives in one global plist,
;;   `my-forge-ediff-review--session' (nil when no review is active):
;;
;;     (:owner "..." :repo "..." :num N
;;      :base-rev "<sha>" :head-rev "<sha>" :host nil
;;      :comments (COMMENT ...))
;;
;;   Each pending comment is itself a plist:
;;
;;     (:path "rel/path" :line N :side "LEFT"|"RIGHT" :body "markdown")
;;
;;   :side is "LEFT" for the base commit and "RIGHT" for the head commit,
;;   matching the GitHub Reviews API.  Where does (:path :line :side) come
;;   from?  Ediff only shows two anonymous buffers, so each revision buffer
;;   is tagged with the buffer locals `my-magit-ediff--buf-file' and
;;   `my-magit-ediff--buf-rev' (set in `my-magit-ediff--create-revision-buffer').
;;   `--current-context' reads those: :path = `--buf-file', :line = point's
;;   line, and :side = `--buf-rev' compared against the session's base/head.
;;   New comments are prepended to :comments and reversed back to insertion
;;   order when listed or submitted.
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

;;;; Ediff control & navigation

;; NOTE: `ediff-window-setup-function' is set to `ediff-setup-windows-plain'
;; in init-editor.el; the in-buffer navigation below depends on it.

(defun my-forge-ediff-review--in-control-buffer (cmd)
  "Run CMD with `ediff-control-buffer' selected as the current buffer."
  (let ((ctrl (and (boundp 'ediff-control-buffer) ediff-control-buffer)))
    (unless (and ctrl (buffer-live-p ctrl))
      (user-error "No active ediff control buffer"))
    (with-current-buffer ctrl
      (call-interactively cmd))))

(defun my-forge-ediff-review-next-diff ()
  "Jump to the next ediff difference from the current revision buffer."
  (interactive)
  (my-forge-ediff-review--in-control-buffer #'ediff-next-difference))

(defun my-forge-ediff-review-prev-diff ()
  "Jump to the previous ediff difference from the current revision buffer."
  (interactive)
  (my-forge-ediff-review--in-control-buffer #'ediff-previous-difference))

(defun my-forge-ediff-review-quit-ediff ()
  "End the current file's ediff session immediately."
  (interactive)
  (let ((ctrl (and (boundp 'ediff-control-buffer) ediff-control-buffer)))
    (unless (and ctrl (buffer-live-p ctrl))
      (user-error "No active ediff control buffer"))
    (with-current-buffer ctrl
      (ediff-really-quit nil))))

;;;; Session lifecycle

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

(defun my-forge-ediff-review--setup-revision-keys ()
  "Install buffer-local keys for in-place ediff navigation and commenting.
Only active when a review session is running and the buffer has the
file/rev locals set by `my-magit-ediff--create-revision-buffer'."
  (when (and my-forge-ediff-review--session
             my-magit-ediff--buf-file
             my-magit-ediff--buf-rev)
    (let ((map (make-composed-keymap nil (current-local-map))))
      (define-key map (kbd "RET") #'my-forge-ediff-review-add-comment)
      (define-key map (kbd "n") #'my-forge-ediff-review-next-diff)
      (define-key map (kbd "p") #'my-forge-ediff-review-prev-diff)
      (define-key map (kbd "q") #'my-forge-ediff-review-quit-ediff)
      (use-local-map map))))

(defun my-forge-ediff-review--prepare-buffer ()
  "Apply overlays and install nav/comment keys in the current revision buffer."
  (my-forge-ediff-review--reapply-overlays)
  (my-forge-ediff-review--setup-revision-keys))

;; Hook so that comments persist and review keys exist when ediff
;; (re)visits a file.
(add-hook 'ediff-prepare-buffer-hook
          #'my-forge-ediff-review--prepare-buffer)

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

(defvar my-forge-ediff-review--summary-event nil
  "Buffer-local: the event chosen for the summary editor.")

(defun my-forge-ediff-review-submit ()
  "Pick a review event then open a buffer to write the summary in.
The actual POST happens when the user types `C-c C-c' in that buffer."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let ((event (completing-read
                "Event: " '("COMMENT" "APPROVE" "REQUEST_CHANGES")
                nil t nil nil "COMMENT")))
    (my-forge-ediff-review--open-summary-editor event)))

(defun my-forge-ediff-review--open-summary-editor (event)
  "Pop up a markdown buffer for the top-level review summary."
  (let ((buf (generate-new-buffer "*forge-review-summary*"))
        (pr-num (plist-get my-forge-ediff-review--session :num))
        (pending (length
                  (plist-get my-forge-ediff-review--session :comments))))
    (with-current-buffer buf
      (when (fboundp 'markdown-mode)
        (markdown-mode))
      (insert (format
               "<!-- Review for PR #%s — event: %s — %d inline comment(s).\n\
C-c C-c submits, C-c C-k cancels. HTML comments are stripped. -->\n\n"
               pr-num event pending))
      (setq-local my-forge-ediff-review--summary-event event)
      (local-set-key (kbd "C-c C-c")
                     #'my-forge-ediff-review--submit-from-editor)
      (local-set-key (kbd "C-c C-k")
                     #'my-forge-ediff-review--cancel-summary)
      (goto-char (point-max)))
    (pop-to-buffer buf)))

(defun my-forge-ediff-review--submit-from-editor ()
  "Finalize the summary in the current editor buffer and POST the review."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let* ((event my-forge-ediff-review--summary-event)
         (raw (buffer-string))
         (summary (string-trim
                   (my-forge-ediff-review--strip-html-comments raw)))
         (comments (plist-get my-forge-ediff-review--session :comments)))
    (unless event
      (user-error "No event recorded for this summary buffer"))
    (when (and (string= event "COMMENT")
               (null comments)
               (string-empty-p summary))
      (user-error "Nothing to submit"))
    (my-forge-ediff-review--do-submit event summary)
    (let ((buf (current-buffer)))
      (quit-window)
      (kill-buffer buf))))

(defun my-forge-ediff-review--cancel-summary ()
  "Discard the summary editor without submitting."
  (interactive)
  (let ((buf (current-buffer)))
    (quit-window)
    (kill-buffer buf))
  (message "Submission cancelled."))

(defun my-forge-ediff-review--do-submit (event summary)
  "POST EVENT/SUMMARY plus the session's pending inline comments via ghub."
  (let* ((s my-forge-ediff-review--session)
         (comment-count (length (plist-get s :comments))))
    (ghub-post
     (format "/repos/%s/%s/pulls/%s/reviews"
             (plist-get s :owner)
             (plist-get s :repo)
             (plist-get s :num))
     (my-forge-ediff-review--build-payload event summary)
     :auth 'forge
     :host (plist-get s :host)
     :callback (lambda (_value &rest _)
                 (message "Review submitted: %s (%d comments)"
                          event comment-count)
                 (setf (plist-get my-forge-ediff-review--session :comments)
                       nil)
                 (my-forge-ediff-review--refresh-all-buffers)
                 (when (get-buffer "*forge-review-pending*")
                   (my-forge-ediff-review-list-comments)))
     :errorback (lambda (err &rest _)
                  (message "Review submission failed: %S" err)))))

(provide 'my-forge-ediff-review)
;;; my-forge-ediff-review.el ends here
