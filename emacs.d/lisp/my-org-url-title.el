;;; my-org-url-title.el --- Fetch page titles for yanked URLs -*- lexical-binding: t; -*-

;;; Commentary:
;; `my-org-url-title-mode' turns a yanked web URL into an Org link whose
;; description is the page title:
;;
;;   https://example.com  ->  [[https://example.com][Example Domain]]
;;
;; The yank inserts the bare URL at once and fetches the page in the
;; background, so a slow site never blocks Emacs.  When the title arrives,
;; the URL at the yank position becomes a link.  A failed request, a page
;; without a title, or a URL edited in the meantime keeps the bare URL.
;;
;; Only a yank that consists of one http(s) URL triggers a fetch.  The mode
;; runs after `my-org-github-link-mode', so GitHub URLs keep their short
;; OWNER/REPO#NUMBER description.

;;; Code:

(require 'dom)
(require 'subr-x)
(require 'url-queue)
(require 'my-org-github-link)

(defgroup my-org-url-title nil
  "Fetch page titles for yanked URLs."
  :group 'org-link)

(defcustom my-org-url-title-max-length 80
  "Display width at which a fetched title gets cut and ends in `...'.
The width counts a full-width character as two columns.  nil keeps the
whole title."
  :type '(choice (natural :tag "Columns") (const :tag "No limit" nil)))

(defconst my-org-url-title-bare-url-regexp
  "\\`https?://[^][:space:]<>\"]+\\'"
  "Regexp that matches a whole string holding one http(s) URL.")

(defun my-org-url-title-bare-url (text)
  "Return TEXT without surrounding whitespace when it is one URL, else nil."
  (let ((url (string-trim text)))
    (and (string-match-p my-org-url-title-bare-url-regexp url) url)))

(defun my-org-url-title-normalize (text)
  "Return TEXT with whitespace runs collapsed, or nil when TEXT is blank."
  (let ((normalized (and text (string-trim (replace-regexp-in-string
                                            "[[:space:]\n]+" " " text)))))
    (and normalized (not (string-empty-p normalized)) normalized)))

(defun my-org-url-title-extract-title (html)
  "Return the page title in the HTML string, or nil when the page has none.
The <title> element wins.  An `og:title' meta tag serves as the fallback,
because some single-page apps leave <title> empty."
  (let* ((dom (with-temp-buffer
                (insert html)
                (libxml-parse-html-region (point-min) (point-max))))
         (title-element (car (dom-by-tag dom 'title)))
         (og-element (seq-find (lambda (meta)
                                 (equal (dom-attr meta 'property) "og:title"))
                               (dom-by-tag dom 'meta))))
    (or (and title-element (my-org-url-title-normalize
                            (dom-inner-text title-element)))
        (and og-element (my-org-url-title-normalize
                         (dom-attr og-element 'content))))))

(defun my-org-url-title-format-link (url title)
  "Return an Org link to URL described by TITLE.
Square brackets in TITLE become braces, because `]]' would end the link.
A title wider than `my-org-url-title-max-length' gets cut."
  (let ((bracketless-title (replace-regexp-in-string
                            "\\]" "}" (replace-regexp-in-string
                                        "\\[" "{" title))))
    (format "[[%s][%s]]" url
            (if my-org-url-title-max-length
                (truncate-string-to-width bracketless-title
                                          my-org-url-title-max-length
                                          nil nil "...")
              bracketless-title))))

(defun my-org-url-title-response-coding (headers body-start)
  "Return the coding system that the current response buffer declares.
HEADERS holds the HTTP header text.  The Content-Type header wins over a
<meta charset> in the first 2048 bytes after BODY-START.  The result
falls back to `utf-8' for a missing or unknown charset."
  (let* ((charset-regexp "charset=[\"']?\\([[:alnum:]_.:-]+\\)")
         (charset
          (or (and (string-match charset-regexp headers)
                   (match-string 1 headers))
              (save-excursion
                (goto-char body-start)
                (and (re-search-forward charset-regexp
                                        (min (point-max) (+ body-start 2048)) t)
                     (match-string 1)))))
         (coding (and charset (coding-system-from-name charset))))
    (or coding 'utf-8)))

(defun my-org-url-title-parse-response ()
  "Return the page title in the current HTTP response buffer, or nil.
The buffer holds the raw unibyte response, headers included, as
`url-retrieve' leaves it.  A response that is not HTML yields nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "\r?\n\r?\n" nil t)
      (let ((headers (buffer-substring-no-properties (point-min) (point)))
            (body-start (point)))
        (when (string-match-p "^content-type:[^\n]*html" (downcase headers))
          (my-org-url-title-extract-title
           (decode-coding-region
            body-start (point-max)
            (my-org-url-title-response-coding headers body-start) t)))))))

(defun my-org-url-title-insert-link (start url title)
  "Replace URL at marker START with a link described by TITLE.
Nothing changes when START no longer points at URL, such as after the
user edited the text before the title arrived."
  (when-let* ((buffer (marker-buffer start)))
    (with-current-buffer buffer
      (save-excursion
        (goto-char start)
        (when (looking-at (regexp-quote url))
          (replace-match (my-org-url-title-format-link url title) t t))))
    (set-marker start nil)))

(defun my-org-url-title-handle-response (status start url)
  "Insert the fetched title for URL at marker START unless STATUS has an error.
The function runs in the response buffer, and kills that buffer."
  (let ((title (and (not (plist-get status :error))
                    (my-org-url-title-parse-response))))
    (kill-buffer (current-buffer))
    (if title
        (my-org-url-title-insert-link start url title)
      (set-marker start nil))))

(defun my-org-url-title-transform-yank (text)
  "Return TEXT unchanged, and fetch the page title when TEXT is one URL.
Point inside an existing Org link skips the fetch, so that pasting a
target into `[[]]' does not nest one link in another."
  (when-let* ((url (and (not (my-org-github-link-point-in-link-target-p))
                        (my-org-url-title-bare-url text))))
    ;; The marker stays at the start of the yanked text because its
    ;; insertion type is nil.
    (url-queue-retrieve url #'my-org-url-title-handle-response
                        (list (copy-marker (point)) url) t t))
  text)

;;;###autoload
(define-minor-mode my-org-url-title-mode
  "Turn a yanked URL into an Org link described by the page title."
  :lighter nil
  (if my-org-url-title-mode
      ;; Depth 90 runs this function after `my-org-github-link-mode', which
      ;; has already turned a GitHub URL into a link that is no bare URL.
      (add-hook 'yank-transform-functions
                #'my-org-url-title-transform-yank 90 t)
    (remove-hook 'yank-transform-functions
                 #'my-org-url-title-transform-yank t)))

(provide 'my-org-url-title)

;;; my-org-url-title.el ends here
