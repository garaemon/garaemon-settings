# emacs.d [![Build Status](https://github.com/garaemon/garaemon-settings/actions/workflows/emacs-test.yml/badge.svg)](https://github.com/garaemon/garaemon-settings/actions/workflows/emacs-test.yml)

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

Standalone `my-*.el` modules under `lisp/` hold the logic that the init files
wire in. `my-keybind-stats.el` is described in
[Keybinding Stats](#keybinding-stats).

Each module is loaded via `(require 'init-*)` in `init.el`.

### Tests (tests/)

ERT tests for the standalone `my-*.el` modules. CI runs them on every push
that touches `emacs.d/`:

```sh
emacs -Q --batch --eval '(progn (require (quote package)) (package-initialize))' \
  -L lisp -L benchmarks -l ert \
  $(printf -- '-l %s ' tests/*.el) -f ert-run-tests-batch-and-exit
```

Pytest covers the Python scripts under `scripts/`:

```sh
python -m pytest tests/
```

### Benchmarks (benchmarks/)

Timings for the code paths whose cost grows with the size of a project, such
as the candidate collection behind `C-x b`. CI measures a pull request against
its base branch and posts the comparison as a comment, because an absolute
time from a shared runner says little on its own.

Run the scenarios by hand with:

```sh
emacs -Q --batch --eval '(progn (require (quote package)) (package-initialize))' \
  -L lisp -L benchmarks -l my-benchmarks \
  -f my-benchmark-run-batch results.json
```

Add a scenario with `my-benchmark-define`, in a file that `my-benchmarks.el`
requires. Give it an `:available-p` that returns nil when the code it measures
is absent, so that the branch a pull request starts from reports `n/a` instead
of failing.

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

## Markdown Preview

`C-c C-c g` in a Markdown buffer toggles `grip-mode`, a live preview in
GitHub's Markdown style. The preview refreshes on every edit, without saving.
It opens in an xwidget window when Emacs is built with xwidgets and in the
default browser otherwise.

The preview needs the `go-grip` command, which renders locally with GitHub's
stylesheet and needs no GitHub token. mise installs it from
`dotfiles/dot_config/mise/config.toml`:

```sh
mise install go:github.com/chrishrb/go-grip
```

## Local AI Models

`init-ai.el`, `init-git.el` and `lisp/my-ollama.el` drive one local Ollama
server. `my-ollama.el` owns the host and the model names, so a switch touches
one file:

- `my-ollama-completion-model` (`qwen2.5-coder:3b`) answers the inline
  completions that minuet requests. The request is a fill-in-the-middle
  completion capped at 56 tokens, which a 3B model returns well inside
  `minuet-request-timeout`.
- `my-ollama-chat-model` (`gemma3:4b`) answers gptel and writes the commit
  messages that gptel-magit proposes.

`my-ollama-fim-suffix` replaces the suffix that minuet sends whenever the
cursor sits at the end of a buffer. Ollama reads an empty suffix as a request
that carries no fill-in-the-middle work, renders the prompt through the chat
template of the model, and an instruct model answers with prose and a markdown
code fence instead of code.

Emacs downloads the missing models itself. `my-ollama-ensure-models` runs from
`emacs-startup-hook`, asks the server which models it holds, and runs
`ollama pull` for each one of `my-ollama-required-models` that is absent:

- The check is one asynchronous HTTP request and downloads nothing when the
  server already holds every model.
- A machine that never starts Ollama gets no message. The check simply finds
  no server and stops.
- The download reports its start and its outcome in the echo area, and leaves
  the progress in the `*ollama-pull*` buffer.

Run `M-x my-ollama-ensure-models` to repeat the check after changing a model
name.

## Keybinding Stats

`my-keybind-stats-mode` (enabled in `init-utils.el`) records every command,
the keys that ran it, and the major mode, so that the report can tell which
bindings earn their place. It skips typing and scrolling commands, keeps the
counts in memory, and appends them every 5 minutes as JSON lines to
`~/.emacs.d/keybind-stats/events-YYYY-MM.jsonl`:

```json
{"ts":"2026-09-11T10:05:00+0900","command":"forward-char","keys":"C-f","mode":"python-mode","mx":false,"bound":null,"count":12}
```

A command chosen through `M-x` is logged with keys `M-x`, and `bound` names the
key that would have run the command directly. The global keymap and the local
keymap of every major mode seen in a session go to
`~/.emacs.d/keybind-stats/bindings/<scope>.jsonl`, so that the report can list
bindings that never appear in the log.

Run `M-x my-keybind-stats-report` to flush the pending counts and open the
HTML report in the browser, or `C-u M-x my-keybind-stats-report` for the text
report in a buffer. The same report comes from the command line:

```sh
python scripts/keybind_stats.py                 # text report on stdout
python scripts/keybind_stats.py --days 30       # only the last 30 days
python scripts/keybind_stats.py --html /tmp/keybind-stats.html
```

The report has these sections:

- **Top commands**: the most used commands, with a breakdown per key.
- **Forgotten bindings**: commands run through `M-x` although a key exists.
- **Unbound favorites**: commands run through `M-x` at least twice with no key.
- **Long key sequences**: sequences of three chords or more, sorted by use.
- **Unused bindings**: bound keys that never appear in the log, per scope.
- **By major mode**, **By hour**, **By weekday**: where and when the commands
  run.

Run `M-x my-keybind-stats-flush` to write the pending counts before building a
report from the command line, and `M-x my-keybind-stats-mode` to pause the
recorder.

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

- **keybind_stats.py**: Report of the keybinding usage log. See
  [Keybinding Stats](#keybinding-stats).

- **latest_directory_timestamp.py**: Print the most recent modification timestamp under a directory tree.

  ```sh
  python scripts/latest_directory_timestamp.py <root-directory>
  ```
