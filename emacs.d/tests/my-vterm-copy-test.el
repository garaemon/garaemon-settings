;;; my-vterm-copy-test.el --- Tests for region-only vterm copy -*- lexical-binding: t; -*-

;;; Commentary:
;; Regression tests for the C-w and M-w copy commands in vterm buffers.
;;
;; The commands must copy exactly the active region:
;;
;; 1. `my-vterm-copy-region' copies the region and stays in
;;    `vterm-copy-mode'.  It never widens the copy to the whole line, the
;;    way `vterm-copy-mode-done' does when no region is active.
;; 2. `my-vterm-copy-region-or-send-key' copies the region when one is
;;    active and otherwise forwards the invoking key to libvterm, so the
;;    readline `unix-word-rubout' that C-w triggers still works while
;;    typing.
;;
;; The tests stub `vterm-send-key' and `vterm-copy-mode' with `cl-letf'
;; because batch Emacs cannot run a real terminal.  The `vterm-copy-mode'
;; stub catches a copy command that wrongly leaves copy mode.  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-vterm-copy-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-vterm-copy)

;; The commands consult these vterm definitions at runtime.  Give the
;; symbols a loud default so a test that forgets to stub one fails
;; clearly, even when the vterm package is absent in batch runs.
(dolist (collaborator '(vterm-send-key vterm-copy-mode))
  (unless (fboundp collaborator)
    (defalias collaborator
      (lambda (&rest _)
        (error "Unexpected call to %s" collaborator)))))

(defmacro my-vterm-copy-test--with-terminal (spec &rest body)
  "Run BODY in a temp buffer that imitates a vterm buffer.
SPEC is a plist with a single key:
- :region  cons of mark and point positions, or nil for no region
The buffer holds \"first line\\nsecond line\\n\".  BODY can inspect the
`(KEY SHIFT META CTRL)' lists handed to `vterm-send-key' in `sent-keys',
the arguments handed to `vterm-copy-mode' in `copy-mode-calls', and the
copied text in `kill-ring' (all in reverse order of invocation)."
  (declare (indent 1))
  `(let ((sent-keys '())
         (copy-mode-calls '())
         (kill-ring '())
         (kill-ring-yank-pointer nil)
         (interprogram-cut-function nil)
         (transient-mark-mode t))
     (cl-letf (((symbol-function 'vterm-send-key)
                (lambda (key &optional shift meta ctrl &rest _)
                  (push (list key shift meta ctrl) sent-keys)))
               ((symbol-function 'vterm-copy-mode)
                (lambda (&optional arg) (push arg copy-mode-calls))))
       (with-temp-buffer
         (insert "first line\nsecond line\n")
         (let ((region ',(plist-get spec :region)))
           (if region
               (progn (set-mark (car region))
                      (goto-char (cdr region)))
             (deactivate-mark)))
         ,@body))))

;;; my-vterm-copy-region: an active region is copied verbatim.

(ert-deftest my-vterm-copy-region-should-copy-the-active-region ()
  (my-vterm-copy-test--with-terminal (:region (3 . 6))
    (my-vterm-copy-region)
    (should (equal (car kill-ring) "rst"))))

(ert-deftest my-vterm-copy-region-should-not-copy-the-whole-line ()
  (my-vterm-copy-test--with-terminal (:region (3 . 6))
    (my-vterm-copy-region)
    (should-not (equal (car kill-ring) "first line"))))

(ert-deftest my-vterm-copy-region-should-copy-across-lines ()
  (my-vterm-copy-test--with-terminal (:region (7 . 18))
    (my-vterm-copy-region)
    (should (equal (car kill-ring) "line\nsecond"))))

(ert-deftest my-vterm-copy-region-should-stay-in-copy-mode ()
  ;; Several copies can then be taken from one screenful, so unlike
  ;; `vterm-copy-mode-done' this must not toggle the mode off.
  (my-vterm-copy-test--with-terminal (:region (3 . 6))
    (my-vterm-copy-region)
    (should (equal copy-mode-calls '()))))

(ert-deftest my-vterm-copy-region-should-deactivate-the-mark ()
  (my-vterm-copy-test--with-terminal (:region (3 . 6))
    (my-vterm-copy-region)
    (should-not (region-active-p))))

;;; my-vterm-copy-region: no region means no copy, not a line copy.

(ert-deftest my-vterm-copy-region-should-signal-without-a-region ()
  (my-vterm-copy-test--with-terminal (:region nil)
    (should-error (my-vterm-copy-region) :type 'user-error)))

(ert-deftest my-vterm-copy-region-should-not-fill-the-kill-ring-without-a-region ()
  (my-vterm-copy-test--with-terminal (:region nil)
    (ignore-errors (my-vterm-copy-region))
    (should (equal kill-ring '()))))

(ert-deftest my-vterm-copy-region-should-stay-in-copy-mode-without-a-region ()
  (my-vterm-copy-test--with-terminal (:region nil)
    (ignore-errors (my-vterm-copy-region))
    (should (equal copy-mode-calls '()))))

;;; my-vterm-copy-region-or-send-key: outside copy mode.

(ert-deftest my-vterm-copy-region-or-send-key-should-copy-the-region ()
  (my-vterm-copy-test--with-terminal (:region (3 . 6))
    (let ((last-command-event ?\C-w))
      (my-vterm-copy-region-or-send-key))
    (should (equal (car kill-ring) "rst"))))

(ert-deftest my-vterm-copy-region-or-send-key-should-copy-the-region-on-meta-w ()
  (my-vterm-copy-test--with-terminal (:region (3 . 6))
    (let ((last-command-event ?\M-w))
      (my-vterm-copy-region-or-send-key))
    (should (equal (car kill-ring) "rst"))))

(ert-deftest my-vterm-copy-region-or-send-key-should-not-send-a-key-with-a-region ()
  (my-vterm-copy-test--with-terminal (:region (3 . 6))
    (let ((last-command-event ?\C-w))
      (my-vterm-copy-region-or-send-key))
    (should (equal sent-keys '()))))

(ert-deftest my-vterm-copy-region-or-send-key-should-send-c-w-without-a-region ()
  (my-vterm-copy-test--with-terminal (:region nil)
    (let ((last-command-event ?\C-w))
      (my-vterm-copy-region-or-send-key))
    (should (equal sent-keys '(("w" nil nil t))))))

(ert-deftest my-vterm-copy-region-or-send-key-should-send-meta-w-without-a-region ()
  (my-vterm-copy-test--with-terminal (:region nil)
    (let ((last-command-event ?\M-w))
      (my-vterm-copy-region-or-send-key))
    (should (equal sent-keys '(("w" nil t nil))))))

(ert-deftest my-vterm-copy-region-or-send-key-should-not-copy-without-a-region ()
  (my-vterm-copy-test--with-terminal (:region nil)
    (let ((last-command-event ?\C-w))
      (my-vterm-copy-region-or-send-key))
    (should (equal kill-ring '()))))

(provide 'my-vterm-copy-test)
;;; my-vterm-copy-test.el ends here
