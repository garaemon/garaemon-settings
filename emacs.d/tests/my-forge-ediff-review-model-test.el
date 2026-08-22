;;; my-forge-ediff-review-model-test.el --- Tests for review model -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for the pure data-model helpers in
;; `my-forge-ediff-review-model'.  These helpers have no dependency on
;; magit/forge/ghub, so they can be exercised in batch with:
;;
;;   emacs -batch -L lisp -l tests/my-forge-ediff-review-model-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'my-forge-ediff-review-model)

;;;; Reviewed flag (per-file path set)

(ert-deftest review-model-should-report-not-reviewed-when-absent ()
  (should-not (my-forge-ediff-review-model-reviewed-p '() "a.el"))
  (should-not (my-forge-ediff-review-model-reviewed-p '("b.el") "a.el")))

(ert-deftest review-model-should-report-reviewed-when-present ()
  (should (my-forge-ediff-review-model-reviewed-p '("a.el" "b.el") "a.el")))

(ert-deftest review-model-toggle-should-add-missing-path ()
  (should (equal '("a.el")
                 (my-forge-ediff-review-model-toggle-reviewed '() "a.el"))))

(ert-deftest review-model-toggle-should-remove-present-path ()
  (should (equal '("b.el")
                 (my-forge-ediff-review-model-toggle-reviewed
                  '("a.el" "b.el") "a.el"))))

(ert-deftest review-model-toggle-should-not-mutate-input ()
  (let ((original '("a.el")))
    (my-forge-ediff-review-model-toggle-reviewed original "b.el")
    (should (equal '("a.el") original))))

;;;; Entry lookup (comments and memos share this shape)

(defun review-model-test--entry (path line side body)
  "Build a test entry plist."
  (list :path path :line line :side side :body body))

(ert-deftest review-model-find-entry-should-match-path-line-side ()
  (let* ((target (review-model-test--entry "a.el" 10 "RIGHT" "hi"))
         (entries (list target
                        (review-model-test--entry "a.el" 11 "RIGHT" "no")
                        (review-model-test--entry "a.el" 10 "LEFT" "no"))))
    (should (eq target
                (my-forge-ediff-review-model-find-entry
                 entries "a.el" 10 "RIGHT")))))

(ert-deftest review-model-find-entry-should-return-nil-when-absent ()
  (should-not (my-forge-ediff-review-model-find-entry
               (list (review-model-test--entry "a.el" 10 "RIGHT" "hi"))
               "a.el" 99 "RIGHT")))

(ert-deftest review-model-remove-entry-should-drop-only-target ()
  (let* ((keep (review-model-test--entry "a.el" 11 "RIGHT" "keep"))
         (drop (review-model-test--entry "a.el" 10 "RIGHT" "drop"))
         (entries (list drop keep)))
    (should (equal (list keep)
                   (my-forge-ediff-review-model-remove-entry entries drop)))))

;;;; Per-file counts and per-side filtering

(ert-deftest review-model-count-for-file-should-count-both-sides ()
  (let ((entries (list (review-model-test--entry "a.el" 1 "LEFT" "x")
                       (review-model-test--entry "a.el" 2 "RIGHT" "y")
                       (review-model-test--entry "b.el" 3 "RIGHT" "z"))))
    (should (= 2 (my-forge-ediff-review-model-count-for-file entries "a.el")))
    (should (= 1 (my-forge-ediff-review-model-count-for-file entries "b.el")))
    (should (= 0 (my-forge-ediff-review-model-count-for-file entries "c.el")))))

(ert-deftest review-model-entries-for-side-should-filter-path-and-side ()
  (let* ((match (review-model-test--entry "a.el" 2 "RIGHT" "y"))
         (entries (list (review-model-test--entry "a.el" 1 "LEFT" "x")
                        match
                        (review-model-test--entry "b.el" 2 "RIGHT" "z"))))
    (should (equal (list match)
                   (my-forge-ediff-review-model-entries-for-side
                    entries "a.el" "RIGHT")))))

;;;; Sidebar line formatting

(ert-deftest review-model-format-line-should-mark-current-file ()
  (let ((line (my-forge-ediff-review-model-format-file-line
               "a.el" t nil 0 0)))
    (should (string-prefix-p ">" line))))

(ert-deftest review-model-format-line-should-not-mark-other-files ()
  (let ((line (my-forge-ediff-review-model-format-file-line
               "a.el" nil nil 0 0)))
    (should-not (string-prefix-p ">" (string-trim-left line)))
    (should (string-match-p "a.el" line))))

(ert-deftest review-model-format-line-should-show-reviewed-checkbox ()
  (should (string-match-p "\\[x\\]"
                          (my-forge-ediff-review-model-format-file-line
                           "a.el" nil t 0 0)))
  (should (string-match-p "\\[ \\]"
                          (my-forge-ediff-review-model-format-file-line
                           "a.el" nil nil 0 0))))

(ert-deftest review-model-format-line-should-show-counts-when-nonzero ()
  (let ((line (my-forge-ediff-review-model-format-file-line
               "a.el" nil nil 2 1)))
    (should (string-match-p "2c" line))
    (should (string-match-p "1m" line))))

(ert-deftest review-model-format-line-should-hide-counts-when-zero ()
  (let ((line (my-forge-ediff-review-model-format-file-line
               "a.el" nil nil 0 0)))
    (should-not (string-match-p "0c" line))
    (should-not (string-match-p "0m" line))))

;;;; Commit history

(ert-deftest review-model-parse-commit-line-should-split-on-nul ()
  (let ((commit (my-forge-ediff-review-model-parse-commit-line
                 "abc1234\0Fix the frobnicator")))
    (should (equal "abc1234" (plist-get commit :hash)))
    (should (equal "Fix the frobnicator" (plist-get commit :subject)))))

(ert-deftest review-model-parse-commit-line-should-reject-line-without-nul ()
  (should-not (my-forge-ediff-review-model-parse-commit-line "not a commit"))
  (should-not (my-forge-ediff-review-model-parse-commit-line nil)))

(ert-deftest review-model-format-commit-line-should-show-hash-and-subject ()
  (let ((line (my-forge-ediff-review-model-format-commit-line
               "abc1234" "Fix the frobnicator")))
    (should (string-match-p "abc1234" line))
    (should (string-match-p "Fix the frobnicator" line))))

(ert-deftest review-model-format-commit-line-should-align-with-file-lines ()
  ;; Same two-column indent as a non-current file line's pointer gutter.
  (should (string-prefix-p "  " (my-forge-ediff-review-model-format-commit-line
                                 "abc1234" "subject"))))

;;;; GitHub review payload (memos must never reach this)

(ert-deftest review-model-payload-should-build-comment-vector ()
  (let* ((comments (list (review-model-test--entry "a.el" 10 "RIGHT" "body")))
         (payload (my-forge-ediff-review-model-payload-comments comments)))
    (should (vectorp payload))
    (should (= 1 (length payload)))
    (let ((c (aref payload 0)))
      (should (equal "a.el" (alist-get 'path c)))
      (should (= 10 (alist-get 'line c)))
      (should (equal "RIGHT" (alist-get 'side c)))
      (should (equal "body" (alist-get 'body c))))))

;;;; Existing review thread parsing (GitHub GraphQL response)

(defun my-forge-ediff-review-model-test--threads-response (thread-nodes)
  "Wrap THREAD-NODES in the reviewThreads GraphQL response envelope."
  `((data
     (repository
      (pullRequest
       (reviewThreads
        (nodes . ,thread-nodes)))))))

