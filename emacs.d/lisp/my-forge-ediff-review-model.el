;;; my-forge-ediff-review-model.el --- Pure data model for ediff review -*- lexical-binding: t; -*-

;;; Commentary:
;; Pure, side-effect-free helpers backing `my-forge-ediff-review'.  They
;; operate only on plain Lisp values (lists of plists, lists of paths) and
;; depend on nothing heavier than `cl-lib', so they can be unit-tested in
;; batch without loading magit/forge/ghub.
;;
;; Two kinds of per-line "entry" share the same plist shape and helpers:
;;   - review comments, which are submitted to GitHub, and
;;   - memos, which stay local and are never submitted.
;; Each entry is (:path "rel/path" :line N :side "LEFT"|"RIGHT" :body "...").
;;
;; The reviewed flag is tracked separately as a plain list of file paths.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'iso8601)

;;;; Reviewed flag

(defun my-forge-ediff-review-model-reviewed-p (reviewed-paths path)
  "Return non-nil when PATH appears in REVIEWED-PATHS."
  (and (member path reviewed-paths) t))

(defun my-forge-ediff-review-model-toggle-reviewed (reviewed-paths path)
  "Return a new list like REVIEWED-PATHS with PATH toggled.
PATH is removed when already present and added otherwise.  The input
list is not modified."
  (if (member path reviewed-paths)
      (remove path reviewed-paths)
    (cons path reviewed-paths)))

;;;; Entry lookup (comments and memos)

(defun my-forge-ediff-review-model-find-entry (entries path line side)
  "Return the first entry in ENTRIES matching PATH, LINE and SIDE, or nil."
  (cl-find-if
   (lambda (entry)
     (and (equal (plist-get entry :path) path)
          (eql (plist-get entry :line) line)
          (equal (plist-get entry :side) side)))
   entries))

