;;; my-grip-auth-test.el --- Tests for my-grip-auth -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for the auth-source lookup that fills grip-mode's GitHub
;; credential.  `auth-source-search' is stubbed with `cl-letf' so the
;; tests never touch ~/.authinfo or a password manager.  Run with:
;;
;;   emacs -Q --batch --eval "(package-initialize)" \
;;     -L lisp -l ert -l tests/my-grip-auth-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'my-grip-auth)

;; grip-mode is absent in batch runs.  Declare its variables special so
;; that `let' binds them dynamically for `my-grip-auth-apply'.
(defvar grip-github-user)
(defvar grip-github-password)

(defmacro my-grip-auth-test--with-entries (entries &rest body)
  "Run BODY with `auth-source-search' returning ENTRIES for any query."
  (declare (indent 1))
  `(cl-letf (((symbol-function 'auth-source-search)
              (lambda (&rest _) ,entries)))
     ,@body))

(ert-deftest my-grip-auth-test-should-return-nil-when-no-entry ()
  (my-grip-auth-test--with-entries nil
    (should (null (my-grip-auth-github-credential)))))

(ert-deftest my-grip-auth-test-should-strip-forge-suffix-from-login ()
  (my-grip-auth-test--with-entries
      '((:host "api.github.com" :user "garaemon^forge" :secret "token-1"))
    (should (equal (my-grip-auth-github-credential)
                   '("garaemon" . "token-1")))))

(ert-deftest my-grip-auth-test-should-keep-login-without-suffix ()
  (my-grip-auth-test--with-entries
      '((:host "api.github.com" :user "garaemon" :secret "token-1"))
    (should (equal (my-grip-auth-github-credential)
                   '("garaemon" . "token-1")))))

(ert-deftest my-grip-auth-test-should-prefer-forge-entry-over-others ()
  (my-grip-auth-test--with-entries
      '((:host "api.github.com" :user "garaemon^code-review" :secret "other")
        (:host "api.github.com" :user "garaemon^forge" :secret "forge-token"))
    (should (equal (my-grip-auth-github-credential)
                   '("garaemon" . "forge-token")))))

(ert-deftest my-grip-auth-test-should-call-secret-function ()
  (my-grip-auth-test--with-entries
      (list (list :host "api.github.com" :user "garaemon^forge"
                  :secret (lambda () "lazy-token")))
    (should (equal (my-grip-auth-github-credential)
                   '("garaemon" . "lazy-token")))))

(ert-deftest my-grip-auth-test-should-return-nil-when-entry-lacks-secret ()
  (my-grip-auth-test--with-entries
      '((:host "api.github.com" :user "garaemon^forge"))
    (should (null (my-grip-auth-github-credential)))))

(ert-deftest my-grip-auth-test-should-set-grip-variables-when-credential-exists ()
  (let ((grip-github-user "")
        (grip-github-password ""))
    (my-grip-auth-test--with-entries
        '((:host "api.github.com" :user "garaemon^forge" :secret "token-1"))
      (my-grip-auth-apply)
      (should (equal (list grip-github-user grip-github-password)
                     '("garaemon" "token-1"))))))

(ert-deftest my-grip-auth-test-should-keep-grip-variables-when-no-entry ()
  (let ((grip-github-user "")
        (grip-github-password ""))
    (my-grip-auth-test--with-entries nil
      (my-grip-auth-apply)
      (should (equal (list grip-github-user grip-github-password)
                     '("" ""))))))

(provide 'my-grip-auth-test)
;;; my-grip-auth-test.el ends here
