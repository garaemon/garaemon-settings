;;; my-org-present-test.el --- Tests for my-org-present -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for the buffer state that `my-org-present-start' installs and
;; `my-org-present-quit' removes around an org-present slide show.
;;
;; The tests stub the minor modes from the visual-fill-column and
;; hide-mode-line packages with `cl-letf', so they run in the batch Emacs
;; that CI provides, where neither package is installed.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert -l tests/my-org-present-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'my-org-present)

;; `my-org-present-start' and `my-org-present-quit' toggle these modes at
;; runtime.  Give the symbols a loud default so a test that forgets to
;; stub one fails clearly when the packages are absent.
(dolist (collaborator '(visual-fill-column-mode hide-mode-line-mode))
  (unless (fboundp collaborator)
    (defalias collaborator
      (lambda (&rest _)
        (error "Unexpected call to %s" collaborator)))))

(defconst my-org-present-test-slides
  "* Slide one
Body of slide one.
** Sub heading
Body of the sub heading.
*** Deep heading
Body of the deep heading.
* Slide two
Body of slide two.
"
  "Slide deck used by every test.")

(defmacro my-org-present-test--with-slides (&rest body)
  "Run BODY in a fresh `org-mode' buffer that holds the test slides.
The minor modes from external packages are stubbed.  BODY can inspect
the recorded (MODE . ARG) pairs in the variable `mode-calls', in
reverse order of invocation."
  (declare (indent 0))
  `(let ((mode-calls '()))
     (cl-letf (((symbol-function 'visual-fill-column-mode)
                (lambda (&optional arg) (push (cons 'visual-fill-column-mode arg) mode-calls)))
               ((symbol-function 'hide-mode-line-mode)
                (lambda (&optional arg) (push (cons 'hide-mode-line-mode arg) mode-calls))))
       (with-temp-buffer
         (insert my-org-present-test-slides)
         (let ((org-startup-folded 'showall))
           (org-mode))
         (goto-char (point-min))
         ,@body))))

(defun my-org-present-test--mode-arg (calls mode)
  "Return the argument of the most recent call to MODE in CALLS.
Return the symbol `unset' when CALLS holds no call to MODE."
  (let ((call (assq mode calls)))
    (if call (cdr call) 'unset)))

(defun my-org-present-test--heading-invisible-p (title)
  "Return non-nil when the heading line titled TITLE is folded away."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward (concat "^\\*+ " (regexp-quote title) "$"))
    (org-invisible-p (line-beginning-position))))

(ert-deftest my-org-present-test-start-enlarges-default-face ()
  "Starting a show remaps the default face to a larger height."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (let ((remap (assq 'default face-remapping-alist)))
      (should (> (plist-get (cadr remap) :height) 1.0)))))

(ert-deftest my-org-present-test-start-hides-block-delimiters ()
  "Starting a show shrinks the #+begin_src and #+end_src lines away."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (should (equal (plist-get (cadr (assq 'org-block-begin-line face-remapping-alist)) :height)
                   0))))

(ert-deftest my-org-present-test-start-pads-slide-top ()
  "Starting a show reserves space above the first line with the header line."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (should (stringp header-line-format))))

(ert-deftest my-org-present-test-start-blends-header-line-into-background ()
  "Starting a show gives the header line the background of the default face."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (should (equal (plist-get (cadr (assq 'header-line face-remapping-alist)) :inherit)
                   'default))))

(ert-deftest my-org-present-test-start-centers-text ()
  "Starting a show turns on visual-fill-column with centering."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (should (equal (my-org-present-test--mode-arg mode-calls 'visual-fill-column-mode) 1))))

(ert-deftest my-org-present-test-start-hides-mode-line ()
  "Starting a show turns on hide-mode-line."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (should (equal (my-org-present-test--mode-arg mode-calls 'hide-mode-line-mode) 1))))

(ert-deftest my-org-present-test-start-wraps-long-lines ()
  "Starting a show wraps lines even though Org starts truncated here."
  (my-org-present-test--with-slides
    (setq truncate-lines t)
    (my-org-present-start)
    (should (null truncate-lines))))

(ert-deftest my-org-present-test-start-hides-line-numbers ()
  "Starting a show turns off line numbers, which the global mode enables."
  (my-org-present-test--with-slides
    (display-line-numbers-mode 1)
    (my-org-present-start)
    (should (null display-line-numbers-mode))))

(ert-deftest my-org-present-test-quit-drops-face-remappings ()
  "Quitting a show removes every face remapping the start installed."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (my-org-present-quit)
    (should (null face-remapping-alist))))

(ert-deftest my-org-present-test-quit-drops-header-line ()
  "Quitting a show removes the top padding."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (my-org-present-quit)
    (should (null header-line-format))))

(ert-deftest my-org-present-test-quit-turns-modes-off ()
  "Quitting a show turns the presentation minor modes off."
  (my-org-present-test--with-slides
    (my-org-present-start)
    (my-org-present-quit)
    (should (equal (my-org-present-test--mode-arg mode-calls 'visual-fill-column-mode) -1))
    (should (equal (my-org-present-test--mode-arg mode-calls 'hide-mode-line-mode) -1))))

(ert-deftest my-org-present-test-quit-restores-truncate-lines ()
  "Quitting a show restores the line truncation the buffer had before."
  (my-org-present-test--with-slides
    (setq truncate-lines t)
    (my-org-present-start)
    (my-org-present-quit)
    (should (eq truncate-lines t))))

(ert-deftest my-org-present-test-quit-restores-line-numbers ()
  "Quitting a show turns line numbers back on when they were on before."
  (my-org-present-test--with-slides
    (display-line-numbers-mode 1)
    (my-org-present-start)
    (my-org-present-quit)
    (should display-line-numbers-mode)))

(ert-deftest my-org-present-test-navigate-shows-direct-children ()
  "Landing on a slide reveals its direct sub headings."
  (my-org-present-test--with-slides
    (my-org-present-after-navigate (buffer-name) "Slide one")
    (should-not (my-org-present-test--heading-invisible-p "Sub heading"))))

(ert-deftest my-org-present-test-navigate-folds-deeper-headings ()
  "Landing on a slide keeps headings below the second level folded."
  (my-org-present-test--with-slides
    (my-org-present-after-navigate (buffer-name) "Slide one")
    (should (my-org-present-test--heading-invisible-p "Deep heading"))))

(provide 'my-org-present-test)
;;; my-org-present-test.el ends here
