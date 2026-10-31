;;; my-org-github-link.el --- Format yanked GitHub URLs as Org links -*- lexical-binding: t; -*-

;;; Commentary:
;; `my-org-github-link-mode' rewrites a yanked GitHub URL into an Org link
;; with a short description:
;;
;;   https://github.com/owner/repo/issues/20 -> [[...][owner/repo#20]]
;;   https://github.com/owner/repo/pull/21   -> [[...][owner/repo#21]]
;;   https://github.com/owner/repo           -> [[...][owner/repo]]
;;
;; Only a yank that consists of one URL changes.  Other GitHub pages, such as
;; files and commits, stay as plain URLs.

;;; Code:

(require 'subr-x)

(defconst my-org-github-link-reserved-owners
  '("about" "apps" "collections" "enterprise" "explore" "features" "issues"
    "login" "marketplace" "new" "notifications" "orgs" "pricing" "pulls"
    "search" "settings" "sponsors" "topics" "users")
  "Top-level GitHub paths that name a site page rather than an account.")

(defconst my-org-github-link-url-re
  (concat "\\`https?://\\(?:www\\.\\)?github\\.com/"
          "\\([[:alnum:]-]+\\)/\\([[:alnum:]._-]+\\)"
          "\\(?:/\\(?:issues\\|pull\\)/\\([0-9]+\\)\\(?:[/?#][^[:space:]]*\\)?"
          "\\|/?\\)\\'")
  "Match a repository, issue, or pull request URL on github.com.
Group 1 holds the owner, group 2 the repository, and group 3 the number.")

(defun my-org-github-link-format (text)
  "Return TEXT as an Org link when TEXT is one GitHub URL, or nil otherwise.
Surrounding whitespace in TEXT is ignored.  The description reads
OWNER/REPO#NUMBER for an issue or a pull request, and OWNER/REPO for a
repository."
  (let ((url (string-trim text)))
    (when (and (string-match my-org-github-link-url-re url)
               (not (member (match-string 1 url)
                            my-org-github-link-reserved-owners)))
      (let* ((owner (match-string 1 url))
             (repository (string-remove-suffix ".git" (match-string 2 url)))
             (number (match-string 3 url))
             (description (if number
                              (format "%s/%s#%s" owner repository number)
                            (format "%s/%s" owner repository))))
        (format "[[%s][%s]]" url description)))))

(defun my-org-github-link-point-in-link-target-p ()
  "Return non-nil when point sits between `[[' and the next `]' on the line."
  (and (looking-back "\\[\\[[^]\n]*" (line-beginning-position))
       (looking-at-p "[^[\n]*\\]")))

(defun my-org-github-link-transform-yank (text)
  "Return TEXT formatted by `my-org-github-link-format', or TEXT itself.
Point inside an existing Org link keeps TEXT, so that pasting a target
into `[[]]' does not nest one link in another."
  (or (and (not (my-org-github-link-point-in-link-target-p))
           (my-org-github-link-format text))
      text))

;;;###autoload
(define-minor-mode my-org-github-link-mode
  "Format a yanked GitHub issue, pull request, or repository URL as a link."
  :lighter nil
  (if my-org-github-link-mode
      (add-hook 'yank-transform-functions
                #'my-org-github-link-transform-yank nil t)
    (remove-hook 'yank-transform-functions
                 #'my-org-github-link-transform-yank t)))

(provide 'my-org-github-link)

;;; my-org-github-link.el ends here
