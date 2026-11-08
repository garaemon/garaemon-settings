;;; my-buf-move-repeat-test.el --- Tests for the buffer-move keys -*- lexical-binding: t; -*-

;;; Commentary:
;; `C-c w <arrow>' swaps the current buffer with the neighbor window, and
;; repeat-mode keeps swapping on bare arrows or b/f/p/n afterwards.  The
;; keys live under `C-c w' because winner-mode owns `C-c <left>' and
;; `C-c <right>', and its minor mode map shadows the global map.
;;
;; The test reads the `use-package' form for buffer-move from
;; lisp/init-editor.el and evaluates it without buffer-move installed,
;; which is what CI provides.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-buf-move-repeat-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'bind-key)
(require 'cl-lib)
(require 'use-package)

(defconst my-buf-move-repeat-test-init-editor-file
  (expand-file-name "../lisp/init-editor.el"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "Init file that carries the buffer-move `use-package' block.")

(defun my-buf-move-repeat-test--read-use-package-form (name)
  "Return the `use-package' form for NAME read from lisp/init-editor.el."
  (with-temp-buffer
    (insert-file-contents my-buf-move-repeat-test-init-editor-file)
    (goto-char (point-min))
    ;; A fresh symbol marks the end of the file, which a plain nil could not:
    ;; `read' returns nil for a top-level nil form too.
    (let ((end-of-forms (make-symbol "end-of-forms")))
      (cl-loop for form = (condition-case nil
                              (read (current-buffer))
                            (end-of-file end-of-forms))
               until (eq form end-of-forms)
               when (and (eq (car-safe form) 'use-package)
                         (eq (cadr form) name))
               return form))))

(defmacro my-buf-move-repeat-test--with-evaluated-form (&rest body)
  "Evaluate the buffer-move `use-package' form, then run BODY.
BODY sees the bindings in a fresh `global-map'."
  (declare (indent 0))
  `(let ((buffer-move-form (my-buf-move-repeat-test--read-use-package-form
                            'buffer-move))
         (global-map (make-sparse-keymap))
         (personal-keybindings (copy-sequence personal-keybindings))
         ;; `:ensure' would reach for the package archives.
         (use-package-ensure-function 'ignore))
     (should buffer-move-form)
     (eval buffer-move-form t)
     ,@body))

(ert-deftest my-buf-move-repeat-should-bind-c-c-w-arrows-globally ()
  (my-buf-move-repeat-test--with-evaluated-form
    (should (equal (mapcar (lambda (key) (lookup-key global-map (kbd key)))
                           '("C-c w <left>" "C-c w <right>"
                             "C-c w <up>" "C-c w <down>"))
                   '(buf-move-left buf-move-right buf-move-up buf-move-down)))))

(ert-deftest my-buf-move-repeat-should-attach-repeat-map-to-commands ()
  (my-buf-move-repeat-test--with-evaluated-form
    (should (equal (mapcar (lambda (command) (get command 'repeat-map))
                           '(buf-move-left buf-move-right
                             buf-move-up buf-move-down))
                   (make-list 4 'my-buf-move-repeat-map)))))

(ert-deftest my-buf-move-repeat-should-repeat-on-arrows-and-emacs-letters ()
  (my-buf-move-repeat-test--with-evaluated-form
    (should (equal (mapcar (lambda (key)
                             (lookup-key my-buf-move-repeat-map (kbd key)))
                           '("<left>" "<right>" "<up>" "<down>"
                             "b" "f" "p" "n"))
                   '(buf-move-left buf-move-right buf-move-up buf-move-down
                     buf-move-left buf-move-right buf-move-up buf-move-down)))))

(provide 'my-buf-move-repeat-test)
;;; my-buf-move-repeat-test.el ends here
