;;; my-ollama.el --- Shared settings for the local Ollama server -*- lexical-binding: t; -*-

;;; Commentary:
;; Three parts of this configuration talk to the same local Ollama server:
;; minuet completes code inline, gptel chats, and gptel-magit writes commit
;; messages.  Each one carried its own copy of the host, the model name and the
;; gptel backend definition, so switching a model meant editing several files
;; and keeping the copies in step.  This module owns those names instead.

;;; Code:

(require 'url)

(defvar url-http-end-of-headers)

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

(defcustom my-ollama-required-models
  (list my-ollama-completion-model my-ollama-chat-model)
  "Models that `my-ollama-ensure-models' downloads when the server lacks them."
  :type '(repeat string)
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

(defun my-ollama-tags-url ()
  "Return the URL of the endpoint that lists the models the server holds."
  (format "http://%s/api/tags" my-ollama-host))

(defun my-ollama-parse-installed-models (payload)
  "Return the model names in PAYLOAD, the JSON body of an /api/tags response.
Return nil when PAYLOAD names no model or does not parse, so that a reply from
something other than Ollama reads as an empty server rather than an error."
  (let* ((parsed (ignore-errors
                   (json-parse-string payload :object-type 'alist :array-type 'list)))
         (entries (and (listp parsed) (alist-get 'models parsed))))
    (delq nil (mapcar (lambda (entry) (and (consp entry) (alist-get 'name entry)))
                      (and (listp entries) entries)))))

(defun my-ollama-normalize-model-name (model)
  "Return MODEL with its tag spelled out.
Ollama resolves an untagged name to the `latest' tag, and /api/tags always
answers with a tag, so the two spellings have to meet somewhere."
  (if (string-search ":" model) model (concat model ":latest")))

(defun my-ollama-missing-models (required installed)
  "Return the models of REQUIRED that INSTALLED does not cover.
The result keeps the order of REQUIRED and names each model once."
  (let ((present (mapcar #'my-ollama-normalize-model-name installed))
        (missing (list)))
    (dolist (model required)
      (let ((name (my-ollama-normalize-model-name model)))
        (unless (member name present)
          ;; Recording the name as present also keeps a list that repeats a
          ;; model from starting two downloads of it.
          (push name present)
          (push model missing))))
    (nreverse missing)))

(defun my-ollama-fetch-installed-models (on-success)
  "Ask the Ollama server for its models and call ON-SUCCESS with their names.
Stay silent when the server does not answer.  A machine that never starts
Ollama is a supported state, not a failure worth a message at every startup."
  (url-retrieve
   (my-ollama-tags-url)
   (lambda (status)
     (let ((payload (and (not (plist-get status :error))
                         url-http-end-of-headers
                         (buffer-substring-no-properties url-http-end-of-headers
                                                         (point-max)))))
       (kill-buffer)
       (when payload
         (funcall on-success (my-ollama-parse-installed-models payload)))))
   nil t t))

(defconst my-ollama-pull-buffer-name "*ollama-pull*"
  "Buffer that collects the output of the downloads.")

(defun my-ollama-pull-model (model)
  "Download MODEL in the background through the `ollama' command.
Report the start and the outcome in the echo area, and leave the progress in
`my-ollama-pull-buffer-name': a download of several gigabytes would otherwise
overwrite every other message for minutes.

The download runs the command rather than the HTTP /api/pull endpoint, which
streams its progress as newline-delimited JSON that `url-retrieve' would hand
over only once the last byte arrived."
  (if (not (executable-find "ollama"))
      (message "my-ollama: cannot download %s, no ollama command on PATH" model)
    (message "my-ollama: downloading %s, progress in %s"
             model my-ollama-pull-buffer-name)
    (make-process
     :name (format "ollama-pull-%s" model)
     :buffer (get-buffer-create my-ollama-pull-buffer-name)
     :command (list "ollama" "pull" model)
     :noquery t
     :sentinel
     (lambda (process _event)
       (unless (process-live-p process)
         (if (zerop (process-exit-status process))
             (message "my-ollama: downloaded %s" model)
           (message "my-ollama: failed to download %s, see %s"
                    model my-ollama-pull-buffer-name)))))))

(defvar my-ollama-fetch-installed-models-function
  #'my-ollama-fetch-installed-models
  "Function that lists the models the server holds.
It receives one callback, and calls it with the list of model names when, and
only when, the server answers.  Tests replace this to drop the HTTP request.")

(defvar my-ollama-pull-model-function #'my-ollama-pull-model
  "Function that downloads the single model name it receives.
Tests replace this to drop the download.")

(defun my-ollama-ensure-models (&optional models)
  "Download the models of MODELS that the local Ollama server lacks.
MODELS defaults to `my-ollama-required-models'.  Ollama rejects a request for a
model it does not hold, and minuet reports the rejection as nothing more than a
completion that never appears, so a fresh machine needs the download before the
AI features do anything.  The check is one asynchronous request and downloads
nothing when the server already holds every model."
  (interactive)
  (let ((wanted (or models my-ollama-required-models)))
    (when wanted
      (funcall my-ollama-fetch-installed-models-function
               (lambda (installed)
                 (dolist (model (my-ollama-missing-models wanted installed))
                   (funcall my-ollama-pull-model-function model)))))))

(provide 'my-ollama)
;;; my-ollama.el ends here
