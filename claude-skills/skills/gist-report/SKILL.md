---
name: gist-report
description: |
  Write a report as Markdown and upload it as a GitHub gist with the gh CLI,
  using the GitHub host of the repository's origin remote (github.com or
  GitHub Enterprise). Use this skill when the user wants a report, summary,
  investigation notes, or analysis written up and shared as a gist, or says
  things like "レポートをgistに上げて", "gistにして", "レポート書いてgist",
  "share this as a gist", "write a report and post it to a gist".
---

# Gist Report Skill

Write a report as a Markdown file, then upload it as a gist with
`scripts/post-gist.sh`. The script derives `GH_HOST` from the `origin`
remote URL, so never set or guess `GH_HOST` by hand.

## Workflow

1. Write the report to a Markdown file in the scratchpad directory (or
   another temporary location outside the repository). Name it after the
   topic, for example `weekly-latency-report.md`. The extension must be `.md`.
2. Run the script from inside the repository whose origin decides the host:

   ```bash
   scripts/post-gist.sh [--public] [--description TEXT] REPORT.md
   ```

   The path above is relative to this skill's directory. Use the absolute
   path of the script, for example `~/.claude/skills/gist-report/scripts/post-gist.sh`.
3. Show the gist URL that the script prints to the user.

## Rules

- Create a secret gist by default. Pass `--public` only when the user asks
  for a public gist. A secret gist is still reachable by anyone with the URL.
- Ask the user before uploading if the report contains credentials, internal
  hostnames, or other sensitive data.
- Do not call `gh gist create` directly. The script prevents a wrong host
  and an inherited `GH_HOST` from sending the report to the wrong server.
- Pass a short `--description` that names the report topic.
- Write the report in the language the user asked for. Follow the
  `technical-writing` skill for the prose.

## What the script does

- Reads the URL of the `origin` remote. It accepts `https://`, `ssh://`, and
  scp-like (`git@host:owner/repo`) forms.
- Exports `GH_HOST` for that host, replacing any inherited value.
- Runs `gh gist create` on the report and prints the gist URL.
- Exits non-zero when the file is missing or is not `.md`, when no `origin`
  remote exists, or when the origin URL has no host.

## Tests

```bash
bash tests/post-gist-test.sh
```

The test replaces `gh` with a fake, so it needs no network or credentials.
