;;; my-magit-ediff-window-test.el --- Window/buffer regression tests -*- lexical-binding: t; -*-

;;; Commentary:
;; Regression tests for the multi-file ediff review session, covering two
;; bugs that made a long review session pile up state on screen:
;;
;; 1. Window accumulation.  While a side window (the forge review sidebar)
;;    is shown, ediff's plain window setup clears the frame with
;;    `delete-other-windows', which is a no-op as long as a side window is
;;    present.  The previous file's windows therefore survived every
;;    navigation, fell back to an unrelated buffer once their revision
;;    buffers were killed, and stacked up.
;;
;; 2. Buffer accumulation.  Each file's two revision buffers were only
;;    dropped on the normal quit path, so switching files outside it left
;;    stale `file (rev)' buffers behind.
;;
;; 3. Wrong diff base.  The review diffed against the base branch tip, so a
;;    base branch that advanced after the PR forked folded its unrelated
;;    commits into the file list.  The review must diff against the
;;    merge-base, matching GitHub's `base...head' view.
;;
;; The tests reproduce a review session over a throwaway git repository,
;; navigate between files through the engine (the same path the sidebar's
;; RET uses), and assert that neither windows nor revision buffers grow.
;; They need magit/ediff on the load path, so they are skipped when those
;; are unavailable (e.g. a minimal batch run).  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-magit-ediff-window-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)

