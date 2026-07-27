;;; my-vterm-toggle-test.el --- Tests for my-vterm-toggle dispatch -*- lexical-binding: t; -*-

;;; Commentary:
;; Regression tests for the C-c t vterm toggle dispatch.
;;
;; The dispatch implements a three-state machine:
;;
;; 1. Focus is on a togglable vterm buffer: hide it.  When the vterm is
;;    the sole ordinary window of its frame, `vterm-toggle-hide' with
;;    the `delete-window' hide method signals "Attempt to delete
;;    minibuffer or sole ordinary window" because `window-deletable-p'
;;    returns the symbol `frame' (truthy) yet `delete-window' rejects a
;;    sole window.  The dispatch deletes the frame instead.
;; 2. The vterm is visible but focus is elsewhere (another window on
;;    the selected frame, or another frame): move focus to the vterm
;;    window instead of hiding or re-showing it.
;; 3. The vterm is not visible anywhere: show it.
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
(defvar vterm-buffer-name)
(dolist (collaborator '(vterm
                        vterm-toggle-show
                        vterm-toggle-hide
                        vterm-toggle--get-window
                        vterm-toggle-togglable-buffer-p))
  (unless (fboundp collaborator)
    (defalias collaborator
      (lambda (&rest _)
        (error "Unexpected call to %s" collaborator)))))

(defmacro my-vterm-toggle-test--with-stubs (spec &rest body)
  "Run BODY with the toggle collaborators stubbed according to SPEC.
SPEC is a plist with these keys:
- :focused-on-vterm      current buffer is a togglable vterm
- :current-frame-window  vterm window on the selected frame
- :other-frame-window    vterm window on another visible frame
- :window-deletable      return value of `window-deletable-p'
BODY can inspect the recorded action symbols in the variable `calls'
\(in reverse order of invocation)."
  (declare (indent 1))
  `(let ((calls '())
         (vterm-toggle-hide-method 'delete-window)
         (vterm-buffer-name "*vterm*"))
     (cl-letf (((symbol-function 'vterm-toggle-togglable-buffer-p)
                (lambda (_buffer) ',(plist-get spec :focused-on-vterm)))
               ((symbol-function 'vterm-toggle--get-window)
                (lambda () ',(plist-get spec :current-frame-window)))
               ((symbol-function 'my-vterm-toggle--get-other-frame-window)
                (lambda () ',(plist-get spec :other-frame-window)))
               ((symbol-function 'window-deletable-p)
                (lambda (&optional _window) ',(plist-get spec :window-deletable)))
               ((symbol-function 'vterm)
                (lambda (&rest _) (push 'new-vterm calls)))
               ((symbol-function 'vterm-toggle-show)
                (lambda (&rest _) (push 'show calls)))
               ((symbol-function 'vterm-toggle-hide)
                (lambda (&rest _) (push 'hide calls)))
               ((symbol-function 'delete-frame)
                (lambda (&rest _) (push 'delete-frame calls)))
               ((symbol-function 'window-frame)
                (lambda (_window) 'stub-frame))
               ((symbol-function 'select-frame-set-input-focus)
                (lambda (frame) (push (cons 'focus-frame frame) calls)))
               ((symbol-function 'select-window)
                (lambda (window &optional _norecord)
                  (push (cons 'select-window window) calls))))
       (with-temp-buffer
         ,@body))))

;;; State 1: focus is on the vterm -> hide.

(ert-deftest my-vterm-toggle-should-hide-when-focused-on-vterm ()
  (my-vterm-toggle-test--with-stubs
      (:focused-on-vterm t :current-frame-window stub-window :window-deletable t)
    (my-vterm-toggle)
    (should (equal calls '(hide)))))

(ert-deftest my-vterm-toggle-should-delete-frame-when-vterm-is-sole-window ()
  ;; `window-deletable-p' returns the symbol `frame' for a frame's sole
  ;; window; `vterm-toggle-hide' would signal an error there.
  (my-vterm-toggle-test--with-stubs
      (:focused-on-vterm t :current-frame-window stub-window :window-deletable frame)
    (my-vterm-toggle)
    (should (equal calls '(delete-frame)))))

(ert-deftest my-vterm-toggle-should-fall-back-to-hide-on-last-frame ()
  ;; Sole window on the last visible frame: `window-deletable-p' is nil,
  ;; so defer to `vterm-toggle-hide' which buries the buffer.
  (my-vterm-toggle-test--with-stubs
      (:focused-on-vterm t :current-frame-window stub-window :window-deletable nil)
    (my-vterm-toggle)
    (should (equal calls '(hide)))))

(ert-deftest my-vterm-toggle-should-spawn-new-vterm-with-prefix-in-vterm ()
  (my-vterm-toggle-test--with-stubs
      (:focused-on-vterm t :current-frame-window stub-window :window-deletable t)
    (my-vterm-toggle '(4))
    (should (equal calls '(new-vterm)))))

;;; State 2: vterm visible but focus elsewhere -> focus it.

(ert-deftest my-vterm-toggle-should-focus-vterm-window-on-current-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window stub-window)
    (my-vterm-toggle)
    (should (equal calls '((select-window . stub-window))))))

(ert-deftest my-vterm-toggle-should-not-hide-unfocused-vterm-on-current-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window stub-window)
    (my-vterm-toggle)
    (should-not (memq 'hide calls))))

(ert-deftest my-vterm-toggle-should-focus-frame-showing-vterm-on-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:other-frame-window stub-window)
    (my-vterm-toggle)
    (should (equal calls
                   '((select-window . stub-window)
                     (focus-frame . stub-frame))))))

(ert-deftest my-vterm-toggle-should-not-hide-vterm-shown-on-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:other-frame-window stub-window)
    (my-vterm-toggle)
    (should-not (memq 'hide calls))))

(ert-deftest my-vterm-toggle-should-not-reshow-vterm-shown-on-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:other-frame-window stub-window)
    (my-vterm-toggle)
    (should-not (memq 'show calls))))

(ert-deftest my-vterm-toggle-should-prefer-current-frame-window-over-other-frame ()
  (my-vterm-toggle-test--with-stubs
      (:current-frame-window stub-window :other-frame-window other-window)
    (my-vterm-toggle)
    (should (equal calls '((select-window . stub-window))))))

;;; State 3: vterm not visible anywhere -> show.

(ert-deftest my-vterm-toggle-should-show-when-vterm-not-visible-anywhere ()
  (my-vterm-toggle-test--with-stubs
      ()
    (my-vterm-toggle)
    (should (equal calls '(show)))))

;;; claude-code-ide buffers are not togglable, so from a claude buffer
;;; the dispatch behaves as if focus were on a normal buffer.

(ert-deftest my-vterm-toggle-should-show-from-claude-buffer-without-visible-vterm ()
  (my-vterm-toggle-test--with-stubs
      ()
    (my-vterm-toggle)
    (should (equal calls '(show)))))

(ert-deftest my-vterm-toggle-should-focus-other-frame-vterm-from-claude-buffer ()
  (my-vterm-toggle-test--with-stubs
      (:other-frame-window stub-window)
    (my-vterm-toggle)
    (should (equal calls
                   '((select-window . stub-window)
                     (focus-frame . stub-frame))))))

;;; Helper: other-frame window lookup.

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
