;;; my-org-url-title-test.el --- Tests for fetching page titles on yank -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for lisp/my-org-url-title.el.  Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-org-url-title-test.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'my-org-github-link)
(require 'my-org-url-title)

(defconst my-org-url-title-test-japanese "\u65e5\u672c\u8a9e"
  "A title that UTF-8 and Shift_JIS encode differently.")

(defun my-org-url-title-test-make-response (headers body coding)
  "Return a unibyte HTTP response with HEADERS and BODY encoded in CODING."
  (concat headers "\n\n" (encode-coding-string body coding)))

(defmacro my-org-url-title-test-with-response (response &rest body)
  "Run BODY, then answer every `url-queue-retrieve' call with RESPONSE.
The answers come after BODY, as the real queue answers after the yank.
A nil RESPONSE reports a network error to the callback."
  (declare (indent 1))
  `(let ((pending-requests nil)
         (response-text ,response))
     (cl-letf (((symbol-function 'url-queue-retrieve)
                (lambda (_url callback &optional cbargs &rest _)
                  (push (cons callback cbargs) pending-requests))))
       ,@body)
     (dolist (request pending-requests)
       (with-current-buffer (generate-new-buffer " *response*" t)
         (set-buffer-multibyte nil)
         (when response-text (insert response-text))
         (apply (car request)
                (if response-text nil '(:error (error "offline")))
                (cdr request))))))

(ert-deftest my-org-url-title-test-accepts-bare-url ()
  (should (equal (my-org-url-title-bare-url " https://example.com/a?b=1\n")
                 "https://example.com/a?b=1")))

(ert-deftest my-org-url-title-test-rejects-url-inside-prose ()
  (should-not (my-org-url-title-bare-url "see https://example.com now")))

(ert-deftest my-org-url-title-test-rejects-org-link ()
  (should-not (my-org-url-title-bare-url "[[https://example.com][ex]]")))

(ert-deftest my-org-url-title-test-rejects-non-http-scheme ()
  (should-not (my-org-url-title-bare-url "file:///etc/hosts")))

(ert-deftest my-org-url-title-test-extracts-title ()
  (should (equal (my-org-url-title-extract-title
                  "<html><head><title> Hello\n  World </title></head></html>")
                 "Hello World")))

(ert-deftest my-org-url-title-test-decodes-entities ()
  (should (equal (my-org-url-title-extract-title
                  "<title>A &amp; B</title>")
                 "A & B")))

(ert-deftest my-org-url-title-test-falls-back-to-og-title ()
  (should (equal (my-org-url-title-extract-title
                  (concat "<head><meta property=\"og:title\" content=\"OG\">"
                          "<title></title></head>"))
                 "OG")))

(ert-deftest my-org-url-title-test-returns-nil-without-title ()
  (should-not (my-org-url-title-extract-title "<p>no title</p>")))

(ert-deftest my-org-url-title-test-formats-link ()
  (should (equal (my-org-url-title-format-link "https://e.com" "Title")
                 "[[https://e.com][Title]]")))

(ert-deftest my-org-url-title-test-replaces-brackets-in-title ()
  (should (equal (my-org-url-title-format-link "https://e.com" "[WIP] a]]b")
                 "[[https://e.com][{WIP} a}}b]]")))

(ert-deftest my-org-url-title-test-elides-long-title ()
  (let ((my-org-url-title-max-length 10))
    (should (equal (my-org-url-title-format-link "https://e.com"
                                                 "abcdefghijklmno")
                   "[[https://e.com][abcdefg...]]"))))

(ert-deftest my-org-url-title-test-elides-by-display-width ()
  (let ((my-org-url-title-max-length 7))
    (should (equal (my-org-url-title-format-link
                    "https://e.com" (concat my-org-url-title-test-japanese
                                            my-org-url-title-test-japanese))
                   (format "[[https://e.com][%s...]]"
                           (substring my-org-url-title-test-japanese 0 2))))))

(ert-deftest my-org-url-title-test-keeps-title-within-max-length ()
  (let ((my-org-url-title-max-length 10))
    (should (equal (my-org-url-title-format-link "https://e.com" "abcdefghij")
                   "[[https://e.com][abcdefghij]]"))))

(ert-deftest my-org-url-title-test-keeps-long-title-without-limit ()
  (let ((my-org-url-title-max-length nil))
    (should (equal (my-org-url-title-format-link "https://e.com"
                                                 (make-string 200 ?a))
                   (format "[[https://e.com][%s]]" (make-string 200 ?a))))))

(ert-deftest my-org-url-title-test-parses-utf-8-response ()
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert (my-org-url-title-test-make-response
             "HTTP/1.1 200 OK\nContent-Type: text/html; charset=utf-8"
             (format "<title>%s</title>" my-org-url-title-test-japanese) 'utf-8))
    (should (equal (my-org-url-title-parse-response)
                   my-org-url-title-test-japanese))))

(ert-deftest my-org-url-title-test-parses-meta-charset ()
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert (my-org-url-title-test-make-response
             "HTTP/1.1 200 OK\nContent-Type: text/html"
             (format "<meta charset=\"Shift_JIS\"><title>%s</title>"
                     my-org-url-title-test-japanese) 'shift_jis))
    (should (equal (my-org-url-title-parse-response)
                   my-org-url-title-test-japanese))))

(ert-deftest my-org-url-title-test-ignores-non-html-response ()
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert (my-org-url-title-test-make-response
             "HTTP/1.1 200 OK\nContent-Type: application/pdf"
             "<title>x</title>" 'utf-8))
    (should-not (my-org-url-title-parse-response))))

(ert-deftest my-org-url-title-test-yank-replaces-url-with-link ()
  (with-temp-buffer
    (org-mode)
    (my-org-url-title-mode 1)
    (my-org-url-title-test-with-response
        (my-org-url-title-test-make-response
         "HTTP/1.1 200 OK\nContent-Type: text/html" "<title>Ex</title>" 'utf-8)
      (insert "see ")
      (let ((kill-ring (list "https://example.com")))
        (yank)))
    (should (equal (buffer-string) "see [[https://example.com][Ex]]"))))

(ert-deftest my-org-url-title-test-yank-keeps-url-on-error ()
  (with-temp-buffer
    (org-mode)
    (my-org-url-title-mode 1)
    (my-org-url-title-test-with-response nil
      (let ((kill-ring (list "https://example.com")))
        (yank)))
    (should (equal (buffer-string) "https://example.com"))))

(ert-deftest my-org-url-title-test-skips-when-url-was-edited ()
  (with-temp-buffer
    (insert "https://example.org")
    (let ((start (copy-marker (point-min))))
      (my-org-url-title-insert-link start "https://example.com" "Ex"))
    (should (equal (buffer-string) "https://example.org"))))

(ert-deftest my-org-url-title-test-skips-inside-link-target ()
  (with-temp-buffer
    (org-mode)
    (my-org-url-title-mode 1)
    (insert "[[]]")
    (goto-char 3)
    (my-org-url-title-test-with-response
        (my-org-url-title-test-make-response
         "HTTP/1.1 200 OK\nContent-Type: text/html" "<title>Ex</title>" 'utf-8)
      (let ((kill-ring (list "https://example.com")))
        (yank)))
    (should (equal (buffer-string) "[[https://example.com]]"))))

(ert-deftest my-org-url-title-test-leaves-github-url-to-github-mode ()
  (with-temp-buffer
    (org-mode)
    (my-org-github-link-mode 1)
    (my-org-url-title-mode 1)
    (my-org-url-title-test-with-response
        (my-org-url-title-test-make-response
         "HTTP/1.1 200 OK\nContent-Type: text/html" "<title>Ex</title>" 'utf-8)
      (let ((kill-ring (list "https://github.com/a/b")))
        (yank)))
    (should (equal (buffer-string) "[[https://github.com/a/b][a/b]]"))))

(provide 'my-org-url-title-test)

;;; my-org-url-title-test.el ends here