(defun my-forge-ediff-review-model-test--comment (body author &optional created-at)
  "Build one review comment node carrying BODY, AUTHOR login and CREATED-AT.
GitHub exposes `path'/`line'/`diffSide' on the thread, so a comment node
holds only the body, author and (when given) the ISO8601 `createdAt'."
  `((body . ,body)
    ,@(when created-at `((createdAt . ,created-at)))
    (author (login . ,author))))

(defun my-forge-ediff-review-model-test--thread (resolved location comment-nodes)
  "Build one reviewThread node with RESOLVED, LOCATION and COMMENT-NODES.
LOCATION is an alist providing the thread-level `path', `line',
`originalLine' and `diffSide' fields."
  `((isResolved . ,resolved)
    ,@location
    (comments (nodes . ,comment-nodes))))

(ert-deftest review-model-should-parse-a-review-comment-into-an-entry ()
  (let* ((response
          (my-forge-ediff-review-model-test--threads-response
           (vector
            (my-forge-ediff-review-model-test--thread
             :json-false
             '((path . "src/a.el") (line . 12) (originalLine . 9)
               (diffSide . "RIGHT"))
             (vector (my-forge-ediff-review-model-test--comment
                      "looks off" "octocat"))))))
         (entries (my-forge-ediff-review-model-parse-review-threads response))
         (entry (car entries)))
    (should (= 1 (length entries)))
    (should (equal "src/a.el" (plist-get entry :path)))
    (should (= 12 (plist-get entry :line)))
    (should (equal "RIGHT" (plist-get entry :side)))
    (should (equal "looks off" (plist-get entry :body)))
    (should (equal "octocat" (plist-get entry :author)))
    (should-not (plist-get entry :resolved))))

(ert-deftest review-model-should-fall-back-to-original-line-when-line-null ()
  (let* ((response
          (my-forge-ediff-review-model-test--threads-response
           (vector
            (my-forge-ediff-review-model-test--thread
             :json-false
             '((path . "a.el") (line) (originalLine . 7) (diffSide . "LEFT"))
             (vector (my-forge-ediff-review-model-test--comment "x" "u"))))))
         (entry (car (my-forge-ediff-review-model-parse-review-threads
                      response))))
    (should (= 7 (plist-get entry :line)))))

(ert-deftest review-model-should-mark-entry-resolved ()
  (let* ((response
          (my-forge-ediff-review-model-test--threads-response
           (vector
            (my-forge-ediff-review-model-test--thread
             t
             '((path . "a.el") (line . 1) (diffSide . "RIGHT"))
             (vector (my-forge-ediff-review-model-test--comment "done" "u"))))))
         (entry (car (my-forge-ediff-review-model-parse-review-threads
                      response))))
    (should (plist-get entry :resolved))))

(ert-deftest review-model-should-skip-thread-without-line ()
  (let* ((response
          (my-forge-ediff-review-model-test--threads-response
           (vector
            (my-forge-ediff-review-model-test--thread
             :json-false
             '((path . "a.el") (line) (originalLine) (diffSide . "RIGHT"))
             (vector (my-forge-ediff-review-model-test--comment
                      "outdated" "u"))))))
         (entries (my-forge-ediff-review-model-parse-review-threads
                   response)))
    (should (null entries))))

(ert-deftest review-model-should-return-empty-for-no-threads ()
  (should (null (my-forge-ediff-review-model-parse-review-threads
                 (my-forge-ediff-review-model-test--threads-response
                  (vector))))))

(ert-deftest review-model-should-parse-ghub-async-callback-root ()
  ;; `ghub-graphql' hands its async callback the root cons `(data . PAYLOAD)'
  ;; rather than the fully wrapped `((data . PAYLOAD))' alist, so the parser
  ;; must accept both or existing comments silently never overlay.
  (let* ((wrapped
          (my-forge-ediff-review-model-test--threads-response
           (vector
            (my-forge-ediff-review-model-test--thread
             :json-false
             '((path . "a.el") (line . 3) (diffSide . "RIGHT"))
             (vector (my-forge-ediff-review-model-test--comment "hi" "me"))))))
         (async-root (car wrapped))
         (entries (my-forge-ediff-review-model-parse-review-threads
                   async-root))
         (entry (car entries)))
    (should (eq 'data (car-safe async-root)))
    (should (= 1 (length entries)))
    (should (equal "a.el" (plist-get entry :path)))
    (should (= 3 (plist-get entry :line)))
    (should (equal "RIGHT" (plist-get entry :side)))))

(ert-deftest review-model-should-carry-thread-and-reply-target ()
  ;; The thread id and the first comment's databaseId let later replies
  ;; target the right thread; both comments in a thread share the reply
  ;; target.  Location lives on the thread, so the comment nodes only carry
  ;; databaseId, body and author.
  (let* ((thread
          `((id . "THREAD_kw1")
            (isResolved . :json-false)
            (path . "a.el") (line . 3) (diffSide . "RIGHT")
            (comments
             (nodes . ,(vector
                        '((databaseId . 555) (body . "first")
                          (author (login . "u")))
                        '((databaseId . 556) (body . "second")
                          (author (login . "v"))))))))
         (response (my-forge-ediff-review-model-test--threads-response
                    (vector thread)))
         (entries (my-forge-ediff-review-model-parse-review-threads response)))
    (should (= 2 (length entries)))
    (should (equal "THREAD_kw1" (plist-get (car entries) :thread-id)))
    (should (= 555 (plist-get (car entries) :reply-to-id)))
    (should (= 555 (plist-get (cadr entries) :reply-to-id)))))