(defun my-forge-ediff-review-model-remove-entry (entries entry)
  "Return ENTRIES without ENTRY, comparing with `eq'."
  (cl-remove entry entries :count 1 :test #'eq))

(defun my-forge-ediff-review-model-count-for-file (entries path)
  "Return how many entries in ENTRIES have :path equal to PATH, any side."
  (cl-count-if (lambda (entry) (equal (plist-get entry :path) path))
               entries))

(defun my-forge-ediff-review-model-entries-for-side (entries path side)
  "Return entries in ENTRIES whose :path is PATH and :side is SIDE."
  (cl-remove-if-not
   (lambda (entry)
     (and (equal (plist-get entry :path) path)
          (equal (plist-get entry :side) side)))
   entries))

;;;; Sidebar line formatting

(defun my-forge-ediff-review-model--counts-suffix (comment-count memo-count)
  "Return a trailing count string for COMMENT-COUNT and MEMO-COUNT.
Empty when both are zero so untouched files stay visually quiet."
  (if (and (zerop comment-count) (zerop memo-count))
      ""
    (format " [%dc/%dm]" comment-count memo-count)))

(defun my-forge-ediff-review-model-format-file-line
    (file current-p reviewed-p comment-count memo-count)
  "Return the sidebar text line for FILE.
CURRENT-P marks the file shown in ediff with a leading caret.
REVIEWED-P selects the checkbox glyph.  COMMENT-COUNT and MEMO-COUNT are
appended only when non-zero."
  (let ((pointer (if current-p "> " "  "))
        (checkbox (if reviewed-p "[x] " "[ ] ")))
    (concat pointer checkbox file
            (my-forge-ediff-review-model--counts-suffix
             comment-count memo-count))))

;;;; Commit history

(defun my-forge-ediff-review-model-parse-commit-line (line)
  "Parse one NUL-separated `git log' LINE into a commit plist.
LINE comes from `git log --format=%h%x00%s' and looks like
\"abc1234\\0Subject text\".  Returns (:hash HASH :subject SUBJECT), or
nil when LINE carries no NUL separator so malformed output is dropped
instead of rendering a broken sidebar row."
  (when (and (stringp line) (string-match-p "\0" line))
    (let* ((parts (split-string line "\0"))
           (hash (car parts))
           (subject (mapconcat #'identity (cdr parts) "\0")))
      (list :hash hash :subject subject))))

(defun my-forge-ediff-review-model-format-commit-line (hash subject)
  "Return the sidebar text line for the commit HASH titled SUBJECT.
Indented to line up with the file lines built by
`my-forge-ediff-review-model-format-file-line'.  A long SUBJECT is not
truncated here; the sidebar's `truncate-lines' clips it at the window
edge, matching how the PR title is shown."
  (format "  %s %s" (or hash "") (or subject "")))

;;;; Inline comment card formatting

;; Comment bodies are rendered as a box-drawn "card" placed below the
;; source line.  Every visual line is padded to the same display width so
;; a single background face paints a clean rectangle rather than ragged
;; text (the trick borrowed from annotate.el).  These helpers are pure
;; strings-in/strings-out so they can be unit-tested without ediff.

(defun my-forge-ediff-review-model--pad (str width)
  "Right-pad STR with spaces to WIDTH display columns.
Width is measured with `string-width', so a wide glyph counts as two
columns.  STR is returned unchanged when already at least WIDTH wide."
  (let ((w (string-width str)))
    (if (>= w width)
        str
      (concat str (make-string (- width w) ?\s)))))

(defun my-forge-ediff-review-model--wrap-text (text width)
  "Word-wrap TEXT to WIDTH columns, returning a list of lines.
Newlines already in TEXT are kept as hard breaks so blank lines between
markdown paragraphs survive.  A single word wider than WIDTH is emitted
on its own line rather than split."
  (let (out)
    (dolist (para (split-string (or text "") "\n"))
      (if (string-empty-p para)
          (push "" out)
        (let ((cur "") (col 0))
          (dolist (word (split-string para "[ \t]+" t))
            (let ((wl (string-width word)))
              (cond
               ((string-empty-p cur) (setq cur word col wl))
               ((<= (+ col 1 wl) width)
                (setq cur (concat cur " " word) col (+ col 1 wl)))
               (t (push cur out) (setq cur word col wl)))))
          (push cur out))))
    (nreverse out)))

(defun my-forge-ediff-review-model--card-summary (glyph header body)
  "Return a one-line summary string for a collapsed card.
Combines GLYPH, HEADER and the first non-empty line of BODY.  When BODY
carries more than that one line, a trailing ellipsis marks the hidden
content so the fold reads as intentional rather than a lost body."
  (let* ((lines (seq-remove #'string-empty-p
                            (split-string (or body "") "\n")))
         (first (car lines))
         (more (> (length lines) 1)))
    (concat glyph " " header
            (if (and first (not (string-empty-p first)))
                (concat ": " first)
              "")
            (if more " …" ""))))

(defun my-forge-ediff-review-model-format-card
    (glyph header body width &optional collapsed)
  "Return a box-drawn annotation card string for HEADER and BODY.
GLYPH is a short per-kind marker shown in the header and WIDTH is the
inner content width in columns.  Every returned line is padded to the
same display width so a single background face paints a clean rectangle;
the string has no leading or trailing newline.  When COLLAPSED is
non-nil a single compact summary line is returned instead of the full
box, so line-number safety is unchanged either way."
  (if collapsed
      ;; A right-pointing triangle reads as "expandable/folded" so a
      ;; one-line summary is not mistaken for a broken multi-line body.
      (concat "▸ "
              (my-forge-ediff-review-model--pad
               (truncate-string-to-width
                (my-forge-ediff-review-model--card-summary glyph header body)
                (1+ width) nil nil "…")
               (1+ width))
              " ")
    (let* ((header-line (concat glyph " " header))
           (text (if (string-empty-p (string-trim (or body "")))
                     " "
                   body))
           (lines (or (my-forge-ediff-review-model--wrap-text text width)
                      '("")))
           ;; Grow the box to the widest line so the header (author +
           ;; timestamp) is never clipped and every row stays rectangular.
           (inner (apply #'max width
                         (mapcar #'string-width (cons header-line lines))))
           (rule (make-string (+ inner 2) ?─)))
      (mapconcat
       #'identity
       (append
        (list (concat "╭" rule "╮")
              (concat "│ " (my-forge-ediff-review-model--pad header-line inner)
                      " │")
              (concat "├" rule "┤"))
        (mapcar (lambda (l)
                  (concat "│ " (my-forge-ediff-review-model--pad l inner)
                          " │"))
                lines)
        (list (concat "╰" rule "╯")))
       "\n"))))

;;;; PR description formatting

(defun my-forge-ediff-review-model-format-description (num title body)
  "Return the markdown text describing PR NUM titled TITLE with BODY.
Shown in the read-only description buffer.  A nil or blank BODY renders
as \"(no description)\" so the buffer never looks broken or truncated."
  (format "# PR #%s: %s\n\n%s\n"
          num
          (or title "")
          (if (and (stringp body)
                   (not (string-empty-p (string-trim body))))
              body
            "(no description)")))

(defun my-forge-ediff-review-model--format-comment (comment)
  "Return the markdown section for one conversation COMMENT.
COMMENT is a plist (:author :body :created-at).  The body is emitted
verbatim, only stripped of trailing blank lines, so that whatever
markdown the author wrote still renders."
  (let ((author (or (plist-get comment :author) "unknown"))
        (time (my-forge-ediff-review-model-format-time
               (plist-get comment :created-at)))
        (body (or (plist-get comment :body) "")))
    (concat "\n### " author
            (if (string-empty-p time) "" (concat " \u2014 " time))
            "\n\n"
            (if (string-empty-p (string-trim body))
                "(empty comment)"
              (string-trim-right body))
            "\n")))

(defun my-forge-ediff-review-model-format-conversation
    (num title body comments)
  "Return the markdown text of PR NUM's conversation, titled TITLE.
BODY is the PR description and COMMENTS the list of plists from
`my-forge-ediff-review-model-parse-conversation', oldest first.  The
header reuses `my-forge-ediff-review-model-format-description' so the
description buffer's opening is unchanged.  Comment bodies are laid out
as plain markdown sections rather than the box-drawn cards used for
inline overlays: a box would re-wrap the text to a fixed width and break
the code blocks, lists and quotes people write in PR discussions."
  (concat
   (my-forge-ediff-review-model-format-description num title body)
   "\n"
   (if (null comments)
       "## Comments\n\nNo comments yet.\n"
     (concat
      (format "## Comments (%d)\n" (length comments))
      (mapconcat #'my-forge-ediff-review-model--format-comment comments "")))
   (format "\n-- PR #%s \u00b7 g to refresh --\n" num)))

(defun my-forge-ediff-review-model-format-time (iso)
  "Return a short local-time string for GitHub ISO8601 timestamp ISO.
ISO looks like \"2026-01-15T10:30:00Z\".  A nil or empty ISO yields the
empty string so callers can omit the time without extra whitespace.  An
unparsable ISO yields the empty string too, rather than signalling: a
timestamp is decoration, and a single odd value coming from forge's
local database must not abort the rendering of a whole buffer."
  (if (and (stringp iso) (not (string-empty-p iso)))
      (condition-case nil
          (format-time-string "%Y-%m-%d %H:%M"
                              (encode-time (iso8601-parse iso)))
        (error ""))
    ""))

;;;; GitHub review payload

(defun my-forge-ediff-review-model-payload-comments (comments)
  "Return a vector of GitHub review comment alists built from COMMENTS.
Memos are never passed here, so they cannot leak into a submission."
  (vconcat
   (mapcar
    (lambda (comment)
      `((path . ,(plist-get comment :path))
        (line . ,(plist-get comment :line))
        (side . ,(plist-get comment :side))
        (body . ,(plist-get comment :body))))
    comments)))

