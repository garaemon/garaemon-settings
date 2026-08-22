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
(require 'cl-lib)

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

(ert-deftest my-forge-ediff-review-dims-diff-faces-when-session-active ()
  "Softening remaps every diff face to a background-only spec locally."
  (skip-unless my-forge-ediff-review-test--available)
  (with-temp-buffer
    (my-forge-ediff-review-test--with-session (list :comments nil :memos nil)
                                              (let ((my-forge-ediff-review-dim-diff-faces t))
                                                (my-forge-ediff-review--dim-diff-faces)
                                                (should (local-variable-p 'face-remapping-alist))
                                                (dolist (pair my-forge-ediff-review--dim-diff-faces)
                                                  ;; The face is remapped and the remap only touches the
                                                  ;; background, leaving the font-lock foreground intact.
                                                  (should (assq (car pair) face-remapping-alist))
                                                  (should (plist-get (cdr pair) :background))
                                                  (should-not (plist-get (cdr pair) :foreground)))))))

(ert-deftest my-forge-ediff-review-does-not-dim-when-disabled ()
  "No remap happens when softening is turned off."
  (skip-unless my-forge-ediff-review-test--available)
  (with-temp-buffer
    (my-forge-ediff-review-test--with-session (list :comments nil :memos nil)
                                              (let ((my-forge-ediff-review-dim-diff-faces nil))
                                                (my-forge-ediff-review--dim-diff-faces)
                                                (should-not (assq 'ediff-current-diff-A face-remapping-alist))))))

(ert-deftest my-forge-ediff-review-does-not-dim-without-session ()
  "No remap happens outside an active review session."
  (skip-unless my-forge-ediff-review-test--available)
  (with-temp-buffer
    (my-forge-ediff-review-test--with-session nil
                                              (let ((my-forge-ediff-review-dim-diff-faces t))
                                                (my-forge-ediff-review--dim-diff-faces)
                                                (should-not (assq 'ediff-current-diff-A face-remapping-alist))))))

;;;; Conversation buffer

(defmacro my-forge-ediff-review-test--with-conversation (session &rest body)
  "Run BODY with SESSION active and the conversation buffer killed after.
The buffer is global and named, so leaving it behind would leak its mode
and point into the next test."
  (declare (indent 1))
  `(let ((my-forge-ediff-review--session ,session))
     (unwind-protect
         (progn ,@body)
       (let ((buf (get-buffer
                   my-forge-ediff-review--conversation-buffer-name)))
         (when (buffer-live-p buf)
           (kill-buffer buf))))))

(defun my-forge-ediff-review-test--conversation-session (&optional comments)
  "Return a minimal session plist carrying COMMENTS as the conversation."
  (list :num 42 :title "A title" :body "A body."
        :conversation comments :pr-node-id nil))

(ert-deftest my-forge-ediff-review-conversation-renders-description-and-comments ()
  "The buffer shows the PR body first, then each comment."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-conversation
      (my-forge-ediff-review-test--conversation-session
       (list (list :author "alice" :body "Looks good.")))
    (with-current-buffer (my-forge-ediff-review--render-conversation)
      (should (string-prefix-p "# PR #42: A title" (buffer-string)))
      (should (string-match-p "### alice" (buffer-string)))
      (should (string-match-p "Looks good\\." (buffer-string))))))

(ert-deftest my-forge-ediff-review-conversation-buffer-is-read-only ()
  "The buffer must not be editable, and `g'/`q' must reach our commands."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-conversation
      (my-forge-ediff-review-test--conversation-session)
    (with-current-buffer (my-forge-ediff-review--render-conversation)
      (should buffer-read-only)
      (should (eq (key-binding (kbd "g"))
                  #'my-forge-ediff-review-show-conversation))
      (should (eq (key-binding (kbd "q")) #'quit-window)))))

(ert-deftest my-forge-ediff-review-conversation-refresh-keeps-point ()
  "A background refresh must not yank the reader back to the top."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-conversation
      (my-forge-ediff-review-test--conversation-session
       (list (list :author "alice" :body "Looks good.")))
    (with-current-buffer (my-forge-ediff-review--render-conversation)
      (goto-char (point-max))
      (let ((before (point)))
        (my-forge-ediff-review--render-conversation)
        (should (= before (point)))))))

(ert-deftest my-forge-ediff-review-conversation-stores-fetched-comments ()
  "A response for the session's own PR replaces the seed and keeps the id."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-conversation
      (my-forge-ediff-review-test--conversation-session
       (list (list :author "seed" :body "from forge")))
    (my-forge-ediff-review--on-conversation-fetched
     '(((body . "from api") (author (login . "bob"))))
     '((data (repository (pullRequest (id . "PR_kwABC")))))
     42)
    (let ((posts (plist-get my-forge-ediff-review--session :conversation)))
      (should (= 1 (length posts)))
      (should (equal "from api" (plist-get (car posts) :body))))
    (should (equal "PR_kwABC"
                   (plist-get my-forge-ediff-review--session :pr-node-id)))))

(ert-deftest my-forge-ediff-review-conversation-ignores-other-pr-response ()
  "A reply that outlives its session must not land under another PR."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-conversation
      (my-forge-ediff-review-test--conversation-session
       (list (list :author "seed" :body "from forge")))
    (my-forge-ediff-review--on-conversation-fetched
     '(((body . "wrong PR") (author (login . "eve"))))
     '((data (repository (pullRequest (id . "PR_other")))))
     99)
    (should (equal "from forge"
                   (plist-get
                    (car (plist-get my-forge-ediff-review--session
                                    :conversation))
                    :body)))
    (should-not (plist-get my-forge-ediff-review--session :pr-node-id))))

;;;; Paged GraphQL requests

(defun my-forge-ediff-review-test--page (nodes &optional cursor)
  "Build one comments page carrying NODES, continuing when CURSOR is given."
  `((data
     (repository
      (pullRequest
       (comments
        (pageInfo (hasNextPage . ,(if cursor t :json-false))
                  (endCursor . ,cursor))
        (nodes . ,nodes)))))))

(defmacro my-forge-ediff-review-test--with-ghub-pages (pages asked &rest body)
  "Run BODY with `ghub-query' replaced by one serving PAGES in order.
Each request's `after' variable is pushed onto ASKED, so a test can
assert the cursor was actually threaded through rather than the pages
merely being concatenated."
  (declare (indent 2))
  `(cl-letf (((symbol-function 'ghub-query)
              (lambda (_query variables &rest args)
                (push (alist-get 'after variables) ,asked)
                (funcall (plist-get args :callback) (pop ,pages)))))
     ,@body))

(ert-deftest my-forge-ediff-review-pagination-follows-the-cursor ()
  "Every page is fetched and the nodes arrive as one list."
  (skip-unless my-forge-ediff-review-test--available)
  (let ((pages (list (my-forge-ediff-review-test--page
                      '(((body . "one"))) "C1")
                     (my-forge-ediff-review-test--page
                      '(((body . "two"))))))
        (asked nil)
        (got 'unset))
    (my-forge-ediff-review-test--with-ghub-pages pages asked
      (let ((my-forge-ediff-review--session (list :host nil)))
        (my-forge-ediff-review--query-all-pages
         "query" '((owner . "o"))
         '(repository pullRequest comments)
         (lambda (nodes _response) (setq got nodes)))))
    (should (equal '(((body . "one")) ((body . "two"))) got))
    ;; First request carries no cursor; the second carries the first page's.
    (should (equal '(nil "C1") (nreverse asked)))))

(ert-deftest my-forge-ediff-review-pagination-stops-on-a-single-page ()
  (skip-unless my-forge-ediff-review-test--available)
  (let ((pages (list (my-forge-ediff-review-test--page '(((body . "only"))))))
        (asked nil)
        (calls 0))
    (my-forge-ediff-review-test--with-ghub-pages pages asked
      (let ((my-forge-ediff-review--session (list :host nil)))
        (my-forge-ediff-review--query-all-pages
         "query" '((owner . "o"))
         '(repository pullRequest comments)
         (lambda (_nodes _response) (setq calls (1+ calls))))))
    (should (= 1 calls))
    (should (equal '(nil) asked))))

(ert-deftest my-forge-ediff-review-threads-ignore-other-pr-response ()
  "The threads fetch guards on PR number the way the conversation does."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-session
      (list :num 42 :existing 'untouched)
    (my-forge-ediff-review--on-threads-fetched nil 99)
    (should (eq 'untouched
                (plist-get my-forge-ediff-review--session :existing)))))

;;;; Outdated thread overlays

(defun my-forge-ediff-review-test--card-at (line)
  "Return the review overlay card rendered after LINE, or nil."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line))
    (car (delq nil
               (mapcar (lambda (overlay)
                         (and (overlay-get overlay 'my-forge-ediff-review)
                              (overlay-get overlay 'after-string)))
                       (overlays-in (line-end-position)
                                    (line-end-position)))))))

(defmacro my-forge-ediff-review-test--with-overlaid-thread (thread &rest body)
  "Run BODY in a 20-line revision buffer overlaid with existing THREAD."
  (declare (indent 1))
  `(with-temp-buffer
     (insert (mapconcat #'number-to-string (number-sequence 1 20) "\n"))
     (setq-local my-magit-ediff--buf-file "a.el")
     (setq-local my-magit-ediff--buf-rev "head")
     (let ((my-forge-ediff-review--session
            (list :base-rev "base" :head-rev "head"
                  :comments nil :memos nil :existing (list ,thread))))
       (my-forge-ediff-review--reapply-overlays)
       ,@body)))

(ert-deftest my-forge-ediff-review-marks-an-outdated-thread ()
  "The header says so and the card is painted with the outdated face."
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-overlaid-thread
      (list :path "a.el" :line 3 :side "RIGHT" :body "stale"
            :author "alice" :outdated t :thread-id "T1")
    (let ((card (my-forge-ediff-review-test--card-at 3)))
      (should card)
      (should (string-match-p "(outdated)" card))
      (should (eq 'my-forge-ediff-review-outdated-comment-face
                  (get-text-property 1 'face card))))))

(ert-deftest my-forge-ediff-review-leaves-a-current-thread-unmarked ()
  (skip-unless my-forge-ediff-review-test--available)
  (my-forge-ediff-review-test--with-overlaid-thread
      (list :path "a.el" :line 3 :side "RIGHT" :body "current"
            :author "alice" :outdated nil :thread-id "T1")
    (let ((card (my-forge-ediff-review-test--card-at 3)))
      (should card)
      (should-not (string-match-p "(outdated)" card))
      (should (eq 'my-forge-ediff-review-existing-comment-face
                  (get-text-property 1 'face card))))))

(provide 'my-forge-ediff-review-test)
;;; my-forge-ediff-review-test.el ends here
