;;; my-ollama.el --- Shared settings for the local Ollama server -*- lexical-binding: t; -*-

;;; Commentary:
;; Three parts of this configuration talk to the same local Ollama server:
;; minuet completes code inline, gptel chats, and gptel-magit writes commit
;; messages.  Each one carried its own copy of the host, the model name and the
;; gptel backend definition, so switching a model meant editing several files
;; and keeping the copies in step.  This module owns those names instead.

;;; Code:

(defgroup my-ollama nil
  "Local Ollama server shared by minuet, gptel and gptel-magit."
  :group 'tools)

(defcustom my-ollama-host "localhost:11434"
  "Host and port of the Ollama server, without a URL scheme."
  :type 'string
  :group 'my-ollama)

(defcustom my-ollama-completion-model "qwen2.5-coder:3b"
  "Model that minuet asks for inline code completions.
The job is a fill-in-the-middle request capped at 56 tokens, which a 3B model
answers well inside the 10 second `minuet-request-timeout\='.  Its predecessor
here, deepseek-coder-v2:lite, spent 9 GB of disk and 16B parameters on the same
request."
  :type 'string
  :group 'my-ollama)

(defcustom my-ollama-chat-model "gemma3:4b"
  "Model that gptel and gptel-magit ask for prose."
  :type 'string
  :group 'my-ollama)

(defun my-ollama-completions-url ()
  "Return the URL of the OpenAI-compatible completion endpoint."
  (format "http://%s/v1/completions" my-ollama-host))

(declare-function gptel-make-ollama "gptel")

(defun my-ollama-make-gptel-backend ()
  "Register the local Ollama server as a gptel backend and return it.
Calling this again replaces the registration, which keeps the backend in step
with `my-ollama-host' and `my-ollama-chat-model'."
  (require 'gptel)
  (gptel-make-ollama (format "Ollama (%s)" my-ollama-chat-model)
    :host my-ollama-host
    :stream t
    :models (list (intern my-ollama-chat-model))))

(provide 'my-ollama)
;;; my-ollama.el ends here