(ert-deftest review-model-should-parse-comment-created-at ()
  (let* ((response
          (my-forge-ediff-review-model-test--threads-response
           (vector
            (my-forge-ediff-review-model-test--thread
             :json-false
             '((path . "a.el") (line . 3) (diffSide . "RIGHT"))
             (vector (my-forge-ediff-review-model-test--comment
                      "hi" "octocat" "2026-01-15T10:30:00Z"))))))
         (entry (car (my-forge-ediff-review-model-parse-review-threads
                      response))))
    (should (equal "2026-01-15T10:30:00Z" (plist-get entry :created-at)))))

;;;; PR description formatting

(ert-deftest review-model-format-description-should-include-title-and-body ()
  (let ((text (my-forge-ediff-review-model-format-description
               42 "Add feature" "This PR adds a feature.\n\nDetails here.")))
    (should (string-match-p "# PR #42: Add feature" text))
    (should (string-match-p "This PR adds a feature\\." text))
    (should (string-match-p "Details here\\." text))))

(ert-deftest review-model-format-description-should-placeholder-nil-body ()
  (should (string-match-p "(no description)"
                          (my-forge-ediff-review-model-format-description
                           1 "Title" nil))))

(ert-deftest review-model-format-description-should-placeholder-blank-body ()
  (should (string-match-p "(no description)"
                          (my-forge-ediff-review-model-format-description
                           1 "Title" "  \n \t ")))
  (should (string-match-p "(no description)"
                          (my-forge-ediff-review-model-format-description
                           1 "Title" ""))))