(defvar my-magit-ediff-window-test--available
  (and (require 'magit nil t)
       (require 'ediff nil t)
       (progn
         (add-to-list 'load-path
                      (expand-file-name
                       "../lisp"
                       (file-name-directory (or load-file-name buffer-file-name))))
         (require 'my-magit-ediff nil t))
       (require 'my-forge-ediff-review nil t))
  "Non-nil when the magit/ediff stack needed by these tests is loadable.")

(defun my-magit-ediff-window-test--run-git (dir &rest args)
  "Run git with ARGS inside DIR, signalling on failure."
  (let ((default-directory (file-name-as-directory dir)))
    (unless (zerop (apply #'call-process "git" nil nil nil args))
      (error "git %S failed in %s" args dir))))

(defun my-magit-ediff-window-test--write-lines (path &rest lines)
  "Write LINES to PATH, one per line."
  (with-temp-file path
    (dolist (line lines) (insert line "\n"))))

(defun my-magit-ediff-window-test--make-repo ()
  "Create a temporary git repo with three files changed across two commits.
Return the repository directory."
  (let ((dir (make-temp-file "my-magit-ediff-test" t)))
    (my-magit-ediff-window-test--run-git dir "init" "-q")
    (my-magit-ediff-window-test--run-git dir "config" "user.email" "t@example.com")
    (my-magit-ediff-window-test--run-git dir "config" "user.name" "Test")
    (dolist (name '("a" "b" "c"))
      (my-magit-ediff-window-test--write-lines
       (expand-file-name (concat name ".txt") dir)
       (concat name "1") (concat name "2") (concat name "3")))
    (my-magit-ediff-window-test--run-git dir "add" "a.txt" "b.txt" "c.txt")
    (my-magit-ediff-window-test--run-git dir "commit" "-qm" "base")
    (dolist (name '("a" "b" "c"))
      (my-magit-ediff-window-test--write-lines
       (expand-file-name (concat name ".txt") dir)
       (concat name "1") "CHANGED" (concat name "3")))
    (my-magit-ediff-window-test--run-git dir "add" "a.txt" "b.txt" "c.txt")
    (my-magit-ediff-window-test--run-git dir "commit" "-qm" "head")
    dir))

(defun my-magit-ediff-window-test--orphan-window-p (window)
  "Return non-nil when WINDOW is neither a revision pane, control panel, nor sidebar."
  (let ((buffer (window-buffer window)))
    (not (or (buffer-local-value 'my-magit-ediff--buf-file buffer)
             (string-match-p "Ediff Control Panel" (buffer-name buffer))
             (window-parameter window 'window-side)))))

(defun my-magit-ediff-window-test--orphan-count ()
  "Count orphan windows in the selected frame."
  (length (seq-filter #'my-magit-ediff-window-test--orphan-window-p
                      (window-list nil 'no-mini))))

(defun my-magit-ediff-window-test--normal-window-count ()
  "Count non-side windows in the selected frame."
  (length (seq-remove (lambda (window) (window-parameter window 'window-side))
                      (window-list nil 'no-mini))))

(defun my-magit-ediff-window-test--sidebar-shown-p ()
  "Return non-nil when the review sidebar window is visible."
  (and (seq-find (lambda (window)
                   (string-match-p "forge-review-files"
                                   (buffer-name (window-buffer window))))
                 (window-list nil 'no-mini))
       t))

(defun my-magit-ediff-window-test--revision-buffer-count ()
  "Count live revision buffers generated for the session."
  (length (seq-filter (lambda (buffer)
                        (buffer-local-value 'my-magit-ediff--buf-file buffer))
                      (buffer-list))))

(defun my-magit-ediff-window-test--force-after-quit ()
  "Run the deferred `my-magit-ediff--after-quit' timer synchronously."
  (dolist (timer (copy-sequence timer-list))
    (when (eq (timer--function timer) 'my-magit-ediff--after-quit)
      (cancel-timer timer)
      (apply (timer--function timer) (timer--args timer)))))

(defun my-magit-ediff-window-test--goto-via-sidebar (index)
  "Select the sidebar and switch the active session to file INDEX."
  (let ((sidebar (seq-find
                  (lambda (window)
                    (string-match-p "forge-review-files"
                                    (buffer-name (window-buffer window))))
                  (window-list nil 'no-mini))))
    (when sidebar (select-window sidebar)))
  (my-magit-ediff-goto-index index)
  (my-magit-ediff-window-test--force-after-quit))

(defun my-magit-ediff-window-test--call-with-session (body)
  "Set up a review session over a throwaway repo, run BODY, then tear it down."
  (let ((repo (my-magit-ediff-window-test--make-repo))
        (ediff-window-setup-function #'ediff-setup-windows-plain)
        (ediff-split-window-function #'split-window-horizontally)
        (ediff-keep-variants t))
    (unwind-protect
        (let ((default-directory (file-name-as-directory repo)))
          (setq my-forge-ediff-review--session
                (list :num 1 :base-rev "HEAD~1" :head-rev "HEAD"
                      :comments nil :memos nil :reviewed nil))
          (my-forge-ediff-review--install-sidebar-hooks)
          (my-magit-ediff-all-compare "HEAD~1" "HEAD")
          (funcall body))
      (ignore-errors (my-magit-ediff--cleanup))
      (delete-directory repo t))))

(ert-deftest my-magit-ediff-leaves-no-orphan-window-on-navigation ()
  "Navigating files with the review sidebar shown must not leave orphan windows."
  (skip-unless my-magit-ediff-window-test--available)
  (my-magit-ediff-window-test--call-with-session
   (lambda ()
     (should (= 0 (my-magit-ediff-window-test--orphan-count)))
     (my-magit-ediff-window-test--goto-via-sidebar 1)
     (should (= 0 (my-magit-ediff-window-test--orphan-count)))
     (my-magit-ediff-window-test--goto-via-sidebar 0)
     (should (= 0 (my-magit-ediff-window-test--orphan-count))))))

(ert-deftest my-magit-ediff-keeps-window-count-stable-across-navigation ()
  "Repeated navigation must keep exactly the control panel and two panes."
  (skip-unless my-magit-ediff-window-test--available)
  (my-magit-ediff-window-test--call-with-session
   (lambda ()
     (dolist (index '(2 1 0 2 1))
       (my-magit-ediff-window-test--goto-via-sidebar index)
       (should (= 3 (my-magit-ediff-window-test--normal-window-count)))
       (should (my-magit-ediff-window-test--sidebar-shown-p))))))

(ert-deftest my-magit-ediff-keeps-revision-buffers-bounded ()
  "Revision buffers from earlier files must not accumulate across navigation."
  (skip-unless my-magit-ediff-window-test--available)
  (my-magit-ediff-window-test--call-with-session
   (lambda ()
     (dolist (index '(1 2 0 1))
       (my-magit-ediff-window-test--goto-via-sidebar index)
       (should (= 2 (my-magit-ediff-window-test--revision-buffer-count)))))))

(defun my-magit-ediff-window-test--make-divergent-repo ()
  "Create a repo whose base branch advanced after a feature branch forked.
The feature branch changes `a.txt'; the base branch (master) then gains an
unrelated `z.txt'.  Return a plist with :dir :base-tip :head and :merge-base."
  (let ((dir (make-temp-file "my-magit-ediff-divergent" t)))
    (my-magit-ediff-window-test--run-git dir "init" "-q" "-b" "master")
    (my-magit-ediff-window-test--run-git dir "config" "user.email" "t@example.com")
    (my-magit-ediff-window-test--run-git dir "config" "user.name" "Test")
    (my-magit-ediff-window-test--write-lines (expand-file-name "a.txt" dir) "a1" "a2")
    (my-magit-ediff-window-test--run-git dir "add" "a.txt")
    (my-magit-ediff-window-test--run-git dir "commit" "-qm" "base")
    (let ((default-directory (file-name-as-directory dir)))
      (let ((fork-point (magit-git-string "rev-parse" "HEAD")))
        (my-magit-ediff-window-test--run-git dir "checkout" "-q" "-b" "feature")
        (my-magit-ediff-window-test--write-lines
         (expand-file-name "a.txt" dir) "a1" "CHANGED")
        (my-magit-ediff-window-test--run-git dir "add" "a.txt")
        (my-magit-ediff-window-test--run-git dir "commit" "-qm" "feature change")
        (let ((head (magit-git-string "rev-parse" "HEAD")))
          (my-magit-ediff-window-test--run-git dir "checkout" "-q" "master")
          (my-magit-ediff-window-test--write-lines
           (expand-file-name "z.txt" dir) "z1")
          (my-magit-ediff-window-test--run-git dir "add" "z.txt")
          (my-magit-ediff-window-test--run-git dir "commit" "-qm" "unrelated base change")
          (list :dir dir
                :base-tip (magit-git-string "rev-parse" "HEAD")
                :head head
                :merge-base fork-point))))))

(ert-deftest my-forge-ediff-review-diffs-against-merge-base ()
  "The review diff base must be the merge-base, not the advanced base tip."
  (skip-unless my-magit-ediff-window-test--available)
  (let ((repo (my-magit-ediff-window-test--make-divergent-repo)))
    (unwind-protect
        (let ((default-directory (file-name-as-directory (plist-get repo :dir))))
          (should (equal (plist-get repo :merge-base)
                         (my-forge-ediff-review--diff-base
                          (plist-get repo :base-tip) (plist-get repo :head))))
          (should-not (equal (plist-get repo :base-tip) (plist-get repo :merge-base))))
      (delete-directory (plist-get repo :dir) t))))

(ert-deftest my-forge-ediff-review-excludes-unrelated-base-commits ()
  "Diffing from the merge-base must list only the PR's own changes."
  (skip-unless my-magit-ediff-window-test--available)
  (let ((repo (my-magit-ediff-window-test--make-divergent-repo)))
    (unwind-protect
        (let* ((default-directory (file-name-as-directory (plist-get repo :dir)))
               (diff-base (my-forge-ediff-review--diff-base
                           (plist-get repo :base-tip) (plist-get repo :head))))
          ;; From the merge-base only the PR's file shows up.
          (should (equal '("a.txt")
                         (magit-changed-files diff-base (plist-get repo :head))))
          ;; Diffing from the advanced base tip wrongly folds in z.txt.
          (should (member "z.txt"
                          (magit-changed-files (plist-get repo :base-tip)
                                               (plist-get repo :head)))))
      (delete-directory (plist-get repo :dir) t))))

(provide 'my-magit-ediff-window-test)
;;; my-magit-ediff-window-test.el ends here