;;;; Existing review threads (parsed from GitHub GraphQL)

(defun my-forge-ediff-review-model--graphql-nodes (container key)
  "Return the `nodes' of CONTAINER's KEY field as a list.
GraphQL arrays decode as either lists or vectors depending on the JSON
reader, so the result is normalized to a list."
  (append (alist-get 'nodes (alist-get key container)) nil))

(defun my-forge-ediff-review-model--truthy-p (value)
  "Return non-nil when a decoded JSON VALUE represents boolean true.
Handles the `:json-false' / nil falsey conventions of the JSON readers."
  (and value (not (eq value :json-false))))

(defun my-forge-ediff-review-model--response-data (response)
  "Return the `data' payload of a GraphQL RESPONSE regardless of wrapping.
`ghub-graphql' hands its async callback the root cons `(data . PAYLOAD)'
whose car is the symbol `data', while a fully wrapped response is the
alist `((data . PAYLOAD))'.  Both resolve to PAYLOAD here."
  (if (eq (car-safe response) 'data)
      (cdr response)
    (alist-get 'data response)))

(defun my-forge-ediff-review-model-parse-review-threads (response)
  "Parse a GitHub reviewThreads GraphQL RESPONSE into overlay entries.
Each entry is a plist (:path :line :side :body :author :created-at
:resolved :thread-id :reply-to-id) where :side is \"LEFT\"/\"RIGHT\" and
:resolved reflects the thread.  :created-at is the comment's ISO8601
timestamp.  :thread-id and :reply-to-id identify the thread and
its first comment so replies can be posted to it.  GitHub
exposes `path', `line', `originalLine' and `diffSide' on the thread, not
on `PullRequestReviewComment', so the location is read from the thread
and only the body/author come from each comment.  A thread with no
resolvable line (neither `line' nor `originalLine') is skipped, and
entries keep their thread/comment order."
  (let* ((data (my-forge-ediff-review-model--response-data response))
         (pullreq (alist-get 'pullRequest (alist-get 'repository data)))
         (threads (my-forge-ediff-review-model--graphql-nodes
                   pullreq 'reviewThreads))
         (entries nil))
    (dolist (thread threads (nreverse entries))
      (let* ((resolved (my-forge-ediff-review-model--truthy-p
                        (alist-get 'isResolved thread)))
             (thread-id (alist-get 'id thread))
             (path (alist-get 'path thread))
             (line (or (alist-get 'line thread)
                       (alist-get 'originalLine thread)))
             (side (alist-get 'diffSide thread))
             (comments (my-forge-ediff-review-model--graphql-nodes
                        thread 'comments))
             (reply-to-id (alist-get 'databaseId (car comments))))
        (when (and path line side)
          (dolist (comment comments)
            (let ((body (alist-get 'body comment))
                  (author (alist-get 'login (alist-get 'author comment)))
                  (created-at (alist-get 'createdAt comment)))
              (push (list :path path :line line :side side :body body
                          :author author :created-at created-at
                          :resolved resolved
                          :thread-id thread-id :reply-to-id reply-to-id)
                    entries))))))))

;;;; Conversation comments (parsed from GitHub GraphQL)

(defun my-forge-ediff-review-model-parse-conversation (response)
  "Parse a GitHub pull-request comments GraphQL RESPONSE into comment plists.
Each entry is a plist (:id :author :body :created-at :url) describing one
conversation-tab comment, kept in the order GitHub returned them, which
is oldest first.  These are `IssueComment' objects -- the PR-level
discussion -- and not the inline review comments handled by
`my-forge-ediff-review-model-parse-review-threads'.  A comment whose
author was deleted carries no `author' object, so :author falls back to
\"unknown\" instead of rendering an empty byline."
  (let* ((data (my-forge-ediff-review-model--response-data response))
         (pullreq (alist-get 'pullRequest (alist-get 'repository data))))
    (mapcar
     (lambda (comment)
       (list :id (alist-get 'id comment)
             :author (or (alist-get 'login (alist-get 'author comment))
                         "unknown")
             :body (alist-get 'body comment)
             :created-at (alist-get 'createdAt comment)
             :url (alist-get 'url comment)))
     (my-forge-ediff-review-model--graphql-nodes pullreq 'comments))))

(defun my-forge-ediff-review-model-parse-pr-node-id (response)
  "Return the pull request's GraphQL node id from RESPONSE, or nil.
The node id is what GitHub's GraphQL mutations take as `pullRequestId',
so it is worth keeping once the conversation query has fetched it."
  (let* ((data (my-forge-ediff-review-model--response-data response))
         (pullreq (alist-get 'pullRequest (alist-get 'repository data))))
    (alist-get 'id pullreq)))

;;;; API host resolution

(defun my-forge-ediff-review-model-resolve-host (apihost)
  "Return the ghub `:host' value for a forge repository's APIHOST.
APIHOST is the repository's `apihost' slot: \"api.github.com\" for
github.com or, for a GitHub Enterprise instance, that instance's API
host such as \"ghe.example.com/api/v3\".  A nil or empty APIHOST yields
nil, which lets ghub fall back to its own default host."
  (and (stringp apihost)
       (not (string-empty-p apihost))
       apihost))

(provide 'my-forge-ediff-review-model)
;;; my-forge-ediff-review-model.el ends here