(ert-deftest review-model-format-description-should-tolerate-nil-title ()
  (should (string-match-p "# PR #7: "
                          (my-forge-ediff-review-model-format-description
                           7 nil "body"))))

;;;; Timestamp formatting

(ert-deftest review-model-format-time-should-format-iso ()
  ;; Pin the zone so the local rendering is deterministic under any TZ.
  (let ((process-environment (cons "TZ=UTC" process-environment)))
    (should (equal "2026-01-15 10:30"
                   (my-forge-ediff-review-model-format-time
                    "2026-01-15T10:30:00Z")))))

(ert-deftest review-model-format-time-should-be-empty-for-nil-or-blank ()
  (should (equal "" (my-forge-ediff-review-model-format-time nil)))
  (should (equal "" (my-forge-ediff-review-model-format-time ""))))

;;;; Card text padding and wrapping

(ert-deftest review-model-pad-should-fill-to-width ()
  (should (equal "ab   " (my-forge-ediff-review-model--pad "ab" 5)))
  (should (= 5 (string-width (my-forge-ediff-review-model--pad "ab" 5)))))

(ert-deftest review-model-pad-should-not-shrink-long-strings ()
  (should (equal "abcdef" (my-forge-ediff-review-model--pad "abcdef" 3))))

(ert-deftest review-model-pad-should-count-wide-glyphs-as-two ()
  ;; A full-width character occupies two columns, so only one pad space
  ;; is needed to reach width 4.
  (should (= 4 (string-width (my-forge-ediff-review-model--pad "あ" 4)))))

(ert-deftest review-model-wrap-should-not-exceed-width ()
  (let ((lines (my-forge-ediff-review-model--wrap-text
                "the quick brown fox jumps over the lazy dog" 12)))
    (dolist (l lines)
      (should (<= (string-width l) 12)))))

(ert-deftest review-model-wrap-should-keep-blank-paragraph-lines ()
  (let ((lines (my-forge-ediff-review-model--wrap-text "a\n\nb" 20)))
    (should (member "" lines))))

(ert-deftest review-model-wrap-should-emit-overlong-word-alone ()
  (let ((lines (my-forge-ediff-review-model--wrap-text
                "short verylongwordthatexceeds end" 8)))
    (should (member "verylongwordthatexceeds" lines))))

;;;; Card rendering

