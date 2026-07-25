;;; my-vterm-toggle-test.el --- Tests for my-vterm-toggle dispatch -*- lexical-binding: t; -*-

;;; Commentary:
;; Regression tests for the C-c t vterm toggle dispatch.
;;
;; The bug: `my-vterm-toggle' only looked for a vterm window on the
;; selected frame (`vterm-toggle--get-window' walks `window-list' of the
;; selected frame).  When the vterm buffer was visible on ANOTHER frame,
;; the dispatch fell through to `vterm-toggle-show', whose
;; `pop-to-buffer' path could select the other frame's window without
;; transferring input focus, and a follow-up toggle then deleted the
;; vterm window instead of focusing it.
;;
;; The fix: when a vterm window is visible on another frame and no vterm
;; window exists on the selected frame, move input focus to that frame
;; and select the window instead of hiding or re-showing the buffer.
;;
;; The tests stub the vterm-toggle collaborators and frame primitives
;; with `cl-letf' because batch Emacs cannot create multiple real
;; frames.  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-vterm-toggle-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-vterm-toggle)

;; The dispatch consults these vterm-toggle definitions at runtime.  Give
;; the symbols a loud default so a test that forgets to stub one fails
;; clearly, even when the vterm-toggle package is absent in batch runs.
(defvar vterm-toggle-hide-method)
(dolist (collaborator '(vterm-toggle-show
                        vterm-toggle-hide
                        vterm-toggle--get-window
                        vterm-toggle-togglable-buffer-p))
  (unless (fboundp collaborator)
    (defalias collaborator
      (lambda (&rest _)
        (error "Unexpected call to %s" collaborator)))))

(defmacro my-vterm-toggle-test--with-stubs (spec &rest body)
  "Run BODY with the toggle collaborators stubbed according to SPEC.
SPEC is a plist with keys :current-frame-window, :other-frame-window,
and :claude-buffer-p.  BODY can inspect the recorded action symbols in
the variable `calls' (in reverse order of invocation)."
  (declare (indent 1))
  `(let ((calls '())
         (vterm-toggle-hide-method 'delete-window))
     (cl-letf (((symbol-function 'vterm-toggle--get-window)
                (lambda () ',(plist-get spec :current-frame-window)))
               ((symbol-function 'my-vterm-toggle--get-other-frame-window)
                (lambda () ',(plist-get spec :other-frame-window)))
               ((symbol-function 'my-vterm-toggle-claude-code-ide-buffer-p)
                (lambda (_buffer) ',(plist-get spec :claude-buffer-p)))
               ((symbol-function 'vterm-toggle-show)
                (lambda (&rest _) (push 'show calls)))
               ((symbol-function 'vterm-toggle-hide)
                (lambda (&rest _) (push 'hide calls)))
               ((symbol-function 'window-frame)
                (lambda (_window) 'stub-frame))
               ((symbol-function 'select-frame-set-input-focus)
                (lambda (frame) (push (cons 'focus-frame frame) calls)))
               ((symbol-function 'select-window)
                (lambda (window &optional _norecord)
                  (push (cons 'select-window window) calls))))
       (with-temp-buffer
         ,@body))))

(ert-deftest my-vterm-toggle-should-focus-frame-showing-vterm-on-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window nil :other-frame-window stub-window)
    (my-vterm-toggle)
    (should (equal calls
                   '((select-window . stub-window)
                     (focus-frame . stub-frame))))))

(ert-deftest my-vterm-toggle-should-not-hide-vterm-shown-on-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window nil :other-frame-window stub-window)
    (my-vterm-toggle)
    (should-not (memq 'hide calls))))

(ert-deftest my-vterm-toggle-should-not-reshow-vterm-shown-on-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window nil :other-frame-window stub-window)
    (my-vterm-toggle)
    (should-not (memq 'show calls))))

(ert-deftest my-vterm-toggle-should-hide-vterm-shown-on-current-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window stub-window :other-frame-window nil)
    (my-vterm-toggle)
    (should (equal calls '(hide)))))

(ert-deftest my-vterm-toggle-should-prefer-current-frame-window-over-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window stub-window :other-frame-window other-window)
    (my-vterm-toggle)
    (should (equal calls '(hide)))))

(ert-deftest my-vterm-toggle-should-show-when-vterm-not-visible-anywhere ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window nil :other-frame-window nil)
    (my-vterm-toggle)
    (should (equal calls '(show)))))

(ert-deftest my-vterm-toggle-should-show-from-claude-buffer-without-other-frame-vterm ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window nil :other-frame-window nil :claude-buffer-p t)
    (my-vterm-toggle)
    (should (equal calls '(show)))))

(ert-deftest my-vterm-toggle-should-focus-other-frame-vterm-from-claude-buffer ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window nil :other-frame-window stub-window :claude-buffer-p t)
    (my-vterm-toggle)
    (should (equal calls
                   '((select-window . stub-window)
                     (focus-frame . stub-frame))))))

(ert-deftest my-vterm-toggle-get-other-frame-window-should-skip-selected-frame ()
  (cl-letf (((symbol-function 'window-list-1)
             (lambda (&rest _) '(window-on-selected-frame window-on-other-frame)))
            ((symbol-function 'window-frame)
             (lambda (window)
               (if (eq window 'window-on-selected-frame) 'frame-a 'frame-b)))
            ((symbol-function 'selected-frame) (lambda () 'frame-a))
            ((symbol-function 'window-buffer) (lambda (_window) (current-buffer)))
            ((symbol-function 'vterm-toggle-togglable-buffer-p)
             (lambda (_buffer) t)))
    (should (eq (my-vterm-toggle--get-other-frame-window)
                'window-on-other-frame))))

(ert-deftest my-vterm-toggle-get-other-frame-window-should-ignore-non-vterm-windows ()
  (cl-letf (((symbol-function 'window-list-1)
             (lambda (&rest _) '(window-on-other-frame)))
            ((symbol-function 'window-frame) (lambda (_window) 'frame-b))
            ((symbol-function 'selected-frame) (lambda () 'frame-a))
            ((symbol-function 'window-buffer) (lambda (_window) (current-buffer)))
            ((symbol-function 'vterm-toggle-togglable-buffer-p)
             (lambda (_buffer) nil)))
    (should-not (my-vterm-toggle--get-other-frame-window))))

(provide 'my-vterm-toggle-test)
;;; my-vterm-toggle-test.el ends here
