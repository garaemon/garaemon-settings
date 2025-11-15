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
