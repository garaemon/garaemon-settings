# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Personal Instructions

`dotfiles/dot_claude/CLAUDE.md` is the source that chezmoi installs to
`~/.claude/CLAUDE.md`. Importing it here applies the same instructions in
sessions that run without the dotfiles installed, such as Claude Code on the
web or a fresh container.

@dotfiles/dot_claude/CLAUDE.md

The imported file points to rule files under `~/.claude/rules/`. Their source
lives at `dotfiles/dot_claude/rules/`. Read the source copy when
`~/.claude/rules/` is missing.

## Repository Guidance

Read [README.md](README.md) first. It documents the layout of the four
components, the per-language lint setup, the install commands, and the
boundary against `private-server-config`. Each component carries its own
README or CLAUDE.md for the details.

## Lint

Run `./scripts/lint.sh` every time you change the code. Pass a target such as
`./scripts/lint.sh shell` to run one language only. CI runs the same script,
so a local run reports the same violations.
