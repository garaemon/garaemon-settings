;;; euslisp-mode.el --- EusLisp mode

;; Copyright (C) 1985, 1986, 1999, 2000, 2001 Free Software Foundation, Inc.
;; Copyright (C) 2005 Takashi Ogura

;; Maintainer: ogura@jsk.t.u-tokyo.ac.jp
;; Keywords: euslisp

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:
;; Almost all code are lisp mode
;;
;;  added (string-match ":.*" function)
;;   Takashi Ogura 12/10/2003

;;; Code:


;; (font-lock-add-keywords 'euslisp-mode
;;   '((lisp-font-lock-keywords
;;      lisp-font-lock-keywords-1 lisp-font-lock-keywords-2 euslisp-font-lock-keywords)
;;     nil nil (("+-*/.<>=!?$%_&~^:" . "w")) beginning-of-defun
;;     (font-lock-mark-block-function . mark-defun)))

;;(font-lock-add-keywords 'lisp-mode 'euslisp-font-lock-keywords)
(defun euslisp-mode ()
  "Major mode for editing Lisp code to run in Emacs.
Commands:
Delete converts tabs to spaces as it moves back.
Blank lines separate paragraphs.  Semicolons start comments.
\\{euslisp-mode-map}
Entry to this mode calls the value of `euslisp-mode-hook'
if that value is non-nil."
  (interactive)
  (kill-all-local-variables)
  (use-local-map lisp-mode-map)
  (set-syntax-table lisp-mode-syntax-table)
  (setq major-mode 'euslisp-mode)
  (setq mode-name "EusLisp")
  (lisp-mode-variables nil)
  (setq imenu-case-fold-search nil)
  (setq lisp-indent-function 'euslisp-indent-function)
  ;;(run-hooks 'lisp-mode-hook)
  (run-hooks 'euslisp-mode-hook)
  )


(defun euslisp-indent-function (indent-point state)
  (let ((normal-indent (current-column)))
    (goto-char (1+ (elt state 1)))
    (parse-partial-sexp (point) calculate-lisp-indent-last-sexp 0 t)
    (if (and (elt state 2)
             (not (looking-at "\\sw\\|\\s_")))
        ;; car of form doesn't seem to be a a symbol
        (progn
          (if (not (> (save-excursion (forward-line 1) (point))
                      calculate-lisp-indent-last-sexp))
              (progn (goto-char calculate-lisp-indent-last-sexp)
                     (beginning-of-line)
                     (parse-partial-sexp (point)
					 calculate-lisp-indent-last-sexp 0 t)))
          ;; Indent under the list or under the first sexp on the same
          ;; line as calculate-lisp-indent-last-sexp.  Note that first
          ;; thing on that line has to be complete sexp since we are
          ;; inside the innermost containing sexp.
          (backward-prefix-chars)
          (current-column))
      (let ((function (buffer-substring (point)
					(progn (forward-sexp 1) (point))))
	    method)
	(setq method (or (get (intern-soft function) 'lisp-indent-function)
			 (get (intern-soft function) 'lisp-indent-hook)))
	(cond ((or (eq method 'defun)
		   (string-match ":.*" function) ;; add by ogura
		   (and (null method)
			(> (length function) 3)
			(string-match "\\`def" function)))
	       (lisp-indent-defform state indent-point))
	      ((integerp method)
	       (lisp-indent-specform method state
				     indent-point normal-indent))
	      (method
		(funcall method state indent-point)))))))

;; (put 'progn 'lisp-indent-function 0), say, causes progn to be indented
;; like defun if the first form is placed on the next line, otherwise
;; it is indented like any other form (i.e. forms line up under first).
(put 'with-open-file 'lisp-indent-function 1)
(put 'eval-debug 'lisp-indent-function 1)
(put 'do-until-key 'lisp-indent-function nil)
(put 'while* 'lisp-indent-function 1)



