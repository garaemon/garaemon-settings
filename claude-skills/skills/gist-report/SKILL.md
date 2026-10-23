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
and their images as one gist with `scripts/post_gist.py`. The script derives
`GH_HOST` from the `origin` remote URL, so never set or guess `GH_HOST` by hand.

## Workflow

1. Write the English report to `<topic>.en.md` and the Japanese report to
   `<topic>.ja.md` in the scratchpad directory (or another temporary location
   outside the repository). Use lowercase kebab-case for `<topic>`.
   - Give both files the same structure, headings order, numbers, and images.
   - Write each one as a native document, not a word-for-word translation.
2. Reference the images the report shows (screenshots, charts) from both
   Markdown files with a relative path, for example
   `![Latency](images/latency.png)`. The script finds these images itself, so
   do not list them on the command line. The path resolves against the
   directory of the Markdown file. The script rewrites inline links (with or
   without a title), `<img src>` attributes, and reference definitions
   (`[id]: path`).
3. Run the script from inside the repository whose origin decides the host.
   Call the script by its absolute path:

   ```bash
   python3 ~/.claude/skills/gist-report/scripts/post_gist.py [--public] [--description TEXT] \
     [--ignore-missing-images] topic.en.md topic.ja.md
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
- A local image link whose file does not exist fails the run before any
  upload. Fix the path. Pass `--ignore-missing-images` only when the link is
  intentional, for example an example path in a code block; the script then
  leaves that link unchanged.
- Pass an `IMAGE` argument only for an image that no Markdown link names.
- Name image files with letters, digits, `.`, `_`, and `-` only, and give
  every image a distinct file name. A gist has no directories.
- Supported images: png, jpg, jpeg, gif, svg, and webp. The script matches
  these extensions, and `.md`, in any letter case.
- Follow the `technical-writing` skill for the prose.

## What the script does

- Reads the URL of the `origin` remote. It accepts `https://`, `ssh://`, and
  scp-like (`git@host:owner/repo`) forms.
- Exports `GH_HOST` for that host, replacing any inherited value.
- Runs `gh gist create` on the Markdown files and takes the gist URL.
- Scans every Markdown file for local image references and adds the files it
  finds to the upload. It skips remote URLs and non-image targets, and it
  uploads an image used by several files once. Images given on the command
  line are uploaded too.
- When images are found or given:
  1. Reads the gist with `gh api gists/<id>` and clones its `git_pull_url`,
     because `gh gist create` rejects binary files. It tries SSH first
     (`git@<host>:<path>`) in batch mode with a 10-second connect timeout. When
     SSH fails, it prints the SSH error to stderr and clones over HTTPS
     through `gh auth git-credential`.
  2. Copies the images into the clone and pushes them in a first commit over
     the same protocol as the clone.
  3. Reads the `raw_url` of each image from the API. The script does not build
     the URL from the one that `gh gist create` printed, because that URL can
     lack the user name on GitHub Enterprise.
  4. Rewrites image links in every Markdown file to that `raw_url`. It handles
     inline links with or without a title, `src="path/name.png"` attributes,
     and reference definitions (`[id]: path/name.png`).
  5. Pushes the rewritten Markdown in a second commit. It skips this commit
     when no Markdown link changed.
- Prints the gist URL. When the image upload fails, it prints the gist URL and
  a `GH_HOST=<host> gh gist delete <id>` command to stderr first.
- Exits non-zero for a missing file, a referenced image that does not exist,
  an unsupported extension, duplicate file names, an unsafe image name, no
  Markdown file, no `origin` remote, or an origin URL without a host.

## Tests

```bash
python3 -m unittest discover -s scripts
```

The tests replace `gh` with a fake that publishes to a local bare repository,
so it needs no network or credentials. It does not exercise a real GitHub
server: the first real run is the check for the raw-URL form on GitHub
Enterprise.
