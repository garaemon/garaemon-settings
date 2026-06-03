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
Each entry is a plist (:path :line :side :body :author :resolved) where
:side is \"LEFT\"/\"RIGHT\" and :resolved reflects the thread.  A comment
with no resolvable line (neither `line' nor `originalLine') is skipped,
and entries keep their thread/comment order."
  (let* ((data (my-forge-ediff-review-model--response-data response))
         (pullreq (alist-get 'pullRequest (alist-get 'repository data)))
         (threads (my-forge-ediff-review-model--graphql-nodes
                   pullreq 'reviewThreads))
         (entries nil))
    (dolist (thread threads (nreverse entries))
      (let ((resolved (my-forge-ediff-review-model--truthy-p
                       (alist-get 'isResolved thread)))
            (comments (my-forge-ediff-review-model--graphql-nodes
                       thread 'comments)))
        (dolist (comment comments)
          (let ((path (alist-get 'path comment))
                (line (or (alist-get 'line comment)
                          (alist-get 'originalLine comment)))
                (side (alist-get 'diffSide comment))
                (body (alist-get 'body comment))
                (author (alist-get 'login (alist-get 'author comment))))
            (when (and path line side)
              (push (list :path path :line line :side side :body body
                          :author author :resolved resolved)
                    entries))))))))

(provide 'my-forge-ediff-review-model)
;;; my-forge-ediff-review-model.el ends here
