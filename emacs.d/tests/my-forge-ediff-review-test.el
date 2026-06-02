;;; my-forge-ediff-review-test.el --- Editor/store regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for the comment/memo editor backing logic in
;; `my-forge-ediff-review' (`--store-entry' and `--existing-entry-body').
;; Comments and memos behave the same way: a line carries at most one
;; entry of each kind, reopening prefills the existing body for in-place
;; editing, and saving empty removes it.
;;
;; Loading `my-forge-ediff-review' pulls in ghub/magit, so the tests are
;; skipped when that stack is unavailable.  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-forge-ediff-review-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)

(defvar my-forge-ediff-review-test--available
  (and (require 'magit nil t)
       (require 'ediff nil t)
       (progn
         (add-to-list 'load-path
                      (expand-file-name
                       "../lisp"
                       (file-name-directory (or load-file-name buffer-file-name))))
         (require 'my-forge-ediff-review nil t))
       t)
  "Non-nil when the magit/ghub stack needed by these tests is loadable.")

(defconst my-forge-ediff-review-test--ctx '(:path "a.el" :line 10 :side "RIGHT")
  "A sample line context shared by the tests.")

(defmacro my-forge-ediff-review-test--with-session (initial &rest body)
  "Run BODY with `my-forge-ediff-review--session' bound to INITIAL."
  (declare (indent 1))
  `(let ((my-forge-ediff-review--session ,initial))
     ,@body))

(ert-deftest my-forge-ediff-review-replaces-existing-comment-on-same-line ()
  "Re-saving a comment on the same line replaces it instead of appending."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-session (list :comments nil :memos nil)
    (my-forge-ediff-review--store-entry
     my-forge-ediff-review-test--ctx 'comment "first")
    (my-forge-ediff-review--store-entry
     my-forge-ediff-review-test--ctx 'comment "second")
    (let ((comments (plist-get my-forge-ediff-review--session :comments)))
      (should (= 1 (length comments)))
      (should (equal "second" (plist-get (car comments) :body))))))

(ert-deftest my-forge-ediff-review-keeps-comments-on-different-lines ()
  "Comments on distinct lines coexist."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-session (list :comments nil :memos nil)
    (my-forge-ediff-review--store-entry
     '(:path "a.el" :line 10 :side "RIGHT") 'comment "ten")
    (my-forge-ediff-review--store-entry
     '(:path "a.el" :line 20 :side "RIGHT") 'comment "twenty")
    (should (= 2 (length (plist-get my-forge-ediff-review--session :comments))))))

(ert-deftest my-forge-ediff-review-removes-comment-saved-empty ()
  "Saving an empty body removes the existing comment on that line."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-session
      (list :comments (list (append my-forge-ediff-review-test--ctx
                                    (list :body "old")))
            :memos nil)
    (my-forge-ediff-review--store-entry
     my-forge-ediff-review-test--ctx 'comment "")
    (should (null (plist-get my-forge-ediff-review--session :comments)))))

(ert-deftest my-forge-ediff-review-prefills-existing-comment-body ()
  "Reopening the editor on a commented line returns its body for prefill."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-session
      (list :comments (list (append my-forge-ediff-review-test--ctx
                                    (list :body "draft")))
            :memos nil)
    (should (equal "draft"
                   (my-forge-ediff-review--existing-entry-body
                    my-forge-ediff-review-test--ctx 'comment)))))

(ert-deftest my-forge-ediff-review-still-replaces-existing-memo ()
  "Memo behaviour is unchanged: one editable memo per line."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-session (list :comments nil :memos nil)
    (my-forge-ediff-review--store-entry
     my-forge-ediff-review-test--ctx 'memo "m1")
    (my-forge-ediff-review--store-entry
     my-forge-ediff-review-test--ctx 'memo "m2")
    (let ((memos (plist-get my-forge-ediff-review--session :memos)))
      (should (= 1 (length memos)))
      (should (equal "m2" (plist-get (car memos) :body))))))

(provide 'my-forge-ediff-review-test)
;;; my-forge-ediff-review-test.el ends here
