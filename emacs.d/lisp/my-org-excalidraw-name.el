;;; my-org-excalidraw-name.el --- Name excalidraw drawings after the Org file -*- lexical-binding: t; -*-

;;; Commentary:
;; `my-org-excalidraw-name-create-drawing' replaces the file name prompt of
;; `org-excalidraw-create-drawing'.  The drawing for 2026-10-25.org lands in
;; `org-excalidraw-default-directory' as 2026-10-25-1.excalidraw, then
;; 2026-10-25-2.excalidraw, and so on.  With a prefix argument, the command
;; asks for a label instead and names the drawing 2026-10-25-LABEL.excalidraw.

;;; Code:

(require 'my-org-drawing-name)

(defvar org-excalidraw-default-directory)
(defvar org-excalidraw-default-template)
(declare-function org-excalidraw-link-open "org-excalidraw" (link))
(declare-function org-excalidraw-create-drawing "org-excalidraw" ())

;;;###autoload
(defun my-org-excalidraw-name-create-drawing (label)
  "Create a drawing named after the current Org file and link it at point.
Interactively, a prefix argument reads LABEL.  A buffer without a file
falls back to the file name prompt of `org-excalidraw-create-drawing'."
  (interactive
   (list (and current-prefix-arg (read-string "Drawing label: "))))
  (let ((source-file (my-org-drawing-name-source-file)))
    (if (not source-file)
        (call-interactively #'org-excalidraw-create-drawing)
      (let ((path (my-org-drawing-name-new-path
                   source-file label org-excalidraw-default-directory
                   ".excalidraw")))
        (with-temp-file path
          (insert org-excalidraw-default-template))
        (insert (format "[[excalidraw:%s]]" path))
        (org-excalidraw-link-open path)))))

(provide 'my-org-excalidraw-name)

;;; my-org-excalidraw-name.el ends here
