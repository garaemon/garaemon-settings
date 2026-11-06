;;; my-dired-actions-test.el --- Tests for per-extension dired actions -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for `my-dired-actions'.  A recording stub replaces the process
;; runner, so the tests launch no external command.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert -l tests/my-dired-actions-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-dired-actions)

(defmacro my-dired-actions-test--with-actions (actions &rest body)
  "Run BODY with `my-dired-actions' bound to ACTIONS."
  (declare (indent 1))
  `(let ((my-dired-actions ,actions))
     ,@body))

(defmacro my-dired-actions-test--with-recorded-commands (&rest body)
  "Run BODY with the shell commands passed to the runner in `recorded-commands'."
  (declare (indent 0))
  `(let ((recorded-commands nil))
     (cl-letf (((symbol-function 'my-dired-actions--run-shell-command)
                (lambda (command &rest _)
                  (setq recorded-commands (append recorded-commands
                                                  (list command))))))
       ,@body)))

(ert-deftest my-dired-actions-should-register-an-action ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "ffmpeg -i %i %o")
    (should (equal (mapcar #'my-dired-action-name
                           (my-dired-actions-for-files '("/v/a.mp4")))
                   '("Speed up")))))

(ert-deftest my-dired-actions-should-replace-an-action-with-the-same-name ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "old %i")
    (my-dired-actions-add '("mp4") "Speed up" "new %i")
    (should (= (length my-dired-actions) 1))))

(ert-deftest my-dired-actions-should-match-extensions-case-insensitively ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "ffmpeg -i %i")
    (should (my-dired-actions-for-files '("/v/A.MP4")))))

(ert-deftest my-dired-actions-should-skip-actions-for-other-extensions ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "ffmpeg -i %i")
    (should-not (my-dired-actions-for-files '("/v/a.png")))))

(ert-deftest my-dired-actions-should-require-every-file-to-match ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "ffmpeg -i %i")
    (should-not (my-dired-actions-for-files '("/v/a.mp4" "/v/b.png")))))

(ert-deftest my-dired-actions-should-match-any-file-with-t ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add t "Checksum" "sha256sum %i")
    (should (my-dired-actions-for-files '("/v/README")))))

(ert-deftest my-dired-actions-should-expand-placeholders-with-quoting ()
  (should (equal (my-dired-actions-expand-command
                  "ffmpeg -i %i %d/%b-2x.%e" "/v/my clip.mp4")
                 (format "ffmpeg -i %s %s/%s-2x.%s"
                         (shell-quote-argument "/v/my clip.mp4")
                         (shell-quote-argument "/v")
                         (shell-quote-argument "my clip")
                         (shell-quote-argument "mp4")))))

(ert-deftest my-dired-actions-should-keep-a-literal-percent ()
  (should (equal (my-dired-actions-expand-command "echo 100%%" "/v/a.mp4")
                 "echo 100%")))

(ert-deftest my-dired-actions-should-run-one-command-per-file ()
  (my-dired-actions-test--with-recorded-commands
    (my-dired-actions-run
     (my-dired-action-create :name "Echo" :extensions t :command "echo %b")
     '("/v/a.mp4" "/v/b.mp4"))
    (should (equal recorded-commands
                   (list "echo a && echo b")))))

(ert-deftest my-dired-actions-should-call-a-function-action-with-the-files ()
  (let ((received-files nil))
    (my-dired-actions-run
     (my-dired-action-create :name "Fn" :extensions t
                             :command (lambda (files)
                                        (setq received-files files)))
     '("/v/a.mp4"))
    (should (equal received-files '("/v/a.mp4")))))

(ert-deftest my-dired-actions-should-error-when-no-action-matches ()
  (my-dired-actions-test--with-actions nil
    (cl-letf (((symbol-function 'dired-get-marked-files)
               (lambda (&rest _) '("/v/a.xyz"))))
      (should-error (my-dired-actions-dispatch) :type 'user-error))))

(ert-deftest my-dired-actions-should-run-the-chosen-action-from-dired ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "speed %b")
    (my-dired-actions-add '("mp4") "Mute" "mute %b")
    (my-dired-actions-test--with-recorded-commands
      (cl-letf (((symbol-function 'dired-get-marked-files)
                 (lambda (&rest _) '("/v/a.mp4")))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) "Mute")))
        (my-dired-actions-dispatch))
      (should (equal recorded-commands '("mute a"))))))

(ert-deftest my-dired-actions-should-annotate-a-candidate-with-its-command ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "ffmpeg -i %i")
    (should (string-match-p
             "ffmpeg -i %i"
             (my-dired-actions--annotate "Speed up")))))

(ert-deftest my-dired-actions-should-tag-candidates-with-a-category ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Speed up" "ffmpeg -i %i")
    (let ((table (my-dired-actions--completion-table
                  my-dired-actions)))
      (should (eq (alist-get 'category (cdr (funcall table "" nil 'metadata)))
                  'my-dired-action)))))

(ert-deftest my-dired-actions-should-choose-with-completing-read-on-right-click ()
  (my-dired-actions-test--with-actions nil
    (my-dired-actions-add '("mp4") "Mute" "mute %b")
    (my-dired-actions-test--with-recorded-commands
      (cl-letf (((symbol-function 'mouse-set-point) #'ignore)
                ((symbol-function 'dired-get-marked-files)
                 (lambda (&rest _) '("/v/a.mp4")))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) "Mute")))
        (my-dired-actions-mouse-menu 'fake-event))
      (should (equal recorded-commands '("mute a"))))))

(provide 'my-dired-actions-test)

;;; my-dired-actions-test.el ends here
