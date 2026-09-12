;;; my-grip-auth.el --- GitHub credential for grip-mode from auth-source -*- lexical-binding: t; -*-

;;; Commentary:
;; grip renders Markdown through the GitHub API, which throttles anonymous
;; callers to 60 requests per hour.  grip-mode passes `grip-github-user'
;; and `grip-github-password' to grip, so this module fills those two
;; variables from the auth-source entry that forge already uses:
;;
;;   machine api.github.com login <user>^forge password <token>
;;
;; forge appends "^forge" to the login to tell its entry apart from other
;; GitHub clients.  grip authenticates with the bare user name, so the
;; lookup drops that suffix.
;;
;; grip-mode hands the token to grip on its command line, where any local
;; process listing can read it.  Accept that on a single-user machine;
;; on a shared one, leave the auth-source entry out and run grip
;; anonymously.

;;; Code:

(require 'auth-source)
(require 'seq)

(defvar grip-github-user)
(defvar grip-github-password)

(defconst my-grip-auth-github-host "api.github.com"
  "Host of the auth-source entry that holds the GitHub token.")

(defconst my-grip-auth-forge-login-suffix "^forge"
  "Suffix that forge appends to the login of its auth-source entry.")

(defun my-grip-auth--forge-entry-p (entry)
  "Return non-nil when the auth-source ENTRY belongs to forge."
  (let ((login (plist-get entry :user)))
    (and (stringp login)
         (string-suffix-p my-grip-auth-forge-login-suffix login))))

(defun my-grip-auth--strip-login-suffix (login)
  "Return LOGIN without forge's suffix, or LOGIN itself when absent."
  (if (string-suffix-p my-grip-auth-forge-login-suffix login)
      (substring login 0 (- (length my-grip-auth-forge-login-suffix)))
    login))

(defun my-grip-auth--secret-string (entry)
  "Return the password of the auth-source ENTRY as a string, or nil.
auth-source wraps the secret in a closure for some backends."
  (let ((secret (plist-get entry :secret)))
    (if (functionp secret) (funcall secret) secret)))

(defun my-grip-auth-github-credential ()
  "Return (USER . TOKEN) for the GitHub API from auth-source, or nil.
Prefers the entry whose login carries forge's suffix and falls back to
the first entry for the host.  Returns nil when no entry has both a
login and a secret."
  (let* ((entries (auth-source-search :host my-grip-auth-github-host :max 10))
         (entry (or (seq-find #'my-grip-auth--forge-entry-p entries)
                    (car entries)))
         (login (plist-get entry :user))
         (token (and entry (my-grip-auth--secret-string entry))))
    (when (and (stringp login) (stringp token))
      (cons (my-grip-auth--strip-login-suffix login) token))))

(defun my-grip-auth-apply ()
  "Fill grip-mode's GitHub credential from auth-source.
Leaves `grip-github-user' and `grip-github-password' untouched when
auth-source has no entry, so grip still runs, anonymously."
  (let ((credential (my-grip-auth-github-credential)))
    (when credential
      (setq grip-github-user (car credential))
      (setq grip-github-password (cdr credential)))))

(provide 'my-grip-auth)
;;; my-grip-auth.el ends here
