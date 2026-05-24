# emacs.d [![Build Status](https://github.com/garaemon/emacs.d/actions/workflows/test.yml/badge.svg)](https://github.com/garaemon/emacs.d/actions?query=workflow%3Alint)

my private emacs setting

## Configuration Structure

This configuration follows a modular structure for better organization and maintainability.

### Initialization Files

- **early-init.el**: Early initialization file loaded before package system and GUI creation
  - GC optimization for startup performance
  - Disables GUI elements to prevent flashing
  - Native compilation settings
  - Runs before `init.el`

- **init.el**: Main configuration entry point
  - Sets up load paths
  - Initializes package system (ELPA, MELPA)
  - Loads modular configuration files from `lisp/`
  - Resets GC threshold after startup

### Modular Configuration (lisp/)

Configuration is split into focused modules in the `lisp/` directory:

- **init-basic.el**: Basic Emacs settings and behaviors
- **init-ui.el**: UI and appearance configuration
- **init-editor.el**: Editor behaviors and key bindings
- **init-prog.el**: Programming mode configurations
- **init-org.el**: Org-mode specific settings
- **init-utils.el**: Utility functions and helper tools

Each module is loaded via `(require 'init-*)` in `init.el`.

## Scripts

Helper scripts kept under `scripts/`. They are not loaded automatically by Emacs; run them manually as described below.

- **profile-org-agenda.el**: Batch-mode profiler for the same code path that `org-agenda-quick` triggers. Measures cold (no buffers preloaded) and warm (buffers reused) wall-clock time, then writes expanded CPU profile reports for both runs.

  ```sh
  /Applications/Emacs.app/Contents/MacOS/Emacs --batch \
      -l init.el \
      -l scripts/profile-org-agenda.el
  ```

  Outputs:
  - `/tmp/org-agenda-profile-bench.txt` — per-phase wall-clock timings
  - `/tmp/org-agenda-profile-cold.txt` — CPU profile, cold run
  - `/tmp/org-agenda-profile-warm.txt` — CPU profile, warm run

  Use this to spot which hooks or globalized minor modes dominate cold agenda time when adding new Org-related packages.

- **latest_directory_timestamp.py**: Print the most recent modification timestamp under a directory tree.

  ```sh
  python scripts/latest_directory_timestamp.py <root-directory>
  ```
