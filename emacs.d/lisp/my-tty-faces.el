;;; my-tty-faces.el --- Readable highlight faces on terminal frames -*- lexical-binding: t; -*-

;;; Commentary:
;; Terminal frames load no theme, so `hl-line' and `show-paren-match' fall
;; back to the stock darkolivegreen and steelblue3 backgrounds.  Under a
;; truecolor terminal with the Ghostty Spacedust theme (background #0a1e24),
;; those bright backgrounds bury the text.  The tty branches below use dark
;; tones close to that background and leave graphic frames untouched.

;;; Code:

(defconst my-tty-faces-line-background "#13323c"
  "Background of the current line on terminal frames.
The tone sits slightly above the Spacedust background #0a1e24.")

(defconst my-tty-faces-paren-background "#0a385c"
  "Background of the matched expression on terminal frames.
The color reuses the Spacedust selection background, a blue that
stays distinct from the highlighted current line.")

(defun my-tty-faces-apply ()
  "Give `hl-line' and `show-paren-match' dark backgrounds on tty frames.
The specs change the face defaults, so every frame, including one
that emacsclient opens later, picks the branch that fits its display."
  (face-spec-set
   'hl-line
   `((((type tty)) :background ,my-tty-faces-line-background :extend t)
     (t :inherit highlight :extend t))
   'face-defface-spec)
  (face-spec-set
   'show-paren-match
   `((((type tty)) :background ,my-tty-faces-paren-background)
     (((class color) (background light)) :background "turquoise")
     (((class color) (background dark)) :background "steelblue3")
     (((background dark) (min-colors 4)) :background "grey50")
     (((background light) (min-colors 4)) :background "gray")
     (t :inherit underline))
   'face-defface-spec))

(provide 'my-tty-faces)
;;; my-tty-faces.el ends here
