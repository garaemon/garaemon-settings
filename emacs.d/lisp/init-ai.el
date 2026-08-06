;;; init-ai.el --- AI assistants and completion -*- lexical-binding: t -*-

;;; Commentary:
;; minuet inline completion, gptel chat, and agent-shell for ACP coding agents.

;;; Code:

(use-package minuet
  :ensure t
  :bind
  (:map minuet-active-mode-map
        ("TAB" . #'minuet-accept-suggestion) ;; accept whole completion
        ("<M-return>" . #'minuet-accept-suggestion) ;; accept whole completion
        ("M-A" . #'minuet-accept-suggestion) ;; accept whole completion
        ;; Accept the first line of completion, or N lines with a numeric-prefix:
        ;; e.g. C-u 2 M-a will accepts 2 lines of completion.
        ("M-a" . #'minuet-accept-suggestion-line)
        ("M-e" . #'minuet-dismiss-suggestion))
  :hook (prog-mode . minuet-auto-suggestion-mode)
  :custom
  (minuet-provider 'openai-fim-compatible)
  (minuet-auto-suggestion-debounce-delay 1.0)
  (minuet-n-completions 1)
  (minuet-context-window 1024)
  (minuet-request-timeout 10)
  ;; Do not show the completion when the cursor is NOT at the end of lines.
  (minuet-auto-suggestion-block-functions '(minuet-evil-not-insert-state-p my-not-eolp))
  :config
  (plist-put minuet-openai-fim-compatible-options
             :end-point "http://localhost:11434/v1/completions")
  ;; an arbitrary non-null environment variable as placeholder.
  ;; For Windows users, TERM may not be present in environment variables.
  ;; Consider using APPDATA instead.
  (plist-put minuet-openai-fim-compatible-options :name "Ollama")
  (plist-put minuet-openai-fim-compatible-options :api-key "TERM")
  ;; TODO: Install qwen2.5-coder:3b automatically
  ;; (plist-put minuet-openai-fim-compatible-options :model "qwen2.5-coder:3b")
  (plist-put minuet-openai-fim-compatible-options :model "deepseek-coder-v2:lite")

  (defun my-not-eolp ()
    (not (eolp)))

  (minuet-set-optional-options minuet-openai-fim-compatible-options :max_tokens 56)
  )

(use-package gptel :ensure t
  ;; TODO: Should I use \?
  :bind (("C-¥" . my-gptel-toggle)
         ("C-c g" . my-gptel-ask-about-code)
         :map gptel-mode-map
         ("C-c C-c" . gptel-send)
         ("C-c C-k" . my-gptel-archive-and-reset))
  :custom
  (gptel-directives
   '((default
      . "You are a large language model living in Emacs and a helpful assistant.
You have to follow the following orders:
- Respond concisely.
- Respond in Japanese. User is a Japanese. Even if the user uses English to ask questions, you have to answer in Japanese.
- Use English in program examples.
- Answer conclusions first.")
     (programming
      . "You are a large language model and a careful programmer. Provide code and only code as output without any additional text, prompt or note.")
     (writing
      . "You are a large language model and a writing assistant. Respond concisely.")
     (chat
      . "You are a large language model and a conversation partner. Respond concisely.")))
  :hook
  (gptel-mode . (lambda () (display-line-numbers-mode -1)))
  :config
  (if (not (display-graphic-p))
      ;; header-line for LSP mode is hard to see in emacs -nw environment.
      ;; https://emacs.stackexchange.com/questions/77279/how-can-i-find-the-face-of-the-items-in-the-headeline-in-lsp-mode
      (custom-set-faces
       '(header-line ((t (:inverse-video nil :underline t)))))
    )

  (setq gptel-model 'gemini-flash-latest
        gptel-backend (gptel-make-gemini "Gemini"
                        :key gptel-api-key
                        :stream t))

  (gptel-make-ollama "Ollama (gemmma3:4b)"
    :host "localhost:11434"
    :stream t
    :models '(gemma3:4b))

  (defun my-gptel-get-buffer ()
    (car (cl-remove-if #'null
                       (mapcar #'(lambda (buf)
                                   (with-current-buffer buf
                                     (if (member 'gptel-mode local-minor-modes)
                                         buf)))
                               (buffer-list)))))

  (defun my-gptel-toggle ()
    (interactive)
    (let ((gptel-buffer (my-gptel-get-buffer)))
      (if gptel-buffer
          (switch-to-buffer gptel-buffer)
        (call-interactively 'gptel)
        )))

  (defun my-gptel-archive-and-reset ()
    "Archives the current gptel buffer to ~/.gptel/sessions/ and clears/resets its content."
    (interactive)
    ;; Ensure the function is executed only in a gptel-mode buffer
    (unless gptel-mode
      (user-error "Not in a gptel buffer"))

    (let* ((base-dir (expand-file-name "~/.gptel/sessions/"))
           (date-str (format-time-string "%Y-%m-%d-%H%M%S-"))

           ;; Sanitize buffer name (replace non-alphanumeric/hyphen characters with hyphens)
           (clean-name (replace-regexp-in-string "[^[:alnum:]-]" "-"
                                                 ;; Remove leading and trailing '*' from buffer names like *Gemini*
                                                 (string-trim (buffer-name) "*" "*")))
           ;; Collapse multiple consecutive hyphens into a single one
           (clean-name (replace-regexp-in-string "-+" "-" clean-name))
           ;; Remove leading and trailing hyphens
           (clean-name (string-trim clean-name "-"))
           ;; Determine the extension based on the buffer mode
           (ext (if (derived-mode-p 'org-mode) ".org" ".md"))
           (file-path (concat base-dir date-str clean-name ext)))

      ;; Create the archive directory if it doesn't exist
      (unless (file-directory-p base-dir)
        (make-directory base-dir t))

      ;; Save the buffer state (model settings, etc.)
      ;; This allows settings to be restored when reopening the saved file
      (gptel--save-state)

      ;; Save the buffer content to the file
      (write-region (point-min) (point-max) file-path)
      (message "Saved session to: %s" file-path)

      ;; Reset the buffer
      (erase-buffer)
      ;; Insert the initial prompt prefix (e.g., ###)
      (insert (gptel-prompt-prefix-string))))

  (defun my-gptel-ask-and-annotate-line (question)
    "Ask GPTel about the current line and annotate it with the response.
The entire buffer content is sent as context."
    (interactive "sQuestion about this line: ")
    (require 'annotate)
    (let* ((buf (current-buffer))
           (start (line-beginning-position))
           (end (line-end-position))
           (line-content (buffer-substring-no-properties start end))
           (buffer-content (buffer-substring-no-properties (point-min) (point-max)))
           (prompt (format "Context (File Content):\n```\n%s\n```\n\nTarget Line:\n```\n%s\n```\n\nQuestion: %s\n\nPlease answer in Japanese. Keep the answer concise enough to fit in a margin annotation."
                           buffer-content line-content question)))
      (message "Asking GPTel...")
      (gptel-request
       prompt
       :system "You are an intelligent coding assistant. Answer in Japanese. Be concise."
       :callback (lambda (response info)
                   (if (and response (stringp response))
                       (with-current-buffer buf
                         ;; Ensure annotate-mode is active
                         (unless (bound-and-true-p annotate-mode)
                           (annotate-mode 1))
                         ;; annotate-create-annotation arguments: start end annotation-text annotated-text
                         (annotate-create-annotation start end response line-content)
                         (message "Annotation added."))
                     (message "GPTel request failed: %s" (plist-get info :status)))))))

  (defun my-gptel-ask-about-code (question)
    "Open gptel buffer with a prompt referencing the current line.
The source buffer is added as gptel context for full file awareness."
    (interactive "sQuestion about this line: ")
    (require 'gptel-context)
    (let* ((source-buffer (current-buffer))
           (file-name (or (buffer-file-name) (buffer-name)))
           (line-number (line-number-at-pos))
           (line-content (string-trim
                          (buffer-substring-no-properties
                           (line-beginning-position) (line-end-position))))
           (file-label (format "%s:%d"
                               (file-name-nondirectory file-name)
                               line-number))
           (gptel-buffer (or (my-gptel-get-buffer)
                             (gptel (gptel--buffer-name)))))
      ;; Add file as context without overlay to avoid changing buffer colors
      (if (buffer-file-name source-buffer)
          (gptel-context--add-text-file (buffer-file-name source-buffer))
        (gptel-context--add-buffer source-buffer))
      (with-current-buffer gptel-buffer
        (goto-char (point-max))
        ;; Ensure we start on a fresh line
        (unless (bolp) (insert "\n"))
        (insert (gptel-prompt-prefix-string))
        (insert (format "`%s`\n" file-label))
        (insert (format "```%s\n%s\n```\n"
                        (replace-regexp-in-string
                         "-mode\\'" ""
                         (symbol-name
                          (buffer-local-value 'major-mode source-buffer)))
                        line-content))
        (insert question "\n"))
      ;; Show gptel buffer in a side window
      (display-buffer gptel-buffer
                      '(display-buffer-in-side-window
                        (side . right)
                        (window-width . 0.4)))))

  )

;; agent-shell: chat with ACP-compatible coding agents (Claude, Gemini)
;; in a comint-based shell buffer. Talks to agents over the Agent Client
;; Protocol via acp.el, so each agent needs its own CLI on PATH. Install
;; the agent executables before use:
;;   npm install -g @agentclientprotocol/claude-agent-acp  ; for Claude
;;   npm install -g @google/gemini-cli                     ; for Gemini
(use-package agent-shell
  :ensure t
  :bind (("C-c q" . agent-shell-anthropic-start-claude-code)
         ("C-c C-q" . agent-shell-google-start-gemini))
  :custom
  ;; Reuse the local Claude/Gemini CLI logins instead of storing API keys.
  (agent-shell-anthropic-authentication
   (agent-shell-anthropic-make-authentication :login t))
  (agent-shell-google-authentication
   (agent-shell-google-make-authentication :login t)))

(provide 'init-ai)
;;; init-ai.el ends here
