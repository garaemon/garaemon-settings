;;; my-org-present.el --- Slide styling for org-present -*- lexical-binding: t; -*-

;;; Commentary:
;; Buffer styling for org-present slide shows: larger text, centered
;; slides, top padding, and no editor chrome.  The two hook functions
;; save the buffer settings they change and restore them on quit, so a
;; slide deck edits like any other Org file between shows.
;;
;; The approach follows Alvaro Ramirez's org-present setup:
;; https://xenodium.com/emacs-org-present-in-style
;; which in turn builds on the System Crafters guide:
;; https://systemcrafters.net/emacs-tips/presentations-with-org-present/
;;
;; The functions here only touch buffer state, so the styling stays
;; testable without the org-present package.  init-org.el connects them
;; to `org-present-mode-hook' and `org-present-mode-quit-hook'.

;;; Code:

(require 'display-fill-column-indicator)
(require 'face-remap)
(require 'display-line-numbers)
(require 'org)
(require 'org-fold)

(declare-function visual-fill-column-mode "visual-fill-column")
(declare-function hide-mode-line-mode "hide-mode-line")

(defgroup my-org-present nil
  "Slide styling for org-present."
  :group 'org)

(defcustom my-org-present-face-remappings
  '((default :height 1.2)
    (org-level-1 :height 1.5)
    (org-block-begin-line :height 0)
    (org-block-end-line :height 0)
    (header-line :inherit default))
  "Relative face attributes applied for the duration of a slide show.
Each entry is (FACE . ATTRIBUTES), added with `face-remap-add-relative'
so that the text scaling of `org-present-big' stays in effect.
Heights are relative to the face, so 1.2 scales the text by 20%.
The zero height hides the #+begin_src and #+end_src lines while the
block body stays visible.  The header line inherits the default
face so that the top padding does not show up as a bar in themes
that give `header-line' its own background."
  :type '(alist :key-type face :value-type plist))

(defcustom my-org-present-top-padding-height 300
  "Height of the blank header line that pads the top of every slide.
The value is an absolute face height in units of 1/10 point."
  :type 'integer)

(defvar-local my-org-present--saved-settings nil
  "Buffer settings captured by `my-org-present-start' for the quit hook.
An alist of (SYMBOL . VALUE) for the variables the show overrides.")

(defvar-local my-org-present--face-cookies nil
  "Cookies from `face-remap-add-relative' that the quit hook removes.")

(defun my-org-present--remap-faces ()
  "Apply `my-org-present-face-remappings' to the current buffer."
  (setq my-org-present--face-cookies
        (mapcar (lambda (entry)
                  (face-remap-add-relative (car entry) (cdr entry)))
                my-org-present-face-remappings)))

(defun my-org-present--unmap-faces ()
  "Remove the face remappings added by `my-org-present--remap-faces'."
  (mapc #'face-remap-remove-relative my-org-present--face-cookies)
  (setq my-org-present--face-cookies nil))

(defun my-org-present--set-minor-modes (arg)
  "Toggle every presentation minor mode with ARG, 1 or -1."
  (visual-line-mode arg)
  (visual-fill-column-mode arg)
  (hide-mode-line-mode arg))

(defun my-org-present--save-settings ()
  "Record the buffer settings that the slide show overrides."
  (setq my-org-present--saved-settings
        (list (cons 'truncate-lines truncate-lines)
              (cons 'display-line-numbers-mode display-line-numbers-mode)
              (cons 'display-fill-column-indicator-mode
                    display-fill-column-indicator-mode))))

(defun my-org-present--restore-settings ()
  "Put back the buffer settings recorded by `my-org-present--save-settings'."
  (let-alist my-org-present--saved-settings
    (setq truncate-lines .truncate-lines)
    (display-line-numbers-mode (if .display-line-numbers-mode 1 -1))
    (display-fill-column-indicator-mode
     (if .display-fill-column-indicator-mode 1 -1)))
  (setq my-org-present--saved-settings nil))

(defun my-org-present-start ()
  "Style the current buffer as a slide show.
Intended for `org-present-mode-hook'."
  (my-org-present--save-settings)
  (my-org-present--remap-faces)
  (setq-local header-line-format
              (propertize " " 'face `(:height ,my-org-present-top-padding-height)))
  ;; Org starts every buffer truncated here (see `org-startup-truncated' in
  ;; init-org.el), but a slide reads better wrapped inside the centered
  ;; column than cut off at the window edge.
  (setq truncate-lines nil)
  (display-line-numbers-mode -1)
  (display-fill-column-indicator-mode -1)
  (my-org-present--set-minor-modes 1)
  (org-fold-show-children))

(defun my-org-present-quit ()
  "Undo the styling of `my-org-present-start'.
Intended for `org-present-mode-quit-hook'."
  (my-org-present--unmap-faces)
  (setq-local header-line-format nil)
  (my-org-present--set-minor-modes -1)
  (my-org-present--restore-settings))

(defun my-org-present-after-navigate (_buffer-name _heading)
  "Show the current slide with only its direct sub headings unfolded.
Intended for `org-present-after-navigate-functions'."
  (org-overview)
  (org-fold-show-entry)
  (org-fold-show-children))

(provide 'my-org-present)
;;; my-org-present.el ends here
