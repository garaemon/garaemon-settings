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
      ;; Search for .git, .venv, or package.xml in parent directories
      (unless project-root
        (let ((dir (file-name-directory file-path)))
          (while (and dir (not (string= dir "/")))
            (when (or (file-directory-p (expand-file-name ".git" dir))
                      (file-directory-p (expand-file-name ".venv" dir))
                      (file-exists-p (expand-file-name "package.xml" dir)))
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

(defun rich-compile--is-ros-project (project-root)
  "Check if the project root contains package.xml (ROS package)."
  (file-exists-p (expand-file-name "package.xml" project-root)))

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

(defun rich-compile-catkin-build-this-no-deps ()
  "Run catkin build --this --no-deps for the current ROS package."
  (interactive)
  (let ((project-root (rich-compile--find-project-root)))
    (unless (rich-compile--is-ros-project project-root)
      (message "Not in a ROS package (no package.xml found).")
      (error "Not in a ROS package"))
    (let ((default-directory project-root))
      (rich-compile--run-command-in-compilation-buffer
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
      (rich-compile--run-command-in-compilation-buffer
       "catkin run_tests --this --no-deps"
       "*Catkin Run Tests This No Deps*"))))

(defun rich-compile-run-menu ()
  "Menu to select and run a command for the current file."
  (interactive)

  (let* ((project-root (rich-compile--find-project-root))
         (is-ros-project (rich-compile--is-ros-project project-root))
         (mode-choices (cond
                        ((derived-mode-p 'python-mode)
                         '(("Run Pytest on current file" . rich-compile-run-pytest-on-current-file)
                           ("Run current file with Python" . rich-compile-run-python-on-current-file)))
                        ((derived-mode-p 'go-mode)
                         '(("Run current file with Go" . rich-compile-run-go-on-current-file)))
                        (t
                         '())))
         (ros-choices (when is-ros-project
                        '(("Catkin build --this" . rich-compile-catkin-build-this)
                          ("Catkin build --this --no-deps" . rich-compile-catkin-build-this-no-deps)
                          ("Catkin run_tests --this --no-deps" . rich-compile-catkin-run-tests-this-no-deps))))
         (choices (append mode-choices ros-choices))
         (prompt (cond
                  ((and (derived-mode-p 'python-mode) is-ros-project) "Choose Python/ROS run command: ")
                  ((and (derived-mode-p 'go-mode) is-ros-project) "Choose Go/ROS run command: ")
                  ((derived-mode-p 'python-mode) "Choose Python run command: ")
                  ((derived-mode-p 'go-mode) "Choose Go run command: ")
                  (is-ros-project "Choose ROS run command: ")
                  (t "No run commands available for this file type.")))
         (choice (when choices (completing-read prompt choices nil t))))
    (cond
     ((null choices)
      (message "No run commands available for this file type."))
     (choice
      (funcall (cdr (assoc choice choices)))))))

(provide 'rich-compile)
