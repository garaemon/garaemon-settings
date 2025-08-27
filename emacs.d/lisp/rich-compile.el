(defvar rich-compile-plugins '()
  "List of registered rich-compile plugins.
Each plugin is a plist with keys:
  :name - plugin name string
  :description - plugin description string
  :available-p - function to check if plugin is available for current context
  :commands - list of command plists with keys:
    :name - command name string
    :description - command description string
    :action - function to execute the command
    :interactive - whether the command supports interactive editing")

(defun rich-compile-register-plugin (name description available-p commands)
  "Register a new plugin for rich-compile.
NAME: plugin name string
DESCRIPTION: plugin description string
AVAILABLE-P: function that returns t if plugin is available for current context
COMMANDS: list of command plists with keys :name, :description, :action, :interactive"
  (let ((plugin (list :name name
                      :description description
                      :available-p available-p
                      :commands commands)))
    (setq rich-compile-plugins
          (cons plugin
                (cl-remove name rich-compile-plugins :key (lambda (p) (plist-get p :name)) :test #'string-equal)))))

(defun rich-compile--get-available-plugins ()
  "Get list of available plugins for current context."
  (cl-remove-if-not (lambda (plugin)
                      (let ((available-p (plist-get plugin :available-p)))
                        (and available-p (funcall available-p))))
                    rich-compile-plugins))

(defun rich-compile--find-project-root ()
  "Locate the project root for the current buffer.
   Prioritizes `project.el`, then searches for .git or .venv."
  (let ((file-path (buffer-file-name))
        (project-root nil))
    (when file-path
      ;; 1. Prioritize `project.el` (built-in Emacs 27+)
      (when (fboundp 'project-current)
        (let ((proj (project-current)))
          (when proj
            (setq project-root (project-root proj)))))

      ;; 2. Fallback if `project.el` is not used or no project found
      ;; Search for .git, .venv, package.xml, or package.json in parent directories
      (unless project-root
        (let ((dir (file-name-directory file-path)))
          (while (and dir (not (string= dir "/")))
            (when (or (file-directory-p (expand-file-name ".git" dir))
                      (file-directory-p (expand-file-name ".venv" dir))
                      (file-exists-p (expand-file-name "package.xml" dir))
                      (file-exists-p (expand-file-name "package.json" dir)))
              (setq project-root dir)
              (cl-return)) ;; Exit loop
            (setq dir (file-name-directory (directory-file-name dir)))))))

    ;; If no project root found, assume current directory
    (unless project-root
      (message "Warning: Could not determine project root. Assuming current directory.")
      (setq project-root default-directory))
    project-root))

(defun rich-compile--get-venv-activate-prefix (project-root)
  "Returns the virtual environment activation command prefix if .venv exists in project-root."
  (let ((activate-prefix "")
        (venv-activate-script (expand-file-name ".venv/bin/activate" project-root)))
    (when (and project-root (file-exists-p venv-activate-script))
      (setq activate-prefix
            (format "source %s && " (shell-quote-argument venv-activate-script))))
    activate-prefix))

(defun rich-compile--run-command-in-compilation-buffer (command &optional buffer-name)
  "Executes a command in a new *compilation* buffer.
   Benefits from compilation-mode features like error parsing."
  (interactive)
  (unless buffer-name (setq buffer-name "*Rich Compile*"))
  (message "Running: %s" command)
  (compilation-start command t #'(lambda (mode-name) buffer-name)))

(defun rich-compile-run-command-interactively (initial-command &optional buffer-name)
  "Run a command interactively, allowing the user to edit it before execution."
  (interactive "sInitial command: ")
  (let ((edited-command (read-string "Edit command: " initial-command)))
    (rich-compile--run-command-in-compilation-buffer edited-command buffer-name)))

(defun rich-compile-run-pytest-on-current-file ()
  "Runs pytest on the current Python test file."
  (interactive)
  (unless (derived-mode-p 'python-mode)
    (message "Not in Python mode.")
    (error "Not in Python mode"))
  (unless (buffer-file-name)
    (message "Buffer not associated with a file.")
    (error "Buffer not associated with a file"))

  (let* ((file-path (buffer-file-name))
         (file-name (file-name-nondirectory file-path))
         (project-root (rich-compile--find-project-root))
         (activate-prefix (rich-compile--get-venv-activate-prefix project-root))
         (pytest-cmd "pytest"))

    (unless (string-match-p "\\`test_.*\\.py\\'" file-name)
      (message "Current file '%s' does not match 'test_*.py' pattern." file-name)
      (error "Not a pytest file"))

    (rich-compile--run-command-in-compilation-buffer
     (concat activate-prefix pytest-cmd " " (shell-quote-argument file-path))
     (format "*Pytest: %s*" file-name))))

(defun rich-compile-run-pytest-on-current-file-interactive ()
  "Runs pytest on the current Python test file with interactive command editing."
  (interactive)
  (unless (derived-mode-p 'python-mode)
    (message "Not in Python mode.")
    (error "Not in Python mode"))
  (unless (buffer-file-name)
    (message "Buffer not associated with a file.")
    (error "Buffer not associated with a file"))

  (let* ((file-path (buffer-file-name))
         (file-name (file-name-nondirectory file-path))
         (project-root (rich-compile--find-project-root))
         (activate-prefix (rich-compile--get-venv-activate-prefix project-root))
         (pytest-cmd "pytest")
         (initial-command (concat activate-prefix pytest-cmd " " (shell-quote-argument file-path))))

    (unless (string-match-p "\\`test_.*\\.py\\'" file-name)
      (message "Current file '%s' does not match 'test_*.py' pattern." file-name)
      (error "Not a pytest file"))

    (rich-compile-run-command-interactively
     initial-command
     (format "*Pytest: %s*" file-name))))

(defun rich-compile-run-python-on-current-file ()
  "Runs the current Python file with the Python interpreter."
  (interactive)
  (unless (derived-mode-p 'python-mode)
    (message "Not in Python mode.")
    (error "Not in Python mode"))
  (unless (buffer-file-name)
    (message "Buffer not associated with a file.")
    (error "Buffer not associated with a file"))
  (unless (string-equal (file-name-extension (buffer-file-name)) "py")
    (message "Current file is not a .py file.")
    (error "Not a .py file"))

  (let* ((file-path (buffer-file-name))
         (file-name (file-name-nondirectory file-path))
         (project-root (rich-compile--find-project-root))
         (activate-prefix (rich-compile--get-venv-activate-prefix project-root))
         (python-interpreter "python3"))

    (rich-compile--run-command-in-compilation-buffer
     (concat activate-prefix python-interpreter " " (shell-quote-argument file-path))
     (format "*Python Run: %s*" file-name))))

(defun rich-compile-run-python-on-current-file-interactive ()
  "Runs the current Python file with the Python interpreter with interactive command editing."
  (interactive)
  (unless (derived-mode-p 'python-mode)
    (message "Not in Python mode.")
    (error "Not in Python mode"))
  (unless (buffer-file-name)
    (message "Buffer not associated with a file.")
    (error "Buffer not associated with a file"))
  (unless (string-equal (file-name-extension (buffer-file-name)) "py")
    (message "Current file is not a .py file.")
    (error "Not a .py file"))

  (let* ((file-path (buffer-file-name))
         (file-name (file-name-nondirectory file-path))
         (project-root (rich-compile--find-project-root))
         (activate-prefix (rich-compile--get-venv-activate-prefix project-root))
         (python-interpreter "python3")
         (initial-command (concat activate-prefix python-interpreter " " (shell-quote-argument file-path))))

    (rich-compile-run-command-interactively
     initial-command
     (format "*Python Run: %s*" file-name))))

(defun rich-compile-run-go-on-current-file ()
  "Runs the current Go file with the Go interpreter."
  (interactive)
  (unless (derived-mode-p 'go-mode)
    (message "Not in Go mode.")
    (error "Not in Go mode"))
  (unless (buffer-file-name)
    (message "Buffer not associated with a file.")
    (error "Buffer not associated with a file"))
  (unless (string-equal (file-name-extension (buffer-file-name)) "go")
    (message "Current file is not a .go file.")
    (error "Not a .go file"))

  (let* ((file-path (buffer-file-name))
         (file-name (file-name-nondirectory file-path))
         (go-interpreter "go"))

    (rich-compile--run-command-in-compilation-buffer
     (concat go-interpreter " run " (shell-quote-argument file-path))
     (format "*Go Run: %s*" file-name))))

(defun rich-compile-run-go-on-current-file-interactive ()
  "Runs the current Go file with the Go interpreter with interactive command editing."
  (interactive)
  (unless (derived-mode-p 'go-mode)
    (message "Not in Go mode.")
    (error "Not in Go mode"))
  (unless (buffer-file-name)
    (message "Buffer not associated with a file.")
    (error "Buffer not associated with a file"))
  (unless (string-equal (file-name-extension (buffer-file-name)) "go")
    (message "Current file is not a .go file.")
    (error "Not a .go file"))

  (let* ((file-path (buffer-file-name))
         (file-name (file-name-nondirectory file-path))
         (go-interpreter "go")
         (initial-command (concat go-interpreter " run " (shell-quote-argument file-path))))

    (rich-compile-run-command-interactively
     initial-command
     (format "*Go Run: %s*" file-name))))

(defun rich-compile--is-ros-project (project-root)
  "Check if the project root contains package.xml (ROS package)."
  (file-exists-p (expand-file-name "package.xml" project-root)))

(defun rich-compile--has-vscode-tasks (project-root)
  "Check if the project root contains .vscode/tasks.json (VS Code tasks)."
  (file-exists-p (expand-file-name ".vscode/tasks.json" project-root)))

(defun rich-compile--has-package-json (project-root)
  "Check if the project root contains package.json (npm/yarn package)."
  (file-exists-p (expand-file-name "package.json" project-root)))

(defun rich-compile-catkin-build-this ()
  "Run catkin build --this for the current ROS package."
  (interactive)
  (let ((project-root (rich-compile--find-project-root)))
    (unless (rich-compile--is-ros-project project-root)
      (message "Not in a ROS package (no package.xml found).")
      (error "Not in a ROS package"))
    (let ((default-directory project-root))
      (rich-compile--run-command-in-compilation-buffer
       "catkin build --this"
       "*Catkin Build This*"))))

(defun rich-compile-catkin-build-this-interactive ()
  "Run catkin build --this for the current ROS package with interactive command editing."
  (interactive)
  (let ((project-root (rich-compile--find-project-root)))
    (unless (rich-compile--is-ros-project project-root)
      (message "Not in a ROS package (no package.xml found).")
      (error "Not in a ROS package"))
    (let ((default-directory project-root))
      (rich-compile-run-command-interactively
       "catkin build --this"
       "*Catkin Build This*"))))

(defun rich-compile-catkin-build-this-no-deps ()
  "Run catkin build --this --no-deps for the current ROS package."
  (interactive)
  (let ((project-root (rich-compile--find-project-root)))
    (unless (rich-compile--is-ros-project project-root)
      (message "Not in a ROS package (no package.xml found).")
      (error "Not in a ROS package"))
    (let ((default-directory project-root))
      (rich-compile-run-command-interactively
       "catkin build --this --no-deps"
       "*Catkin Build This No Deps*"))))

(defun rich-compile-catkin-run-tests-this-no-deps ()
  "Run catkin run_tests --this --no-deps for the current ROS package."
  (interactive)
  (let ((project-root (rich-compile--find-project-root)))
    (unless (rich-compile--is-ros-project project-root)
      (message "Not in a ROS package (no package.xml found).")
      (error "Not in a ROS package"))
    (let ((default-directory project-root))
      (rich-compile-run-command-interactively
       "catkin run_tests --this --no-deps"
       "*Catkin Run Tests This No Deps*"))))

(defun rich-compile--get-vscode-tasks (project-root)
  "Get list of available VS Code tasks from tasks.json."
  (let ((tasks-json-path (expand-file-name ".vscode/tasks.json" project-root))
        (default-directory project-root))
    (when (file-exists-p tasks-json-path)
      (let ((output (shell-command-to-string
                     (format "tasks-json-cli list -c %s -q" (shell-quote-argument tasks-json-path)))))
        (when (and output (not (string-empty-p (string-trim output))))
          (split-string (string-trim output) "\n" t))))))

(defun rich-compile--get-npm-scripts (project-root)
  "Get list of available npm scripts from package.json."
  (let ((package-json-path (expand-file-name "package.json" project-root)))
    (when (file-exists-p package-json-path)
      (with-temp-buffer
        (insert-file-contents package-json-path)
        (goto-char (point-min))
        (let ((json-data (ignore-errors (json-read))))
          (when json-data
            (let ((scripts (cdr (assoc 'scripts json-data))))
              (when scripts
                (mapcar (lambda (script) (symbol-name (car script))) scripts)))))))))

(defun rich-compile-run-npm-script (script-name)
  "Run an npm script from package.json."
  (interactive)
  (let* ((project-root (rich-compile--find-project-root))
         (default-directory project-root)
         (command (format "npm run %s" (shell-quote-argument script-name))))
    (rich-compile--run-command-in-compilation-buffer
     command
     (format "*npm run %s*" script-name))))

(defun rich-compile-run-npm-script-interactive (script-name)
  "Run an npm script from package.json with interactive command editing."
  (interactive)
  (let* ((project-root (rich-compile--find-project-root))
         (default-directory project-root)
         (initial-command (format "npm run %s" (shell-quote-argument script-name))))
    (rich-compile-run-command-interactively
     initial-command
     (format "*npm run %s*" script-name))))

(defun rich-compile-run-vscode-task (task-name)
  "Run a VS Code task using tasks-json-cli."
  (interactive)
  (let* ((project-root (rich-compile--find-project-root))
         (tasks-json-path (expand-file-name ".vscode/tasks.json" project-root))
         (default-directory project-root)
         (current-file (when (buffer-file-name) (buffer-file-name)))
         (command (format "tasks-json-cli run %s -c %s%s"
                         (shell-quote-argument task-name)
                         (shell-quote-argument tasks-json-path)
                         (if current-file
                             (format " --file %s" (shell-quote-argument current-file))
                           ""))))
    (rich-compile--run-command-in-compilation-buffer
     command
     (format "*VS Code Task: %s*" task-name))))

(defun rich-compile-run-vscode-task-interactive (task-name)
  "Run a VS Code task using tasks-json-cli with interactive command editing."
  (interactive)
  (let* ((project-root (rich-compile--find-project-root))
         (tasks-json-path (expand-file-name ".vscode/tasks.json" project-root))
         (default-directory project-root)
         (current-file (when (buffer-file-name) (buffer-file-name)))
         (initial-command (format "tasks-json-cli run %s -c %s%s"
                                 (shell-quote-argument task-name)
                                 (shell-quote-argument tasks-json-path)
                                 (if current-file
                                     (format " --file %s" (shell-quote-argument current-file))
                                   ""))))
    (rich-compile-run-command-interactively
     initial-command
     (format "*VS Code Task: %s*" task-name))))

(defun rich-compile-run-menu ()
  "Menu to select and run a command for the current file."
  (interactive)

  (let* ((project-root (rich-compile--find-project-root))
         (is-ros-project (rich-compile--is-ros-project project-root))
         (has-vscode-tasks (rich-compile--has-vscode-tasks project-root))
         (has-package-json (rich-compile--has-package-json project-root))
         (vscode-tasks (when has-vscode-tasks (rich-compile--get-vscode-tasks project-root)))
         (npm-scripts (when has-package-json (rich-compile--get-npm-scripts project-root)))
         (mode-choices (cond
                        ((derived-mode-p 'python-mode)
                         '(("Run Pytest on current file" . rich-compile-run-pytest-on-current-file-interactive)
                           ("Run current file with Python" . rich-compile-run-python-on-current-file-interactive)))
                        ((derived-mode-p 'go-mode)
                         '(("Run current file with Go" . rich-compile-run-go-on-current-file)))
                        (t
                         '())))
         (ros-choices (when is-ros-project
                        '(("Catkin build --this" . rich-compile-catkin-build-this-interactive)
                          ("Catkin build --this --no-deps" . rich-compile-catkin-build-this-no-deps)
                          ("Catkin run_tests --this --no-deps" . rich-compile-catkin-run-tests-this-no-deps))))
         (vscode-choices (when vscode-tasks
                           (apply 'append
                                  (mapcar (lambda (task)
                                            (list (cons (format "VS Code Task: %s" task)
                                                        `(lambda () (rich-compile-run-vscode-task-interactive ,task)))))
                                          vscode-tasks))))
         (npm-choices (when npm-scripts
                        (apply 'append
                               (mapcar (lambda (script)
                                         (list (cons (format "npm run %s" script)
                                                     `(lambda () (rich-compile-run-npm-script-interactive ,script)))))
                                       npm-scripts))))
         (plugin-choices (let ((available-plugins (rich-compile--get-available-plugins)))
                           (apply 'append
                                  (mapcar (lambda (plugin)
                                            (mapcar (lambda (command)
                                                      (cons (format "%s: %s" (plist-get plugin :name) (plist-get command :name))
                                                            (plist-get command :action)))
                                                    (plist-get plugin :commands)))
                                          available-plugins))))
         (generic-choices '(("Run custom command" . (lambda () (call-interactively 'rich-compile-run-command-interactively)))))
         (choices (append mode-choices ros-choices vscode-choices npm-choices plugin-choices generic-choices))
         (prompt (let ((has-npm (and has-package-json npm-scripts)))
                   (cond
                    ((and (derived-mode-p 'python-mode) is-ros-project has-vscode-tasks has-npm)
                     "Choose Python/ROS/VS Code/npm run command: ")
                    ((and (derived-mode-p 'go-mode) is-ros-project has-vscode-tasks has-npm)
                     "Choose Go/ROS/VS Code/npm run command: ")
                    ((and (derived-mode-p 'python-mode) has-vscode-tasks has-npm)
                     "Choose Python/VS Code/npm run command: ")
                    ((and (derived-mode-p 'go-mode) has-vscode-tasks has-npm)
                     "Choose Go/VS Code/npm run command: ")
                    ((and is-ros-project has-vscode-tasks has-npm)
                     "Choose ROS/VS Code/npm run command: ")
                    ((and (derived-mode-p 'python-mode) is-ros-project has-vscode-tasks)
                     "Choose Python/ROS/VS Code run command: ")
                    ((and (derived-mode-p 'go-mode) is-ros-project has-vscode-tasks)
                     "Choose Go/ROS/VS Code run command: ")
                    ((and (derived-mode-p 'python-mode) has-vscode-tasks)
                     "Choose Python/VS Code run command: ")
                    ((and (derived-mode-p 'go-mode) has-vscode-tasks)
                     "Choose Go/VS Code run command: ")
                    ((and is-ros-project has-vscode-tasks)
                     "Choose ROS/VS Code run command: ")
                    ((and (derived-mode-p 'python-mode) has-npm)
                     "Choose Python/npm run command: ")
                    ((and (derived-mode-p 'go-mode) has-npm)
                     "Choose Go/npm run command: ")
                    ((and is-ros-project has-npm)
                     "Choose ROS/npm run command: ")
                    ((derived-mode-p 'python-mode) "Choose Python run command: ")
                    ((derived-mode-p 'go-mode) "Choose Go run command: ")
                    (is-ros-project "Choose ROS run command: ")
                    (has-vscode-tasks "Choose VS Code run command: ")
                    (has-npm "Choose npm run command: ")
                    ((rich-compile--get-available-plugins) "Choose command: ")
                    (t "Choose run command: "))))
         (choice (when choices (completing-read prompt choices nil t))))
    (cond
     ((null choices)
      (message "No run commands available for this file type."))
     (choice
      (funcall (cdr (assoc choice choices)))))))

;; Default plugins

;; Python plugin
(rich-compile-register-plugin
 "Python"
 "Python development commands"
 (lambda () (derived-mode-p 'python-mode))
 (list
  (list :name "Run current file"
        :description "Run current Python file with interpreter"
        :action (lambda () (call-interactively #'rich-compile-run-python-on-current-file-interactive))
        :interactive t)
  (list :name "Run pytest on current file"
        :description "Run pytest on current test file"
        :action (lambda () (call-interactively #'rich-compile-run-pytest-on-current-file-interactive))
        :interactive t)))

;; Go plugin
(rich-compile-register-plugin
 "Go"
 "Go development commands"
 (lambda () (derived-mode-p 'go-mode))
 (list
  (list :name "Run current file"
        :description "Run current Go file"
        :action (lambda () (call-interactively #'rich-compile-run-go-on-current-file))
        :interactive nil)))

;; ROS plugin
(rich-compile-register-plugin
 "ROS"
 "ROS development commands"
 (lambda () (rich-compile--is-ros-project (rich-compile--find-project-root)))
 (list
  (list :name "Catkin build --this"
        :description "Build current ROS package"
        :action (lambda () (call-interactively #'rich-compile-catkin-build-this-interactive))
        :interactive t)
  (list :name "Catkin build --this --no-deps"
        :description "Build current ROS package without dependencies"
        :action (lambda () (call-interactively #'rich-compile-catkin-build-this-no-deps))
        :interactive t)
  (list :name "Catkin run_tests --this --no-deps"
        :description "Run tests for current ROS package"
        :action (lambda () (call-interactively #'rich-compile-catkin-run-tests-this-no-deps))
        :interactive t)))

(provide 'rich-compile)