(defun euslisp-complete-method-list ()
  (let (start p word buffer sbuffer sprocess complist)
    ;;(save-excursion
    (skip-chars-backward "^\n\t ") ;; 空白以外を読み飛ばす
    (skip-chars-backward "\t ") ;; 空白を読み飛ばす
    (setq p (point))
    (skip-chars-backward "^\n\t ") ;; 空白以外を読み飛ばす
    (setq start (point))
    (setq word (buffer-substring start p))
    (setq sbuffer (get-buffer "*shell*")
	  sprocess (get-buffer-process sbuffer))
    ;;     (setq buffer (get-buffer-create "*euslisp-completions*"))
    ;;     (set-process-buffer sprocess buffer)
    (set-buffer sbuffer)
    (search-backward "$" nil t) ;; プロンプトへ
    (forward-char 2) ;; コマンドの先頭へ
    (kill-line) ;; コマンドを削除
    (process-send-string sprocess (format "(mapcar #'(lambda(x) (if (listp x) (setq x (car x))) (list (concatenate string \":\" (string-downcase (string x))))) (send %s :methods))\n" word)) ;; methodを表示させる
    ;;(search-backward "\n" nil t) ;; methodの最後までもどる
    ;;(setq p (point))
    (sleep-for 0 20) ;; コマンドの出力が終わるまで待つ (適当．．．)
    (search-backward "$" nil t 2) ;; methodの最初
    (forward-char 2)
    (setq start (point))
    (end-of-line)
    (setq p (point))
    ;;(message (format "Got: %s" (buffer-substring start2 p2)))
    (setq complist (car (read-from-string (buffer-substring start p)))) ;; GET!
    (kill-region start (point-max))
    (insert (nth 1 kill-ring-yank-pointer)) ;; 入力済み
    (rotate-yank-pointer 2);; kill ring バッファをもとに戻す
    complist))

(defun euslisp-complete-function-list-org ()
  (let (start p word buffer sbuffer sprocess complist)
    ;;(save-excursion
    (setq sbuffer (get-buffer "*shell*")
	  sprocess (get-buffer-process sbuffer))
    ;;     (setq buffer (get-buffer-create "*euslisp-completions*"))
    ;;     (set-process-buffer sprocess buffer)
    (set-buffer sbuffer)
    (search-backward "$" nil t) ;; プロンプトへ
    (forward-char 2) ;; コマンドの先頭へ
    (kill-line) ;; コマンドを削除
    (process-send-string sprocess "(mapcar #'(lambda (x) (list (string-downcase (string x)))) (functions))\n")
    (sleep-for 0 50) ;; コマンドの出力が終わるまで待つ (適当．．．)
    (search-backward "$" nil t 2) ;; methodの最初
    (forward-char 2)
    (setq start (point))
    (end-of-line)
    (setq p (point))
    ;;(message (format "Got: %s" (buffer-substring start2 p2)))
    (setq complist (car (read-from-string (buffer-substring start p)))) ;; GET!
    (kill-region start (point-max))
    (insert (nth 1 kill-ring-yank-pointer)) ;; 入力済み
    (rotate-yank-pointer 2);; kill ring バッファをもとに戻す
    complist))

(defun euslisp-complete-symbol ()
  "Complete EusLisp methods"
  (interactive)
  (let (word (p (point)) clist start result start2 p2)
    (save-excursion
      (skip-chars-backward "^\n\t ")
      (setq start (point))
      (setq word (buffer-substring start p))
      ;; 判別のため
      (skip-chars-backward "\t ")
      (setq p2 (point))
      (search-backward "$")
      (setq start2 (point))
      )
    (cond
     ((string= (buffer-substring start2 p2) "$") ;; function
      (setq clist (euslisp-complete-function-list)))
     (t ;; method
      (setq clist (euslisp-complete-method-list))))
    (setq result (try-completion word clist))
    (cond
     ((eq result t) (message ""))
     ((eq result nil) (error "Nothing to complete"))
     ((string= result word)
      (with-output-to-temp-buffer "*Completions*"
	(display-completion-list
	 (all-completions word clist))))
     (t (delete-region start p)
	(insert result)
	(if (eq t (try-completion result clist))
	    nil
	  (message "There are some completions"))))))

(defun euslisp-make-accessor (slot arg)
  "Insert accesser interactively"
  (interactive "sslot name: \nsarg name: ")
  (insert "(:" slot " (&optional " arg ")" "(if " arg " (setq " slot " "arg ") "
	  slot "))")
  (message "inserted eus-method"))

(defun euslisp-make-class (cls spr)
  "Insert templete for defclass and defmethod"
  (interactive "sclass name: \nssuper class name: ")
  (insert "(defclass " cls "\n  :super " spr "\n  :slots ())\n\n")
  (insert "(defmethod " cls "\n )")
  (message "inserted eus-class"))

;;add keywords by R.Ueda
(defconst euslisp-font-lock-keywords
  (append lisp-font-lock-keywords-2
	  (list
	   (cons (concat
		  "(" (regexp-opt
		       '("defforeign") t)
		  "\\>")
		 1)
	   (list "\\(self\\)\\>"
		 '(1 font-lock-constant-face nil t))
	   (list "\\(\\*\\w\+\\*\\)\\>"
		 '(1 font-lock-constant-face nil t))
	   (list "\\(#\\+\.\*\\)"
		 '(1 font-lock-variable-name-face))
	   (list "\\(#\\-\.\*\\)"
		 '(1 font-lock-variable-name-face))
	   (list "\\(evaldebug\\)\\>"
		 '(1 font-lock-constant-face nil t))
	   ))
  "Minimal highlighting expressions for EusLisp mode")

;; (define-derived-mode euslisp-mode lisp-mode "EusLisp"
;;   "Major mode for editing EusLisp files"
;;   (set (make-local-variable 'font-lock-defaults)
;;        '((lisp-font-lock-keywords
;; 	  lisp-font-lock-keywords-1 lisp-font-lock-keywords-2 euslisp-font-lock-keywords)
;; 	  nil nil (("+-*/.<>=!?$%_&~^:" . "w")) beginning-of-defun
;; 	  (font-lock-mark-block-function . mark-defun))))
;;(font-lock-add-keywords 'lisp-mode 'euslisp-font-lock-keywords)

;;(setq lisp-font-lock-keywords 'euslisp-mode)

(font-lock-add-keywords 'euslisp-mode
			(list
			 (list (concat
				"(" (regexp-opt '("defforeign") t) "\\>") '(1 font-lock-keyword-face nil t))
			 (list "\\(self\\)\\>" '(1 font-lock-constant-face nil t))
			 (list "\\(\\*\\w\+\\*\\)\\>" '(1 font-lock-constant-face nil t))
			 (list "\\(#\\(\\+\\|\\-\\)\.\*\\)" '(1 font-lock-variable-name-face))
			 (list "\\(check-ik-solvable\\)" '(1 font-lock-keyword-face nil t))
			 (list "\\(ik-block\\)" '(1 font-lock-keyword-face nil t))
			 (list "\\(ar-warn\\)" '(1 font-lock-warning-face nil t))
			 (list "\\(warning\\)" '(1 font-lock-warning-face nil t))
			 ;;(list "\\(catch\\*\\)\\>" '(1 font-lock-constant-face nil t))
			 (list (concat (regexp-opt '("catch*") t) "\\>") '(1 font-lock-constant-face nil t))
			 (list "\\(throw-error\\)" '(1 font-lock-warning-face nil t))))

(provide 'euslisp-mode)

;;; euslisp-mode.el ends here
