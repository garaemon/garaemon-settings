;;; my-forge-ediff-review-model-test.el --- Tests for review model -*- lexical-binding: t; -*-

;;; Commentary:
;; ERT tests for the pure data-model helpers in
;; `my-forge-ediff-review-model'.  These helpers have no dependency on
;; magit/forge/ghub, so they can be exercised in batch with:
;;
;;   emacs -batch -L lisp -l lisp/my-forge-ediff-review-model-test.el \
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

(provide 'my-forge-ediff-review-model-test)
;;; my-forge-ediff-review-model-test.el ends here
