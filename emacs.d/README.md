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
- **init-prog.el**: Shared development tooling (shell environment, snippets,
  formatters, terminals, project navigation)
- **init-lang.el**: Per-language major modes, indentation and tree-sitter setup
- **init-lsp.el**: lsp-mode, lsp-ui, lsp-sourcekit and flycheck
- **init-git.el**: magit, forge and the git review/commit helpers
- **init-ai.el**: minuet, gptel and agent-shell
- **init-org.el**: Org-mode specific settings
- **init-utils.el**: Utility functions and helper tools

Each module is loaded via `(require 'init-*)` in `init.el`.

## Fonts

`init-ui.el` picks the default face from `my-font-candidates`, taking the first
family that is actually installed. Monaco heads the list.

Monaco carries no Japanese glyphs, so Japanese falls back to another family
whose advance width has nothing to do with Monaco's. That breaks Org tables:
`org-table-align` pads cells by `string-width`, which counts a full-width
character as two columns, so at any ratio other than 1:2 the `|` separators of a
table containing Japanese drift apart row by row.

`my-tune-cjk-font` fixes this by pinning the Japanese family (Hiragino Sans and
friends, see `my-cjk-fallback-font-candidates`) to an explicit pixel size of
twice `frame-char-width` — a full-width glyph advances by its em box, so that
size makes it occupy exactly two columns. It runs at startup and again after
every `text-scale+` / `text-scale-` / `text-scale0`, since the pinned size is
absolute and cannot follow the ASCII font by itself.

The trade-off of keeping Monaco: Monaco advances only about 0.6 em, so twice
that is ~1.2 em and the Japanese font ends up visibly larger than the ASCII one.
Lines containing Japanese are therefore taller than pure-ASCII lines. Families
further down `my-font-candidates` (HackGen, UDEV Gothic, PlemolJP, Cica, …) ship
Japanese glyphs at exactly twice the half-width advance and need no tuning at
all, at the cost of not being Monaco; installing one and moving it to the front
of the list is all it takes to switch.

Run `M-x my-check-cjk-font-ratio` to check the result: it reports the measured
full-width/half-width ratio, which should be `2.000`.

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