(ert-deftest review-model-card-should-be-a-rectangle ()
  ;; Every visual line must share the same display width so the background
  ;; face paints a clean rectangle (the annotate.el invariant).
  (let* ((card (my-forge-ediff-review-model-format-card
                "◈" "octocat  2026-01-15 10:30 (resolved)"
                "line one\n\ntwo two two" 40))
         (widths (mapcar #'string-width (split-string card "\n"))))
    (should (= 1 (length (delete-dups (copy-sequence widths)))))))

(ert-deftest review-model-card-should-contain-glyph-and-header ()
  (let ((card (my-forge-ediff-review-model-format-card
               "◈" "octocat" "body" 40)))
    (should (string-match-p "◈" card))
    (should (string-match-p "octocat" card))))

(ert-deftest review-model-card-should-render-borders-even-when-empty ()
  (let ((card (my-forge-ediff-review-model-format-card "◈" "octocat" "" 40)))
    (should (string-prefix-p "╭" card))
    (should (string-suffix-p "╯" (car (last (split-string card "\n")))))))

(ert-deftest review-model-card-line-count-should-match-body ()
  ;; 3 chrome lines (top, header, separator) + N body lines + 1 bottom.
  (let* ((card (my-forge-ediff-review-model-format-card
                "◈" "h" "a\nb\nc" 40))
         (lines (split-string card "\n")))
    (should (= (+ 3 3 1) (length lines)))))

(ert-deftest review-model-card-collapsed-should-be-one-line ()
  (let ((card (my-forge-ediff-review-model-format-card
               "✎" "Comment" "first line\nsecond line" 40 t)))
    (should-not (string-match-p "\n" card))
    (should (string-match-p "first line" card))
    ;; A fold affordance marks it as collapsed, not broken.
    (should (string-match-p "▸" card))))

(ert-deftest review-model-collapsed-summary-should-mark-hidden-lines ()
  ;; A multi-line body gets a trailing ellipsis; a single-line body does not.
  (should (string-suffix-p
           "…" (my-forge-ediff-review-model--card-summary
                "✎" "Comment" "one\ntwo")))
  (should-not (string-suffix-p
               "…" (my-forge-ediff-review-model--card-summary
                    "✎" "Comment" "only one line"))))

;;;; Card rendering (golden — exact input/output)

;; These pin the full rendered layout byte-for-byte so any change to the
;; box drawing, padding, wrapping or fold summary is caught, not just its
;; prefix.  Regenerate with scripts if the layout is intentionally changed.

(ert-deftest review-model-card-golden-expanded-single-line-body ()
  (should (equal
           (my-forge-ediff-review-model-format-card "✎" "Comment" "hi there" 10 nil)
           "╭────────────╮
│ ✎ Comment  │
├────────────┤
│ hi there   │
╰────────────╯")))

(ert-deftest review-model-card-golden-expanded-body-wraps-to-width ()
  (should (equal
           (my-forge-ediff-review-model-format-card "✎" "Comment" "the quick brown fox jumps" 10 nil)
           "╭────────────╮
│ ✎ Comment  │
├────────────┤
│ the quick  │
│ brown fox  │
│ jumps      │
╰────────────╯")))

(ert-deftest review-model-card-golden-expanded-preserves-blank-paragraph-line ()
  (should (equal
           (my-forge-ediff-review-model-format-card "◈" "octocat" "para one\n\npara two" 12 nil)
           "╭──────────────╮
│ ◈ octocat    │
├──────────────┤
│ para one     │
│              │
│ para two     │
╰──────────────╯")))

(ert-deftest review-model-card-golden-expanded-grows-when-header-wider-than-width ()
  (should (equal
           (my-forge-ediff-review-model-format-card "◈" "verylongauthor 2026-01-15 10:30" "hi" 8 nil)
           "╭───────────────────────────────────╮
│ ◈ verylongauthor 2026-01-15 10:30 │
├───────────────────────────────────┤
│ hi                                │
╰───────────────────────────────────╯")))

(ert-deftest review-model-card-golden-expanded-empty-body ()
  (should (equal
           (my-forge-ediff-review-model-format-card "✎" "Comment" "" 10 nil)
           "╭────────────╮
│ ✎ Comment  │
├────────────┤
│            │
╰────────────╯")))

(ert-deftest review-model-card-golden-collapsed-multi-line ()
  (should (equal
           (my-forge-ediff-review-model-format-card "✎" "Comment" "first line\nsecond" 20 t)
           "▸ ✎ Comment: first lin… ")))

(ert-deftest review-model-card-golden-collapsed-single-line ()
  (should (equal
           (my-forge-ediff-review-model-format-card "▤" "Memo" "just one" 20 t)
           "▸ ▤ Memo: just one      ")))

;;;; API host resolution (github.com and GitHub Enterprise)

(ert-deftest review-model-resolve-host-should-return-github-apihost ()
  (should (equal "api.github.com"
                 (my-forge-ediff-review-model-resolve-host "api.github.com"))))

(ert-deftest review-model-resolve-host-should-return-enterprise-apihost ()
  (should (equal "ghe.example.com/api/v3"
                 (my-forge-ediff-review-model-resolve-host
                  "ghe.example.com/api/v3"))))

(ert-deftest review-model-resolve-host-should-return-nil-when-nil ()
  (should-not (my-forge-ediff-review-model-resolve-host nil)))

(ert-deftest review-model-resolve-host-should-return-nil-when-empty ()
  (should-not (my-forge-ediff-review-model-resolve-host "")))

(provide 'my-forge-ediff-review-model-test)
;;; my-forge-ediff-review-model-test.el ends here
