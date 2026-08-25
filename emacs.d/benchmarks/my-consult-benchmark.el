;;; my-consult-benchmark.el --- Timings for the consult-buffer sources -*- lexical-binding: t; -*-

;;; Commentary:
;; Every scenario here runs on the path that `C-x b' takes: collect the
;; candidates of the custom sources, then filter them once per keystroke.
;; Both costs grow with the number of tracked files, so each scenario runs
;; against a generated repository rather than this checkout, whose size would
;; otherwise decide the numbers.
;;
;; The scenarios report nothing on a branch that predates
;; `my-consult-sources', which is what the `n/a' cells of the first
;; comparison mean.
;;
;; Preview is deliberately absent.  Its cost lives in the major mode that
;; opens the file, so a bare batch Emacs with no tree-sitter grammars and no
;; language packages would report a number unrelated to the editor the
;; configuration actually builds.

;;; Code:

(require 'my-benchmark)

(declare-function consult--multi-collection "consult" (sources))
(declare-function consult--multi-enabled-sources "consult" (sources))
(declare-function my-get-git-files "my-consult-sources" ())
(defvar my-git-files-source)

(defconst my-consult-benchmark-repository-sizes '(1000 10000)
  "File counts of the generated repositories, one scenario set per size.")

(defconst my-consult-benchmark-files-per-directory 100
  "Files placed in each generated directory.
A single flat directory of ten thousand entries would measure the file
system more than it measures the code under test.")

(defvar my-consult-benchmark--repositories nil
  "Alist mapping a file count to the generated repository that holds it.")

(defvar my-consult-benchmark--candidates nil
  "Candidates collected by the most recent collect scenario.")

(defun my-consult-benchmark--make-repository (file-count)
  "Create a git repository holding FILE-COUNT tracked files and return its path.
The repository is generated once per Emacs process and reused afterwards."
  (or (cdr (assq file-count my-consult-benchmark--repositories))
      (let ((root (file-name-as-directory (make-temp-file "my-consult-bench" t))))
        (dotimes (index file-count)
          (let ((path (expand-file-name
                       (format "dir%03d/file%03d.el"
                               (/ index my-consult-benchmark-files-per-directory)
                               (% index my-consult-benchmark-files-per-directory))
                       root)))
            (make-directory (file-name-directory path) t)
            (with-temp-file path (insert ";; benchmark fixture\n"))))
        (let ((default-directory root))
          (dolist (command '(("init" "--quiet")
                             ("config" "user.email" "benchmark@example.com")
                             ("config" "user.name" "benchmark")
                             ("add" "--all")))
            (apply #'call-process "git" nil nil nil command)))
        (push (cons file-count root) my-consult-benchmark--repositories)
        root)))

(defun my-consult-benchmark--sources-available-p ()
  "Return non-nil when this branch carries the custom consult sources.
`my-get-git-files' reaches the repository root through magit and lists the
files through vc-git.  Both have to be loaded outright, because a batch
Emacs autoloads neither `magit-toplevel' nor `vc-git-command'."
  (and (require 'my-consult-sources nil 'noerror)
       (require 'magit nil 'noerror)
       (require 'vc-git nil 'noerror)
       (fboundp 'my-get-git-files)))

(defun my-consult-benchmark--collection-available-p ()
  "Return non-nil when consult can build a collection from the custom sources."
  (and (my-consult-benchmark--sources-available-p)
       (require 'consult nil 'noerror)
       (fboundp 'consult--multi-collection)))

(defun my-consult-benchmark--filtering-available-p ()
  "Return non-nil when the filtering scenarios can run under orderless."
  (and (my-consult-benchmark--collection-available-p)
       (require 'orderless nil 'noerror)))

(defun my-consult-benchmark--collect (file-count)
  "Collect the `Git Files' candidates of the repository holding FILE-COUNT files."
  (let ((default-directory (my-consult-benchmark--make-repository file-count)))
    (setq my-consult-benchmark--candidates
          (consult--multi-collection
           (consult--multi-enabled-sources (list my-git-files-source))))))

(defun my-consult-benchmark--filter (input)
  "Filter the collected candidates by INPUT the way the completion UI does.
The styles mirror the `completion-styles' that `init-editor.el' sets for
orderless.  A batch Emacs otherwise falls back to the far cheaper built-in
styles and reports a cost no keystroke ever pays."
  (let ((completion-styles '(orderless basic))
        (completion-category-defaults nil))
    (completion-all-completions input my-consult-benchmark--candidates nil
                                (length input)
                                '(metadata (category . multi-category)))))

(dolist (size my-consult-benchmark-repository-sizes)
  (my-benchmark-define
   (format "git-files/%d" size)
   :available-p #'my-consult-benchmark--sources-available-p
   :setup (lambda () (my-consult-benchmark--make-repository size))
   :thunk (lambda ()
            (let ((default-directory (my-consult-benchmark--make-repository size)))
              (my-get-git-files))))

  (my-benchmark-define
   (format "consult-collect/%d" size)
   :available-p #'my-consult-benchmark--collection-available-p
   :setup (lambda () (my-consult-benchmark--make-repository size))
   :thunk (lambda () (my-consult-benchmark--collect size)))

  ;; A single letter is the worst keystroke: it rejects almost nothing, so the
  ;; completion style pays for every candidate.
  (my-benchmark-define
   (format "consult-filter-1-char/%d" size)
   :available-p #'my-consult-benchmark--filtering-available-p
   :setup (lambda () (my-consult-benchmark--collect size))
   :thunk (lambda () (my-consult-benchmark--filter "e")))

  (my-benchmark-define
   (format "consult-filter-8-chars/%d" size)
   :available-p #'my-consult-benchmark--filtering-available-p
   :setup (lambda () (my-consult-benchmark--collect size))
   :thunk (lambda () (my-consult-benchmark--filter "file0042"))))

(provide 'my-consult-benchmark)
;;; my-consult-benchmark.el ends here
