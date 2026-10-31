;;; my-org-github-link.el --- Format yanked GitHub URLs as Org links -*- lexical-binding: t; -*-

;;; Commentary:
;; `my-org-github-link-mode' rewrites a yanked GitHub URL into an Org link
;; with a short description:
;;
;;   https://github.com/owner/repo/issues/20      -> owner/repo#20
;;   .../issues/20#issuecomment-1                  -> owner/repo#20 (comment)
;;   .../pull/21#pullrequestreview-1               -> owner/repo#21 (review)
;;   .../pull/21/files                             -> owner/repo#21 (files)
;;   https://github.com/owner/repo                 -> owner/repo
;;
;; Only a yank that consists of one URL changes.  Other GitHub pages, such
;; as file views and commits, stay as plain URLs.

;;; Code:

(require 'subr-x)

(defconst my-org-github-link-reserved-owners
  '("about" "apps" "collections" "enterprise" "explore" "features" "issues"
    "login" "marketplace" "new" "notifications" "orgs" "pricing" "pulls"
    "search" "settings" "sponsors" "topics" "users")
  "Top-level GitHub paths that name a site page rather than an account.")

(defconst my-org-github-link-anchor-labels
  '(("\\`\\(?:issuecomment-\\|discussion_r\\|r\\)[0-9]+\\'" . "comment")
    ("\\`pullrequestreview-[0-9]+\\'" . "review"))
  "Alist from a URL fragment regexp to the label that the description shows.")

(defconst my-org-github-link-url-re
  (concat "\\`https?://\\(?:www\\.\\)?github\\.com"
          "/\\([[:alnum:]-]+\\)/\\([[:alnum:]._-]+\\)"
          "\\(?:/\\(?:issues\\|pull\\)/\\([0-9]+\\)"
          "\\(?:/\\([[:alpha:]]*\\)[^?#[:space:]]*\\)?"
          "\\(?:\\?[^#[:space:]]*\\)?"
          "\\(?:#\\([^[:space:]]*\\)\\)?"
          "\\|/?\\)\\'")
  "Match a repository, issue, or pull request URL on github.com.
The groups hold: 1 the owner, 2 the repository, 3 the number, 4 the first
path segment after the number, and 5 the fragment.")

(defun my-org-github-link-detail-label (subpage fragment)
  "Return the label for FRAGMENT, else for SUBPAGE, or nil for neither.
A comment or review FRAGMENT wins over a SUBPAGE such as `files'."
  (or (and fragment
           (cdr (seq-find (lambda (entry) (string-match-p (car entry) fragment))
                          my-org-github-link-anchor-labels)))
      (and subpage (not (string-empty-p subpage)) subpage)))

(defun my-org-github-link-format (text)
  "Return TEXT as an Org link when TEXT is one GitHub URL, or nil otherwise.
Surrounding whitespace in TEXT is ignored.  The description reads
OWNER/REPO#NUMBER for an issue or a pull request, followed by a label in
parentheses for a comment, a review, or a tab such as `files'.  A
repository gets OWNER/REPO."
  (let ((url (string-trim text)))
    (when (and (string-match my-org-github-link-url-re url)
               (not (member (match-string 1 url)
                            my-org-github-link-reserved-owners)))
      (let* ((repository (format "%s/%s" (match-string 1 url)
                                 (string-remove-suffix ".git"
                                                       (match-string 2 url))))
             (number (match-string 3 url))
             (label (my-org-github-link-detail-label (match-string 4 url)
                                                     (match-string 5 url)))
             (description
              (cond (label (format "%s#%s (%s)" repository number label))
                    (number (format "%s#%s" repository number))
                    (t repository))))
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
