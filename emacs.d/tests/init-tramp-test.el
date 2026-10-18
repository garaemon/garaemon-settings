;;; init-tramp-test.el --- Tests for the TRAMP performance settings -*- lexical-binding: t; -*-

;;; Commentary:
;; The tests read the init files instead of loading them, because loading
;; them reaches for the package archives.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/init-tramp-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

(defconst init-tramp-test-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory that holds this test file.")

(defun init-tramp-test--read-file-text (relative-name)
  "Return the contents of RELATIVE-NAME, relative to emacs.d/."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name (concat "../" relative-name) init-tramp-test-directory))
    (buffer-string)))

(ert-deftest should_enable_tramp_directory_cache_when_loading_init_editor ()
  (let ((text (init-tramp-test--read-file-text "lisp/init-editor.el")))
    (should (string-match-p "remote-file-name-inhibit-cache [0-9]+" text))))

(ert-deftest should_skip_vc_on_remote_files_when_loading_init_editor ()
  (let ((text (init-tramp-test--read-file-text "lisp/init-editor.el")))
    (should (string-match-p "vc-ignore-dir-regexp.*tramp-file-name-regexp" text))))

(ert-deftest should_keep_ssh_connections_alive_when_loading_init_editor ()
  (let ((text (init-tramp-test--read-file-text "lisp/init-editor.el")))
    (should (string-match-p "ControlPersist" text))))

(ert-deftest should_disable_diff_hl_on_remote_when_loading_init_ui ()
  (let ((text (init-tramp-test--read-file-text "lisp/init-ui.el")))
    (should (string-match-p "diff-hl-disable-on-remote t" text))))

(ert-deftest should_skip_projectile_root_detection_on_remote_when_loading_init_prog ()
  (let ((text (init-tramp-test--read-file-text "lisp/init-prog.el")))
    (should (string-match-p
             "advice-add 'projectile-project-root :around #'my-projectile-skip-remote-root"
             text))))

(ert-deftest should_pick_dired_icons_without_stat_when_loading_init_ui ()
  (let ((text (init-tramp-test--read-file-text "lisp/init-ui.el")))
    (should (string-match-p
             "advice-add 'all-the-icons-dired--icon :around[ \n]+#'my-all-the-icons-dired-icon-without-stat"
             text))))

(ert-deftest should_keep_dired_icons_enabled_on_remote_when_loading_init_ui ()
  (let ((text (init-tramp-test--read-file-text "lisp/init-ui.el")))
    (should-not (string-match-p "my-enable-all-the-icons-dired-on-local" text))))

(provide 'init-tramp-test)
;;; init-tramp-test.el ends here
