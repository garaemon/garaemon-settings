---
name: gist-report
description: |
  Write a report as Markdown in two versions (Japanese and English), embed any
  image files, and upload everything as one GitHub gist with the gh CLI, using
  the GitHub host of the repository's origin remote (github.com or GitHub
  Enterprise). Use this skill when the user wants a report, summary,
  investigation notes, or analysis written up and shared as a gist, or says
  things like "レポートをgistに上げて", "gistにして", "レポート書いてgist",
  "share this as a gist", "write a report and post it to a gist".
---

# Gist Report Skill

Write a report as two Markdown files (English and Japanese), then upload them
and their images as one gist with `scripts/post-gist.sh`. The script derives
`GH_HOST` from the `origin` remote URL, so never set or guess `GH_HOST` by hand.

## Workflow

1. Write the English report to `<topic>.en.md` and the Japanese report to
   `<topic>.ja.md` in the scratchpad directory (or another temporary location
   outside the repository). Use lowercase kebab-case for `<topic>`.
   - Give both files the same structure, headings order, numbers, and images.
   - Write each one as a native document, not a word-for-word translation.
2. Collect the image files the report shows (screenshots, charts). Reference
   them from both Markdown files with a relative path, for example
   `![Latency](images/latency.png)`. The link only has to end in the image's
   file name; the script rewrites it.
3. Run the script from inside the repository whose origin decides the host.
   Use the absolute path of the script, for example
   `~/.claude/skills/gist-report/scripts/post-gist.sh`:

   ```bash
   post-gist.sh [--public] [--description TEXT] \
     topic.en.md topic.ja.md [IMAGE ...]
   ```

4. Show the gist URL that the script prints to the user.

## Rules

- Always produce both the English and the Japanese version, unless the user
  asks for one language only.
- Create a secret gist by default. Pass `--public` only when the user asks
  for a public gist. A secret gist, and its images, are still reachable by
  anyone with the URL.
- Ask the user before uploading if the report or an image contains
  credentials, internal hostnames, or other sensitive data.
- Do not call `gh gist create` directly. The script prevents a wrong host
  and an inherited `GH_HOST` from sending the report to the wrong server.
- Pass a short `--description` that names the report topic.
- Name image files with letters, digits, `.`, `_`, and `-` only, and give
  every image a distinct file name. A gist has no directories.
- Supported images: png, jpg, jpeg, gif, svg, and webp.
- Follow the `technical-writing` skill for the prose.

## What the script does

- Reads the URL of the `origin` remote. It accepts `https://`, `ssh://`, and
  scp-like (`git@host:owner/repo`) forms.
- Exports `GH_HOST` for that host, replacing any inherited value.
- Runs `gh gist create` on the Markdown files and takes the gist URL.
- When images are given:
  1. Clones the gist, because `gh gist create` rejects binary files.
  2. Copies the images into the clone.
  3. Rewrites image links (`](path/name.png)` and `src="path/name.png"`) in
     every Markdown file to `<gist URL>/raw/name.png`.
  4. Pushes one commit through `gh auth git-credential`.
- Prints the gist URL.
- Exits non-zero for a missing file, an unsupported extension, duplicate file
  names, an unsafe image name, no Markdown file, no `origin` remote, or an
  origin URL without a host.

## Tests

```bash
bash tests/post-gist-test.sh
```

The test replaces `gh` with a fake that publishes to a local bare repository,
so it needs no network or credentials. It does not exercise a real GitHub
server: the first real run is the check for the raw-URL form on GitHub
Enterprise.
