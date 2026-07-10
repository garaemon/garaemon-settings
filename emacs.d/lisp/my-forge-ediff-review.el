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
;;     (:owner "..." :repo "..." :num N :title "..." :body "..."
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
(require 'my-forge-ediff-review-model)

(defvar my-forge-ediff-review--session nil
  "Plist for the active review session, or nil.
Keys: :owner :repo :num :title :body :head-rev :base-rev :host
:comments :memos :reviewed :existing.  :title and :body are the PR's
title and description, read from forge's local database so they can be
shown while reviewing.  Each comment and memo is a plist with :path
:line :side :body; memos stay local and are never submitted.  :reviewed
is a list of repository-relative file paths the user has flagged as
done.  :existing holds review comments already posted to the PR on
GitHub, fetched once at session start and shown read-only as overlays.")

(defvar my-forge-ediff-review--cards-collapsed nil
  "When non-nil, inline comment cards render as one-line summaries.
Shared across every ediff revision buffer of the session so
`my-forge-ediff-review-toggle-cards' folds or unfolds them all at once.
Reset to nil when a session starts so an earlier fold never carries
over into a new review.")

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

(defun my-forge-ediff-review--diff-base (base-rev head-rev)
  "Return the commit to diff HEAD-REV against when reviewing a PR.
GitHub shows a PR as the three-dot diff `base...head', i.e. against the
merge-base where the branch diverged, not against the base branch tip.
Diffing against the tip (a two-dot diff) would fold in commits that landed
on the base branch after the PR forked, inflating the file list with
unrelated changes.  Fall back to BASE-REV when no merge-base is found."
  (or (magit-git-string "merge-base" base-rev head-rev) base-rev))

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
    ;; `:base-rev' must track the diff base so that
    ;; `my-forge-ediff-review--side-for-rev' still maps the base pane to LEFT.
    (let ((diff-base (my-forge-ediff-review--diff-base base-rev head-rev)))
      (setq my-forge-ediff-review--session
            (list :owner (oref repo owner)
                  :repo (oref repo name)
                  :num (oref pullreq number)
                  :title (oref pullreq title)
                  :body (oref pullreq body)
                  :head-rev head-rev
                  :base-rev diff-base
                  :host (my-forge-ediff-review--resolve-host repo)
                  :comments nil
                  :memos nil
                  :reviewed nil
                  :existing nil))
      ;; Start every review with cards unfolded; the fold flag is global,
      ;; so without this a stray `c' in an earlier review would leave this
      ;; one showing only one-line summaries.
      (setq my-forge-ediff-review--cards-collapsed nil)
      (message
       "Review session for PR #%s started. C-c M c to comment, C-c M C to submit."
       (oref pullreq number))
      (my-forge-ediff-review--install-sidebar-hooks)
      (my-forge-ediff-review--fetch-existing-threads)
      (my-magit-ediff-all-compare diff-base head-rev))))

(defun my-forge-ediff-review--resolve-host (repo)
  "Return the API host to use for REPO, or nil for ghub's default.
Supports both github.com and GitHub Enterprise: the host comes from the
repository's own `apihost' slot, which ghub uses verbatim to build the
REST and GraphQL endpoints (api.github.com for github.com).  Non-GitHub
forges resolve to nil so ghub falls back to its default host."
  (when (and (fboundp 'forge-github-repository-p)
             (forge-github-repository-p repo))
    (my-forge-ediff-review-model-resolve-host (oref repo apihost))))

(defun my-forge-ediff-review--ensure-session ()
  "Signal an error if no review session is active."
  (unless my-forge-ediff-review--session
    (user-error "No active forge ediff review session")))

;;;; PR description

(defconst my-forge-ediff-review--description-buffer-name
  "*forge-review-description*"
  "Name of the read-only buffer showing the PR title and description.")

(defun my-forge-ediff-review-show-description ()
  "Show the PR's title and description in a read-only markdown buffer.
Available from the revision buffers and the sidebar on `D'; the buffer
closes with `q' (via `view-mode')."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let ((s my-forge-ediff-review--session)
        (buf (get-buffer-create
              my-forge-ediff-review--description-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (my-forge-ediff-review-model-format-description
                 (plist-get s :num)
                 (plist-get s :title)
                 (plist-get s :body))))
      (when (fboundp 'markdown-mode)
        (markdown-mode))
      (view-mode 1)
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;;;; Existing review comments (fetched from GitHub)

(defconst my-forge-ediff-review--threads-query
  "query($owner:String!,$repo:String!,$number:Int!){
     repository(owner:$owner,name:$repo){
       pullRequest(number:$number){
         reviewThreads(first:100){
           nodes{
             id
             isResolved path line originalLine diffSide
             comments(first:100){
               nodes{ databaseId body createdAt author{login} }
             }
           }
         }
       }
     }
   }"
  "GraphQL query fetching a PR's review threads and their inline comments.")

(defun my-forge-ediff-review--fetch-existing-threads ()
  "Fetch the PR's existing review comments and overlay them when they arrive.
Runs asynchronously; failures are reported but never abort the review."
  (let ((s my-forge-ediff-review--session))
    (when (fboundp 'ghub-query)
      (ghub-query
       my-forge-ediff-review--threads-query
       `((owner . ,(plist-get s :owner))
         (repo . ,(plist-get s :repo))
         (number . ,(plist-get s :num)))
       :auth 'forge
       :host (plist-get s :host)
       :callback #'my-forge-ediff-review--on-threads-fetched
       :errorback (lambda (err &rest _)
                    (message "Could not fetch existing review comments: %S"
                             err))))))

(defun my-forge-ediff-review--on-threads-fetched (response &rest _)
  "Store parsed RESPONSE into the session and refresh overlays."
  (when my-forge-ediff-review--session
    (let ((entries (my-forge-ediff-review-model-parse-review-threads
                    response)))
      (setf (plist-get my-forge-ediff-review--session :existing) entries)
      (my-forge-ediff-review--refresh-all-buffers)
      (message "Loaded %d existing review comment(s)." (length entries)))))

;;;; Overlays in ediff buffers

(defcustom my-forge-ediff-review-card-width 72
  "Inner content width, in columns, of an inline review comment card.
Bodies are word-wrapped to this width; the card grows wider only when a
header (author and timestamp) does not fit."
  :type 'integer
  :group 'my-forge-ediff-review)

(defface my-forge-ediff-review-comment-face
  '((((background light)) :background "#fff8c5" :foreground "#24292f")
    (((background dark))  :background "#3a3a00" :foreground "#ffffff"))
  "Face for lines with pending review comments and inline body display."
  :group 'my-forge-ediff-review)

(defface my-forge-ediff-review-memo-face
  '((((background light)) :background "#ddf4ff" :foreground "#24292f")
    (((background dark))  :background "#002a3a" :foreground "#ffffff"))
  "Face for inline memos, which stay local and are never submitted."
  :group 'my-forge-ediff-review)

(defface my-forge-ediff-review-existing-comment-face
  '((((background light)) :background "#eaeef2" :foreground "#57606a")
    (((background dark))  :background "#21262d" :foreground "#8b949e"))
  "Face for existing review comments already posted to the PR on GitHub."
  :group 'my-forge-ediff-review)

(defcustom my-forge-ediff-review-dim-diff-faces t
  "When non-nil, soften ediff's diff highlight faces in review buffers.
Ediff's default `ediff-current-diff-*' and `ediff-fine-diff-*' faces
paint an opaque background and override the foreground, which hides the
buffer's own syntax highlighting.  While a review session is active
those faces are remapped, buffer-locally, to a background-only spec so
the font-lock foreground stays visible and code remains readable.  The
remap is scoped to the ediff revision buffers, so ediff used outside a
review keeps its normal, stronger highlighting."
  :type 'boolean
  :group 'my-forge-ediff-review)

(defconst my-forge-ediff-review--dim-diff-faces
  '((ediff-current-diff-A        . (:background "#3d2529"))
    (ediff-current-diff-B        . (:background "#1f3325"))
    (ediff-current-diff-C        . (:background "#2f2f1c"))
    (ediff-current-diff-Ancestor . (:background "#2f2f1c"))
    (ediff-fine-diff-A           . (:background "#5a2c33"))
    (ediff-fine-diff-B           . (:background "#2c4a35"))
    (ediff-fine-diff-C           . (:background "#4a4a24"))
    (ediff-fine-diff-Ancestor    . (:background "#4a4a24"))
    (ediff-even-diff-A           . (:background "#0f333d"))
    (ediff-even-diff-B           . (:background "#0f333d"))
    (ediff-even-diff-C           . (:background "#0f333d"))
    (ediff-even-diff-Ancestor    . (:background "#0f333d"))
    (ediff-odd-diff-A            . (:background "#0f333d"))
    (ediff-odd-diff-B            . (:background "#0f333d"))
    (ediff-odd-diff-C            . (:background "#0f333d"))
    (ediff-odd-diff-Ancestor     . (:background "#0f333d")))
  "Alist mapping ediff diff faces to their softened remap spec.
Each spec sets only a background, so the buffer's font-lock foreground —
its syntax highlighting — shows through the diff highlight.  Tuned for
the solarized-dark background used in this configuration.")

(defun my-forge-ediff-review--dim-diff-faces ()
  "Buffer-locally soften ediff's diff faces in the current revision buffer.
Uses `face-remap-set-base' so each face keeps only a subtle background,
which lets syntax highlighting remain visible underneath the diff
highlight.  No-op unless a review session is active and
`my-forge-ediff-review-dim-diff-faces' is non-nil."
  (when (and my-forge-ediff-review-dim-diff-faces
             my-forge-ediff-review--session)
    (dolist (pair my-forge-ediff-review--dim-diff-faces)
      (face-remap-set-base (car pair) (cdr pair)))))

(defun my-forge-ediff-review--side-for-rev (rev)
  "Return \"LEFT\" / \"RIGHT\" for REV in the current session, or nil."
  (let ((s my-forge-ediff-review--session))
    (cond
     ((equal rev (plist-get s :base-rev)) "LEFT")
     ((equal rev (plist-get s :head-rev)) "RIGHT"))))

(defun my-forge-ediff-review--put-overlay (buf line glyph header body face)
  "Show BODY as a boxed annotation card below LINE in BUF.
GLYPH marks the entry kind, HEADER titles the card (author + timestamp
for existing comments, or a kind label for comments and memos) and FACE
paints the whole card.  The source line is untouched: the card is an
overlay `after-string' on a zero-width overlay anchored at end-of-line,
so it never shifts `display-line-numbers-mode' or `nlinum-mode' counts.
When `my-forge-ediff-review--cards-collapsed' is non-nil the card is a
one-line summary instead of the full box."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (let* ((eol (line-end-position))
             (ov (make-overlay eol eol nil t nil))
             (card (my-forge-ediff-review-model-format-card
                    glyph header body my-forge-ediff-review-card-width
                    my-forge-ediff-review--cards-collapsed)))
        (overlay-put ov 'my-forge-ediff-review t)
        (overlay-put ov 'priority 100)
        ;; Leave the leading newline unpropertized so no highlighted strip
        ;; bleeds to the window edge before the box; the card owns the face.
        (overlay-put ov 'after-string
                     (concat "\n" (propertize card 'face face)))))))

(defun my-forge-ediff-review--clear-overlays (&optional buf)
  "Remove all review overlays from BUF (defaults to current buffer)."
  (with-current-buffer (or buf (current-buffer))
    (remove-overlays (point-min) (point-max) 'my-forge-ediff-review t)))

(defun my-forge-ediff-review--reapply-overlays ()
  "Reapply comment and memo overlays in current buffer for its file/side."
  (when (and my-forge-ediff-review--session
             my-magit-ediff--buf-file
             my-magit-ediff--buf-rev)
    (my-forge-ediff-review--clear-overlays)
    (let* ((file my-magit-ediff--buf-file)
           (rev  my-magit-ediff--buf-rev)
           (side (my-forge-ediff-review--side-for-rev rev)))
      (when side
        (my-forge-ediff-review--put-existing-overlays
         (plist-get my-forge-ediff-review--session :existing) file side)
        (my-forge-ediff-review--put-side-overlays
         (plist-get my-forge-ediff-review--session :comments)
         file side "✎" "Comment" 'my-forge-ediff-review-comment-face)
        (my-forge-ediff-review--put-side-overlays
         (plist-get my-forge-ediff-review--session :memos)
         file side "▤" "Memo" 'my-forge-ediff-review-memo-face)))))

(defun my-forge-ediff-review--put-existing-overlays (entries file side)
  "Overlay existing review comments in ENTRIES matching FILE and SIDE.
Each card header carries the author, the comment's posting time and a
resolved marker so it is clearly distinguished from the reviewer's own
pending comments."
  (dolist (entry (my-forge-ediff-review-model-entries-for-side
                  entries file side))
    (let* ((author (or (plist-get entry :author) "reviewer"))
           (time (my-forge-ediff-review-model-format-time
                  (plist-get entry :created-at)))
           (resolved (if (plist-get entry :resolved) " (resolved)" ""))
           (header (concat author
                           (if (string-empty-p time) "" (concat "  " time))
                           resolved)))
      (my-forge-ediff-review--put-overlay
       (current-buffer)
       (plist-get entry :line)
       "◈" header
       (plist-get entry :body)
       'my-forge-ediff-review-existing-comment-face))))

(defun my-forge-ediff-review--put-side-overlays (entries file side glyph header face)
  "Overlay each of ENTRIES matching FILE and SIDE as a GLYPH/HEADER card.
FACE paints the card."
  (dolist (entry (my-forge-ediff-review-model-entries-for-side
                  entries file side))
    (my-forge-ediff-review--put-overlay
     (current-buffer)
     (plist-get entry :line)
     glyph header
     (plist-get entry :body)
     face)))

(defun my-forge-ediff-review--refresh-all-buffers ()
  "Reapply overlays in every revision buffer and redraw the sidebar."
  (dolist (buf my-magit-ediff--temp-buffers)
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (my-forge-ediff-review--reapply-overlays))))
  (my-forge-ediff-review--refresh-sidebar))

(defun my-forge-ediff-review-toggle-cards ()
  "Fold or unfold every inline comment card in the review.
Folded cards shrink to a one-line summary so a diff dense with comments
stays readable; unfolding restores the full boxed body."
  (interactive)
  (setq my-forge-ediff-review--cards-collapsed
        (not my-forge-ediff-review--cards-collapsed))
  (my-forge-ediff-review--refresh-all-buffers)
  (message "Review comment cards %s"
           (if my-forge-ediff-review--cards-collapsed "folded" "unfolded")))

(defvar-local my-forge-ediff-review--keys-installed nil
  "Non-nil once review navigation keys are installed in this buffer.
Guards against `ediff-prepare-buffer-hook' firing more than once on the
same buffer and stacking composed keymaps on top of each other.")

(defun my-forge-ediff-review--setup-revision-keys ()
  "Install buffer-local keys for in-place ediff navigation and commenting.
Only active when a review session is running and the buffer has the
file/rev locals set by `my-magit-ediff--create-revision-buffer'."
  (when (and my-forge-ediff-review--session
             my-magit-ediff--buf-file
             my-magit-ediff--buf-rev
             (not my-forge-ediff-review--keys-installed))
    (let ((map (make-composed-keymap nil (current-local-map))))
      (define-key map (kbd "RET") #'my-forge-ediff-review-add-comment)
      (define-key map (kbd "m") #'my-forge-ediff-review-add-memo)
      (define-key map (kbd "r") #'my-forge-ediff-review-reply-to-comment)
      (define-key map (kbd "R") #'my-forge-ediff-review-toggle-resolved)
      (define-key map (kbd "d") #'my-forge-ediff-review-toggle-reviewed)
      (define-key map (kbd "D") #'my-forge-ediff-review-show-description)
      (define-key map (kbd "c") #'my-forge-ediff-review-toggle-cards)
      (define-key map (kbd "n") #'my-forge-ediff-review-next-diff)
      (define-key map (kbd "p") #'my-forge-ediff-review-prev-diff)
      (define-key map (kbd "q") #'my-forge-ediff-review-quit-ediff)
      (use-local-map map)
      (setq-local my-forge-ediff-review--keys-installed t))))

(defun my-forge-ediff-review--prepare-buffer ()
  "Apply overlays and install nav/comment keys in the current revision buffer."
  (my-forge-ediff-review--reapply-overlays)
  (my-forge-ediff-review--setup-revision-keys)
  (my-forge-ediff-review--dim-diff-faces)
  (my-forge-ediff-review--refresh-sidebar))

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

;;;; Adding comments and memos

;; Comments and memos share one markdown editor and behave the same way:
;; a line carries at most one entry of each kind, reopening the editor
;; prefills the existing body for in-place editing, and saving it empty
;; removes it.  They differ only in which session list they land in
;; (:comments is submitted to GitHub, :memos stays local).
(defconst my-forge-ediff-review--kinds
  '((comment . (:key :comments :label "Comment"))
    (memo    . (:key :memos    :label "Memo")))
  "Per-kind metadata: session plist key and human label.")

(defvar my-forge-ediff-review--editor-ctx nil
  "Buffer-local context plist while editing a comment or memo.")

(defvar my-forge-ediff-review--editor-kind nil
  "Buffer-local kind symbol (`comment' or `memo') of the active editor.")

(defun my-forge-ediff-review--kind-key (kind)
  "Return the session plist key storing entries of KIND."
  (plist-get (alist-get kind my-forge-ediff-review--kinds) :key))

(defun my-forge-ediff-review--kind-label (kind)
  "Return the human-readable label for KIND."
  (plist-get (alist-get kind my-forge-ediff-review--kinds) :label))

(defun my-forge-ediff-review-add-comment ()
  "Add a PR review comment for the line at point in this ediff buffer.
Reopening the editor on the same line prefills the existing comment for
in-place editing; saving it empty removes it."
  (interactive)
  (my-forge-ediff-review--start-editor 'comment))

(defun my-forge-ediff-review-add-memo ()
  "Attach a local memo to the line at point.
Memos are never submitted to GitHub.  Editing the line again reopens the
existing memo; saving it empty removes it."
  (interactive)
  (my-forge-ediff-review--start-editor 'memo))

(defun my-forge-ediff-review--start-editor (kind)
  "Open the editor of KIND for the current line, validating context first."
  (my-forge-ediff-review--ensure-session)
  (let ((ctx (my-forge-ediff-review--current-context)))
    (unless ctx
      (user-error
       "Not in a review ediff revision buffer (no file/rev context)"))
    (my-forge-ediff-review--open-editor ctx kind)))

(defun my-forge-ediff-review--existing-entry-body (ctx kind)
  "Return the body of an existing entry of KIND at CTX, or nil."
  (let ((entry (my-forge-ediff-review-model-find-entry
                (plist-get my-forge-ediff-review--session
                           (my-forge-ediff-review--kind-key kind))
                (plist-get ctx :path)
                (plist-get ctx :line)
                (plist-get ctx :side))))
    (and entry (plist-get entry :body))))

(defun my-forge-ediff-review--open-editor (ctx kind)
  "Pop up a markdown editor for an entry of KIND described by CTX."
  (let ((buf (generate-new-buffer
              (format "*forge-review-%s*" kind)))
        (prefill (my-forge-ediff-review--existing-entry-body ctx kind)))
    (with-current-buffer buf
      (when (fboundp 'markdown-mode)
        (markdown-mode))
      (insert (format
               "<!-- %s for %s:%d (%s) — C-c C-c to save, C-c C-k to cancel. \
HTML comments are stripped. -->\n\n"
               (my-forge-ediff-review--kind-label kind)
               (plist-get ctx :path)
               (plist-get ctx :line)
               (plist-get ctx :side)))
      (when prefill
        (insert prefill))
      (setq-local my-forge-ediff-review--editor-ctx ctx)
      (setq-local my-forge-ediff-review--editor-kind kind)
      (local-set-key (kbd "C-c C-c") #'my-forge-ediff-review--save-entry)
      (local-set-key (kbd "C-c C-k") #'my-forge-ediff-review--cancel-entry)
      (goto-char (point-max)))
    (pop-to-buffer buf)))

(defun my-forge-ediff-review--strip-html-comments (text)
  "Remove `<!-- ... -->' blocks from TEXT."
  (replace-regexp-in-string "<!--\\(.\\|\n\\)*?-->" "" text))

(defun my-forge-ediff-review--save-entry ()
  "Finalize the comment/memo in the current editor buffer and store it."
  (interactive)
  (let* ((ctx my-forge-ediff-review--editor-ctx)
         (kind my-forge-ediff-review--editor-kind)
         (body (string-trim
                (my-forge-ediff-review--strip-html-comments
                 (buffer-string)))))
    (unless my-forge-ediff-review--session
      (user-error "Review session disappeared; not saving"))
    (my-forge-ediff-review--store-entry ctx kind body)
    (let ((buf (current-buffer)))
      (quit-window)
      (kill-buffer buf))
    (my-forge-ediff-review--refresh-all-buffers)
    (message "%s saved (%d pending)."
             (my-forge-ediff-review--kind-label kind)
             (length (plist-get my-forge-ediff-review--session
                                 (my-forge-ediff-review--kind-key kind))))))

(defun my-forge-ediff-review--store-entry (ctx kind body)
  "Store an entry of KIND with BODY at CTX into the session.
An entry replaces any existing entry of the same KIND on the same line
and side; an empty BODY removes it."
  (let* ((key (my-forge-ediff-review--kind-key kind))
         (entries (plist-get my-forge-ediff-review--session key))
         (existing (my-forge-ediff-review-model-find-entry
                    entries (plist-get ctx :path)
                    (plist-get ctx :line) (plist-get ctx :side))))
    (when existing
      (setq entries (my-forge-ediff-review-model-remove-entry
                     entries existing)))
    (setf (plist-get my-forge-ediff-review--session key)
          (if (string-empty-p body)
              entries
            (cons (append ctx (list :body body)) entries)))))

(defun my-forge-ediff-review--cancel-entry ()
  "Discard the in-progress comment/memo editor."
  (interactive)
  (let ((buf (current-buffer)))
    (quit-window)
    (kill-buffer buf))
  (message "Editing cancelled."))

;;;; Replying to existing review threads

(defvar my-forge-ediff-review--reply-target nil
  "Buffer-local entry plist of the existing comment being replied to.")

(defun my-forge-ediff-review--existing-at-point ()
  "Return the first existing review comment entry on the line at point, or nil."
  (let ((ctx (my-forge-ediff-review--current-context)))
    (and ctx
         (my-forge-ediff-review-model-find-entry
          (plist-get my-forge-ediff-review--session :existing)
          (plist-get ctx :path)
          (plist-get ctx :line)
          (plist-get ctx :side)))))

(defun my-forge-ediff-review-reply-to-comment ()
  "Reply to the existing review thread on the line at point.
The reply is posted immediately to GitHub; it is not part of the batch
of pending comments collected for a new review."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let ((entry (my-forge-ediff-review--existing-at-point)))
    (unless entry
      (user-error "No existing review comment on this line to reply to"))
    (unless (plist-get entry :reply-to-id)
      (user-error "This review comment cannot be replied to (no comment id)"))
    (my-forge-ediff-review--open-reply-editor entry)))

(defun my-forge-ediff-review--open-reply-editor (entry)
  "Pop up a markdown editor to reply to the thread described by ENTRY."
  (let ((buf (generate-new-buffer "*forge-review-reply*")))
    (with-current-buffer buf
      (when (fboundp 'markdown-mode)
        (markdown-mode))
      (insert (format
               "<!-- Reply to %s at %s:%d (%s) — C-c C-c to send, \
C-c C-k to cancel.  HTML comments are stripped. -->\n\n"
               (or (plist-get entry :author) "reviewer")
               (plist-get entry :path)
               (plist-get entry :line)
               (plist-get entry :side)))
      (setq-local my-forge-ediff-review--reply-target entry)
      (local-set-key (kbd "C-c C-c") #'my-forge-ediff-review--send-reply)
      (local-set-key (kbd "C-c C-k") #'my-forge-ediff-review--cancel-entry)
      (goto-char (point-max)))
    (pop-to-buffer buf)))

(defun my-forge-ediff-review--send-reply ()
  "POST the reply in the current editor buffer, then refresh existing threads."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let* ((entry my-forge-ediff-review--reply-target)
         (reply-to-id (plist-get entry :reply-to-id))
         (body (string-trim
                (my-forge-ediff-review--strip-html-comments
                 (buffer-string))))
         (s my-forge-ediff-review--session))
    (when (string-empty-p body)
      (user-error "Reply body is empty"))
    (ghub-post
     (format "/repos/%s/%s/pulls/%s/comments/%s/replies"
             (plist-get s :owner) (plist-get s :repo)
             (plist-get s :num) reply-to-id)
     `((body . ,body))
     :auth 'forge
     :host (plist-get s :host)
     :callback (lambda (_value &rest _)
                 (message "Reply sent.")
                 (my-forge-ediff-review--fetch-existing-threads))
     :errorback (lambda (err &rest _)
                  (message "Reply failed: %S" err)))
    (let ((buf (current-buffer)))
      (quit-window)
      (kill-buffer buf))))

;;;; Resolving / unresolving review threads

(defconst my-forge-ediff-review--resolve-mutation
  "mutation($threadId:ID!){
     resolveReviewThread(input:{threadId:$threadId}){ thread{ id isResolved } }
   }"
  "GraphQL mutation marking a review thread resolved.")

(defconst my-forge-ediff-review--unresolve-mutation
  "mutation($threadId:ID!){
     unresolveReviewThread(input:{threadId:$threadId}){ thread{ id isResolved } }
   }"
  "GraphQL mutation marking a review thread unresolved.")

(defun my-forge-ediff-review-toggle-resolved ()
  "Resolve or unresolve the existing review thread on the line at point."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let ((entry (my-forge-ediff-review--existing-at-point)))
    (unless entry
      (user-error "No existing review comment on this line"))
    (let ((thread-id (plist-get entry :thread-id)))
      (unless thread-id
        (user-error "This review comment has no thread id to resolve"))
      (my-forge-ediff-review--set-thread-resolved
       thread-id (not (plist-get entry :resolved))))))

(defun my-forge-ediff-review--set-thread-resolved (thread-id resolve)
  "Mark THREAD-ID resolved when RESOLVE is non-nil, else unresolved.
Refreshes the inline overlays once GitHub confirms the change."
  (let ((s my-forge-ediff-review--session))
    (ghub-query
     (if resolve
         my-forge-ediff-review--resolve-mutation
       my-forge-ediff-review--unresolve-mutation)
     `((threadId . ,thread-id))
     :auth 'forge
     :host (plist-get s :host)
     :callback (lambda (_value &rest _)
                 (message "Thread %s." (if resolve "resolved" "unresolved"))
                 (my-forge-ediff-review--fetch-existing-threads))
     :errorback (lambda (err &rest _)
                  (message "Could not update thread: %S" err)))))

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
      (comments . ,(my-forge-ediff-review-model-payload-comments comments)))))

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

;;;; Reviewed flag

(defun my-forge-ediff-review--toggle-reviewed-path (path)
  "Toggle the reviewed flag for PATH and redraw the sidebar."
  (my-forge-ediff-review--ensure-session)
  (setf (plist-get my-forge-ediff-review--session :reviewed)
        (my-forge-ediff-review-model-toggle-reviewed
         (plist-get my-forge-ediff-review--session :reviewed) path))
  (my-forge-ediff-review--refresh-sidebar)
  (message "%s marked %s." path
           (if (my-forge-ediff-review-model-reviewed-p
                (plist-get my-forge-ediff-review--session :reviewed) path)
               "reviewed" "not reviewed")))

(defun my-forge-ediff-review-toggle-reviewed ()
  "Toggle the reviewed flag for the file in the current revision buffer."
  (interactive)
  (my-forge-ediff-review--ensure-session)
  (let ((path my-magit-ediff--buf-file))
    (unless path
      (user-error "Not in a review ediff revision buffer"))
    (my-forge-ediff-review--toggle-reviewed-path path)))

;;;; File-list sidebar

(defconst my-forge-ediff-review--sidebar-name "*forge-review-files*"
  "Name of the buffer hosting the GitHub-style file-list sidebar.")

(defvar my-forge-ediff-review-sidebar-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'my-forge-ediff-review-sidebar-open)
    (define-key map (kbd "<mouse-1>") #'my-forge-ediff-review-sidebar-open)
    (define-key map (kbd "d") #'my-forge-ediff-review-sidebar-toggle-reviewed)
    (define-key map (kbd "D") #'my-forge-ediff-review-show-description)
    (define-key map (kbd "g") #'my-forge-ediff-review-sidebar-refresh)
    (define-key map (kbd "n") #'next-line)
    (define-key map (kbd "p") #'previous-line)
    (define-key map (kbd "q") #'my-forge-ediff-review-sidebar-quit)
    map)
  "Keymap for `my-forge-ediff-review-sidebar-mode'.")

(define-derived-mode my-forge-ediff-review-sidebar-mode special-mode
  "ReviewFiles"
  "Major mode for the forge ediff review file-list sidebar."
  (setq truncate-lines t))

(defun my-forge-ediff-review--file-counts (path)
  "Return a cons (COMMENT-COUNT . MEMO-COUNT) of entries for PATH."
  (cons (my-forge-ediff-review-model-count-for-file
         (plist-get my-forge-ediff-review--session :comments) path)
        (my-forge-ediff-review-model-count-for-file
         (plist-get my-forge-ediff-review--session :memos) path)))

(defun my-forge-ediff-review--insert-sidebar-file (file current-p reviewed-p)
  "Insert one sidebar line for FILE carrying its path as a text property.
CURRENT-P highlights the file open in ediff; REVIEWED-P picks the box."
  (let* ((counts (my-forge-ediff-review--file-counts file))
         (text (my-forge-ediff-review-model-format-file-line
                file current-p reviewed-p (car counts) (cdr counts)))
         (start (point)))
    (insert text "\n")
    (put-text-property start (point) 'my-forge-ediff-review-file file)
    (when current-p
      (put-text-property start (point) 'face 'highlight))))

(defun my-forge-ediff-review--render-sidebar ()
  "Rebuild the sidebar buffer from session and engine state."
  (let ((buffer (get-buffer-create my-forge-ediff-review--sidebar-name))
        (reviewed (plist-get my-forge-ediff-review--session :reviewed))
        (current my-magit-ediff--current-index))
    (with-current-buffer buffer
      (unless (derived-mode-p 'my-forge-ediff-review-sidebar-mode)
        (my-forge-ediff-review-sidebar-mode))
      (let ((saved-line (line-number-at-pos))
            (inhibit-read-only t)
            (index 0))
        (erase-buffer)
        (insert (propertize
                 (format "PR #%s  reviewed %d/%d\n"
                         (plist-get my-forge-ediff-review--session :num)
                         (length reviewed)
                         (length my-magit-ediff--files))
                 'face 'bold))
        (let ((title (plist-get my-forge-ediff-review--session :title)))
          (when (and title (not (string-empty-p title)))
            ;; Show the whole title.  The sidebar sets `truncate-lines',
            ;; so a long title would be clipped at the window edge; wrap
            ;; it to the side-window width instead so nothing is hidden.
            (dolist (line (my-forge-ediff-review-model--wrap-text title 36))
              (insert (propertize line 'face 'bold) "\n"))))
        (insert (propertize "D: description\n\n" 'face 'shadow))
        (dolist (file my-magit-ediff--files)
          (my-forge-ediff-review--insert-sidebar-file
           file (= index current)
           (my-forge-ediff-review-model-reviewed-p reviewed file))
          (setq index (1+ index)))
        (goto-char (point-min))
        (forward-line (1- saved-line))))))

(defun my-forge-ediff-review--show-sidebar ()
  "Display the file-list sidebar in a persistent left side window.
The `no-delete-other-windows' parameter keeps it alive across ediff's
own window reconfiguration."
  (my-forge-ediff-review--render-sidebar)
  (display-buffer-in-side-window
   (get-buffer my-forge-ediff-review--sidebar-name)
   '((side . left)
     (slot . 0)
     (window-width . 38)
     (window-parameters . ((no-delete-other-windows . t))))))

(defun my-forge-ediff-review--refresh-sidebar ()
  "Redraw the sidebar when it exists."
  (let ((buffer (get-buffer my-forge-ediff-review--sidebar-name)))
    (when (buffer-live-p buffer)
      (my-forge-ediff-review--render-sidebar))))

(defun my-forge-ediff-review--sidebar-file-at-point ()
  "Return the file on the current sidebar line or signal an error."
  (or (get-text-property (point) 'my-forge-ediff-review-file)
      (user-error "No file on this line")))

(defun my-forge-ediff-review-sidebar-open ()
  "Open ediff for the file on the current sidebar line."
  (interactive)
  (let* ((file (my-forge-ediff-review--sidebar-file-at-point))
         (index (seq-position my-magit-ediff--files file #'string=)))
    (when index
      (my-magit-ediff-goto-index index))))

(defun my-forge-ediff-review-sidebar-toggle-reviewed ()
  "Toggle the reviewed flag for the file on the current sidebar line."
  (interactive)
  (my-forge-ediff-review--toggle-reviewed-path
   (my-forge-ediff-review--sidebar-file-at-point)))

(defun my-forge-ediff-review-sidebar-refresh ()
  "Redraw the sidebar on demand."
  (interactive)
  (my-forge-ediff-review--render-sidebar))

(defun my-forge-ediff-review-sidebar-quit ()
  "End the review session.  Quit the open diff first if one is shown."
  (interactive)
  (let ((control my-magit-ediff--control-buffer))
    (if (and control (buffer-live-p control))
        (message "Quit the current diff first (press q in it), then q here.")
      (my-magit-ediff--cleanup)
      (message "Review ended."))))

;;;; Lifecycle wiring between the engine and the sidebar

(defun my-forge-ediff-review--navigation ()
  "Keep the sidebar in control after a file is quit, instead of prompting."
  (my-forge-ediff-review--render-sidebar)
  (let ((window (get-buffer-window my-forge-ediff-review--sidebar-name)))
    (when (window-live-p window)
      (select-window window))))

(defun my-forge-ediff-review--on-cleanup ()
  "Tear down the sidebar and review session when the engine cleans up."
  (let ((buffer (get-buffer my-forge-ediff-review--sidebar-name)))
    (when (buffer-live-p buffer)
      (let ((window (get-buffer-window buffer)))
        (when (window-live-p window)
          (ignore-errors (delete-window window))))
      (kill-buffer buffer)))
  (setq my-magit-ediff-navigation-function
        #'my-magit-ediff--prompt-navigation)
  (remove-hook 'my-magit-ediff-start-hook
               #'my-forge-ediff-review--show-sidebar)
  (remove-hook 'my-magit-ediff-cleanup-hook
               #'my-forge-ediff-review--on-cleanup)
  (setq my-forge-ediff-review--session nil))

(defun my-forge-ediff-review--install-sidebar-hooks ()
  "Route engine navigation and cleanup through the review sidebar."
  (setq my-magit-ediff-navigation-function
        #'my-forge-ediff-review--navigation)
  (add-hook 'my-magit-ediff-start-hook
            #'my-forge-ediff-review--show-sidebar)
  (add-hook 'my-magit-ediff-cleanup-hook
            #'my-forge-ediff-review--on-cleanup))

(provide 'my-forge-ediff-review)
;;; my-forge-ediff-review.el ends here
