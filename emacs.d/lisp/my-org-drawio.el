;;; my-org-drawio.el --- Create and edit draw.io drawings from Org -*- lexical-binding: t; -*-

;;; Commentary:
;; Drawings use the .drawio.svg format: an SVG image that also embeds the
;; draw.io diagram.  Org shows the file as an ordinary inline image, so no
;; export step is needed, and the draw.io desktop app edits the same file.
;;
;; `my-org-drawio-create-drawing' names the drawing after the Org file, as
;; `my-org-excalidraw-name-create-drawing' does, inserts a file: link, and
;; opens the drawing in draw.io.  `my-org-drawio-open-file-app' plugs into
;; `org-file-apps' so that following such a link opens draw.io too.

;;; Code:

(require 'my-org-drawing-name)

(declare-function org-link-preview-region "ol" (&optional include-linked refresh beg end))
(declare-function org-display-inline-images "org" (&optional include-linked refresh beg end))

(defgroup my-org-drawio nil
  "Create and edit draw.io drawings from Org."
  :group 'org)

(defcustom my-org-drawio-directory "~/org/drawio/"
  "Directory that holds new drawings."
  :type 'directory)

(defcustom my-org-drawio-open-command
  (if (eq system-type 'darwin)
      '("open" "-a" "draw.io")
    '("drawio"))
  "Program and leading arguments that open a drawing in draw.io.
The path of the drawing follows the last argument."
  :type '(repeat string))

(defconst my-org-drawio-extension ".drawio.svg")

;; draw.io reads the diagram from the `content' attribute and rewrites the
;; whole SVG on save.  The white page background keeps dark strokes visible
;; on a dark Emacs theme, because draw.io exports a transparent page
;; otherwise.
(defconst my-org-drawio-template
  (concat
   "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\""
   " width=\"1px\" height=\"1px\" viewBox=\"-0.5 -0.5 1 1\""
   " content=\"&lt;mxfile&gt;&lt;diagram id=&quot;page-1&quot;"
   " name=&quot;Page-1&quot;&gt;&lt;mxGraphModel background=&quot;#ffffff&quot;&gt;"
   "&lt;root&gt;&lt;mxCell id=&quot;0&quot;/&gt;"
   "&lt;mxCell id=&quot;1&quot; parent=&quot;0&quot;/&gt;&lt;/root&gt;"
   "&lt;/mxGraphModel&gt;&lt;/diagram&gt;&lt;/mxfile&gt;\">"
   "<defs/><g/></svg>\n")
  "Contents of a new, empty drawing.")

(defconst my-org-drawio-text-warning-regexp
  (concat "<switch><g requiredFeatures=\"http://www\\.w3\\.org/TR/SVG11/"
          "feature#Extensibility\"[[:space:]]*/>[[:space:]]*<a\\b[^>]*>"
          "[[:space:]]*<text\\b[^>]*>Text is not SVG - cannot display</text>"
          "[[:space:]]*</a>[[:space:]]*</switch>")
  "Regexp for the warning that draw.io appends to an SVG with HTML labels.")

(defun my-org-drawio-strip-text-warning (svg)
  "Return SVG without the warning about HTML labels that draw.io appends.
librsvg cannot render HTML labels, so Emacs draws the warning across the
bottom of every drawing.  The labels keep their plain text fallback."
  (replace-regexp-in-string my-org-drawio-text-warning-regexp "" svg t t))

(defun my-org-drawio-image-args (args)
  "Return ARGS of `create-image' with a drawing file read as stripped data.
Leave ARGS unchanged unless they name an existing .drawio.svg file."
  (pcase-let ((`(,file-or-data ,_type ,data-p . ,props) args))
    (if (and (stringp file-or-data)
             (not data-p)
             (string-suffix-p my-org-drawio-extension file-or-data)
             (file-readable-p file-or-data))
        ;; Raw bytes keep non-ASCII labels intact for librsvg, which reads
        ;; image data as UTF-8.
        (let ((svg (with-temp-buffer
                     (set-buffer-multibyte nil)
                     (insert-file-contents-literally file-or-data)
                     (buffer-string))))
          `(,(my-org-drawio-strip-text-warning svg) svg t ,@props))
      args)))

(defun my-org-drawio-link (drawing-path source-file)
  "Return an Org link to DRAWING-PATH relative to the directory of SOURCE-FILE.
A relative link survives a move of the whole Org directory to another
machine."
  (format "[[file:%s]]"
          (file-relative-name drawing-path (file-name-directory source-file))))

(defun my-org-drawio-open-file (path)
  "Open the drawing at PATH in draw.io without waiting for the app to exit.
Signal `user-error' when `my-org-drawio-open-command' names a program
that is not installed."
  (let ((program (car my-org-drawio-open-command)))
    (unless (executable-find program)
      (user-error "Cannot find %s; install the draw.io desktop app" program))
    (make-process :name "drawio"
                  :command (append my-org-drawio-open-command
                                   (list (expand-file-name path)))
                  :noquery t
                  :connection-type 'pipe)))

(defun my-org-drawio-preview-region (beg end)
  "Show the image links between BEG and END inline.
Org 9.8 renamed `org-display-inline-images' to `org-link-preview-region'."
  (if (fboundp 'org-link-preview-region)
      (org-link-preview-region nil t beg end)
    (org-display-inline-images nil t beg end)))

;;;###autoload
(defun my-org-drawio-open-file-app (file &optional _link)
  "Open FILE in draw.io.  Meant for an `org-file-apps' entry."
  (my-org-drawio-open-file file))

(defun my-org-drawio-read-new-path ()
  "Read the path of a new drawing for a buffer that visits no file."
  (let ((path (read-file-name "Drawing file: " my-org-drawio-directory)))
    (if (string-suffix-p my-org-drawio-extension path)
        path
      (concat path my-org-drawio-extension))))

;;;###autoload
(defun my-org-drawio-create-drawing (label)
  "Create a draw.io drawing named after the current Org file and link it.
Interactively, a prefix argument reads LABEL.  A buffer without a file
asks for the path of the drawing instead and links it by absolute path."
  (interactive
   (list (and current-prefix-arg (read-string "Drawing label: "))))
  (let* ((source-file (my-org-drawing-name-source-file))
         (path (expand-file-name
                (if source-file
                    (my-org-drawing-name-new-path
                     source-file label my-org-drawio-directory
                     my-org-drawio-extension)
                  (my-org-drawio-read-new-path)))))
    (make-directory (file-name-directory path) t)
    (with-temp-file path
      (insert my-org-drawio-template))
    (let ((link-start (point)))
      (insert (if source-file
                  (my-org-drawio-link path source-file)
                (format "[[file:%s]]" path)))
      ;; The focus hook in init-org.el refreshes only buffers that already
      ;; show an image, so the new link needs a preview of its own.
      (my-org-drawio-preview-region link-start (point)))
    (my-org-drawio-open-file path)))

(provide 'my-org-drawio)

;;; my-org-drawio.el ends here
