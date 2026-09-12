;;; my-ollama-test.el --- Tests for the Ollama model provisioning -*- lexical-binding: t; -*-

;;; Commentary:
;; The module decides which models to download at startup, so the tests pin
;; down that decision: which names count as already installed, and when a
;; download starts at all.  They inject stubs through
;; `my-ollama-fetch-installed-models-function' and
;; `my-ollama-pull-model-function', which keeps a running Ollama server out of
;; the test dependencies.
;;
;; Run with:
;;
;;   emacs -Q --batch -L lisp -l ert \
;;     -l tests/my-ollama-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'my-ollama)

(defun my-ollama-test--collect-pulls (required installed)
  "Return the models `my-ollama-ensure-models' downloads.
REQUIRED is the wanted model list.  INSTALLED is what the stub server answers,
or the symbol `unreachable' to make the fetch fail."
  (let* ((pulled (list))
         ;; An empty default keeps the fallback in `my-ollama-ensure-models'
         ;; out of the cases that pass REQUIRED explicitly.
         (my-ollama-required-models nil)
         (my-ollama-fetch-installed-models-function
          (lambda (on-success)
            (unless (eq installed 'unreachable)
              (funcall on-success installed))))
         (my-ollama-pull-model-function
          (lambda (model) (push model pulled))))
    (my-ollama-ensure-models required)
    (nreverse pulled)))

(ert-deftest my-ollama-should-list-the-models-in-a-tags-response ()
  (let ((payload "{\"models\":[{\"name\":\"gemma3:4b\"},{\"name\":\"qwen2.5-coder:3b\"}]}"))
    (should (equal (my-ollama-parse-installed-models payload)
                   '("gemma3:4b" "qwen2.5-coder:3b")))))

(ert-deftest my-ollama-should-list-no-model-for-an-empty-tags-response ()
  (should (equal (my-ollama-parse-installed-models "{\"models\":[]}") nil)))

(ert-deftest my-ollama-should-list-no-model-for-a-malformed-tags-response ()
  (should (equal (my-ollama-parse-installed-models "not json") nil)))

(ert-deftest my-ollama-should-report-a-model-the-server-lacks ()
  (should (equal (my-ollama-missing-models '("qwen2.5-coder:3b") '("gemma3:4b"))
                 '("qwen2.5-coder:3b"))))

(ert-deftest my-ollama-should-report-nothing-when-every-model-is-installed ()
  (should (equal (my-ollama-missing-models '("gemma3:4b") '("gemma3:4b" "qwen2.5-coder:3b"))
                 nil)))

(ert-deftest my-ollama-should-match-an-untagged-name-against-the-latest-tag ()
  (should (equal (my-ollama-missing-models '("gemma3") '("gemma3:latest")) nil)))

(ert-deftest my-ollama-should-keep-a-name-whose-tag-differs-from-latest ()
  (should (equal (my-ollama-missing-models '("gemma3:4b") '("gemma3:latest"))
                 '("gemma3:4b"))))

(ert-deftest my-ollama-should-report-each-missing-model-once ()
  (should (equal (my-ollama-missing-models '("gemma3:4b" "gemma3:4b") nil)
                 '("gemma3:4b"))))

(ert-deftest my-ollama-should-pull-only-the-models-the-server-lacks ()
  (should (equal (my-ollama-test--collect-pulls
                  '("gemma3:4b" "qwen2.5-coder:3b") '("gemma3:4b"))
                 '("qwen2.5-coder:3b"))))

(ert-deftest my-ollama-should-pull-nothing-when-the-server-is-unreachable ()
  (should (equal (my-ollama-test--collect-pulls '("qwen2.5-coder:3b") 'unreachable)
                 nil)))

(ert-deftest my-ollama-should-pull-nothing-when-no-model-is-required ()
  (should (equal (my-ollama-test--collect-pulls nil '("gemma3:4b")) nil)))

(ert-deftest my-ollama-should-fall-back-to-the-required-model-list ()
  (let ((my-ollama-required-models '("qwen2.5-coder:3b"))
        (pulled (list)))
    (let ((my-ollama-fetch-installed-models-function
           (lambda (on-success) (funcall on-success nil)))
          (my-ollama-pull-model-function
           (lambda (model) (push model pulled))))
      (my-ollama-ensure-models))
    (should (equal pulled '("qwen2.5-coder:3b")))))

(ert-deftest my-ollama-should-build-the-tags-url-from-the-host ()
  (let ((my-ollama-host "localhost:11434"))
    (should (equal (my-ollama-tags-url) "http://localhost:11434/api/tags"))))

(ert-deftest my-ollama-should-build-the-completions-url-from-the-host ()
  (let ((my-ollama-host "localhost:11434"))
    (should (equal (my-ollama-completions-url)
                   "http://localhost:11434/v1/completions"))))

(ert-deftest my-ollama-fim-suffix-should-keep-the-text-after-the-cursor ()
  (should (equal (my-ollama-fim-suffix '(:after-cursor "\nreturn x\n"))
                 "\nreturn x\n")))

(ert-deftest my-ollama-fim-suffix-should-replace-an-empty-suffix ()
  (should (equal (my-ollama-fim-suffix '(:after-cursor "")) "\n")))

(ert-deftest my-ollama-fim-suffix-should-replace-a-missing-suffix ()
  (should (equal (my-ollama-fim-suffix '(:before-cursor "if ")) "\n")))

(ert-deftest my-ollama-fim-suffix-should-keep-a-whitespace-suffix ()
  (should (equal (my-ollama-fim-suffix '(:after-cursor "  ")) "  ")))

(provide 'my-ollama-test)
;;; my-ollama-test.el ends here
