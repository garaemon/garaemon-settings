---
name: add-paper-from-url
description: |
  Add a paper to Paperpile from a PDF URL. Always attach three artifacts to the
  newly created item: the original PDF, a Japanese bilingual (side-by-side)
  translation produced by the `pdf2zh` skill, and a Japanese Ochiai-format
  summary note. The `paperpile` CLI and the PDF download run inside a hardened
  Docker container; nothing executes on the host directly.
  Trigger when the user provides a PDF URL and wants it added to Paperpile with
  a summary, or says things like "この論文追加して <url>", "paperpileに追加して <url>",
  "add this paper <url>", "PDFから論文追加して".
  Scope: this skill is specialized for adding a paper from a URL, with the
  translated version attached automatically. Other Paperpile workflows should
  live in separate skills.
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/add-paper-from-url/run.sh:*), Bash($CLAUDE_PLUGIN_ROOT/skills/pdf2zh/run.sh:*)
---

# Add Paper from URL Skill

Download a PDF from a URL, upload it to Paperpile, translate it to Japanese and
attach the bilingual PDF to the same item, then generate a Japanese Ochiai-format
summary from the PDF content and attach it as a note. Every Paperpile CLI
invocation (curl download, `paperpile` CLI) is routed through `run.sh`, which
launches a locked-down Docker container with the Paperpile config mounted
read-only and a single workspace directory mounted read-write for the PDF.
Translation is delegated to the `pdf2zh` skill, which runs in its own isolated
container with a Gemini API key mounted read-only.

## Prerequisites

- The `add-paper-from-url:local` Docker image is built:

  ```bash
  docker build -t add-paper-from-url:local \
    "$CLAUDE_PLUGIN_ROOT/skills/add-paper-from-url"
  ```

- The `pdf2zh:local` Docker image is built (see
  [`pdf2zh`](../pdf2zh/SKILL.md) for the full setup instructions):

  ```bash
  docker build -t pdf2zh:local \
    "$CLAUDE_PLUGIN_ROOT/skills/pdf2zh"
  ```

- The host has a valid Paperpile config at `~/.config/paperpile/config.yaml`
  (create it with `paperpile login` on the host — the login flow opens a browser
  and is not something the skill runs).
- The config file must be mode `600` or `400`:

  ```bash
  chmod 600 ~/.config/paperpile/config.yaml
  ```

  `run.sh` refuses to start if the mode is looser than that.

- A Gemini API key is placed at `~/.config/pdf2zh/gemini.key` with mode `600`
  (required by the `pdf2zh` skill for translation). The `pdf2zh` run.sh refuses
  to start if the key is missing or has looser permissions.

If any prerequisite is missing, stop and tell the user exactly which step is
needed. Do not try to work around a missing config.

## Workspace directory

All PDFs are downloaded into `/tmp/paperpile-add/` on the host, which is the same
path bind-mounted into the container. Use this path both when invoking `run.sh`
and when reading the PDF with the `Read` tool — they refer to the same file.

The `pdf2zh` skill is also directed to write its translated output into the same
`/tmp/paperpile-add/` directory (via `--output`). This keeps the original and the
translated PDFs in one workspace so `paperpile attach` can read both without an
extra mount.

## Inputs

- A single PDF URL. If the user gave an abstract page URL (e.g., arXiv abs/, ACM, IEEE),
  resolve it to the direct PDF URL first (arXiv: replace `/abs/` with `/pdf/` and add `.pdf`).
- If the URL is ambiguous or the user gave multiple URLs, ask which one to add.

## Workflow

### Step 1: Download the PDF via the container

Always store the URL in a shell variable first and reference it as `"$URL"`. Do not
interpolate the raw URL into single-quoted command arguments — URLs containing single
quotes or shell metacharacters would break the command.

```bash
RUN_SH="$CLAUDE_PLUGIN_ROOT/skills/add-paper-from-url/run.sh"
URL='<url>'
TMP_PDF="/tmp/paperpile-add/$(date +%s)-$(basename "$URL" | sed 's/[^A-Za-z0-9._-]/_/g').pdf"
"$RUN_SH" fetch "$URL" "$TMP_PDF"
```

Verify the download:

- File size > 0
- First bytes are `%PDF` (run `file "$TMP_PDF"` and confirm it says PDF)

If the download failed or the file is not a PDF (e.g., HTML login wall), stop and report
the problem to the user. Do not upload a non-PDF.

### Step 2: Upload to Paperpile

```bash
"$RUN_SH" paperpile upload "$TMP_PDF"
```

Expected stdout:

```text
Uploading <basename> ...
Done! Task ID: <task_id>
```

The Task ID returned here is an upload-task identifier, not the final library item ID.
It cannot be used with `paperpile note set`. The final item ID must be obtained from
`paperpile list` in the next step.

### Step 3: Find the New Item ID

Note: the Task ID returned by `paperpile upload` cannot be used with `paperpile note set`.
The item ID must be obtained from `paperpile list`, which is sorted newest-first by default.
Poll briefly because Paperpile needs a moment to process the upload and create the item.

First extract the expected title from the PDF (via `Read` — a lightweight
first-page read is enough here; Step 5 does the full read for the summary),
then poll until the top-of-list title contains it:

```bash
EXPECTED_TITLE="<short substring of the PDF title>"
NEW_ID=""
for i in 1 2 3 4 5 6; do
  # paperpile list output uses whitespace-aligned columns; $1 is the ID, columns 4+ are the title.
  LINE=$("$RUN_SH" paperpile list | sed -n '2p')
  CANDIDATE_ID=$(echo "$LINE" | awk '{print $1}')
  CANDIDATE_TITLE=$(echo "$LINE" | awk '{for (i=4; i<=NF; i++) printf "%s ", $i; print ""}')
  if [[ "$CANDIDATE_TITLE" == *"$EXPECTED_TITLE"* ]]; then
    NEW_ID="$CANDIDATE_ID"
    break
  fi
  sleep 2
done
```

Verification: read the PDF title (from the PDF itself — see Step 5) and confirm the
top-of-list title roughly matches. If the top item looks stale (e.g., created minutes ago
and title mismatches), wait longer or ask the user to confirm the item ID.

If multiple papers might be uploaded concurrently, show the user the top 3 rows of
`"$RUN_SH" paperpile list` and confirm which ID corresponds to the paper just uploaded.

### Step 4: Start the Translation in the Background

Translation is the slowest part of this flow (roughly one minute per PDF page),
so kick it off with `run_in_background=true` **before** reading the PDF for
the summary. The summary generation in Steps 5–6 then runs in parallel with
pdf2zh's work, and Step 7 waits on the translation and attaches it.

```bash
PDF2ZH_RUN="$CLAUDE_PLUGIN_ROOT/skills/pdf2zh/run.sh"
"$PDF2ZH_RUN" "$TMP_PDF" --output /tmp/paperpile-add
# → /tmp/paperpile-add/<basename>-mono.pdf
# → /tmp/paperpile-add/<basename>-dual.pdf
```

Invoke this via the `Bash` tool with `run_in_background: true`. Record the
returned task ID so Step 7 can wait for it. If the user has overridden the
default model or languages in conversation, pass `--model`, `--source-lang`,
or `--target-lang` here.

### Step 5: Read the PDF and Generate the Summary

Use the `Read` tool on `$TMP_PDF` (the host path, which is identical to the container
path) to extract the paper's content. For long papers (>10 pages), read targeted page
ranges: title page + intro, method section, results, discussion, references page (for
"next papers to read").

Generate a Japanese summary following the Ochiai format below. The note is written in
Markdown (pass `--markdown` to `paperpile note set`).

**Content generation instructions (internal — follow when writing the note):**

```text
日本語で回答してください。ここでは英語論文の説明をお願いします。
私がアップする論文のみを要約して、他の文献と間違えないでください。
要約と質問に対しては、アップした論文をもとに答えてください。
例えば「CADデータが使われているか？」の質問に対しては、その論文の記述を確認して答えてください。
論文での記述がなく、わからない場合はその旨を伝えてください。

以下の項目について、A4一枚程度にまとめてください。
```

**Note body format (this is what gets saved):**

```markdown
## どんなもの？

<2–4 sentences in Japanese>

## 先行研究と比べてどこがすごい？

<2–4 sentences in Japanese>

## 技術や手法のキモはどこ？

<2–4 sentences in Japanese>

## どうやって有効だと検証した？

<2–4 sentences in Japanese>

## 議論はある？

<2–4 sentences in Japanese>

## 次読むべき論文は？

<list of 2–4 related references cited in the paper, with short reason each>
```

Rules for the summary content:

- Base every statement on the uploaded PDF only. Do not mix in knowledge from other
  papers.
- If a section cannot be answered from the PDF (e.g., no discussion section), write
  `論文中に明確な記述なし` rather than inventing content.
- Keep total length around one A4 page (~600–900 Japanese characters).
- Use paper-specific terminology from the PDF.

### Step 6: Attach the Note

Save the generated summary to a shell variable, then pass it as the note body. Because
`paperpile note set` takes the text as positional args, use proper quoting:

```bash
SUMMARY=$(cat <<'EOF'
## どんなもの？

...

## 次読むべき論文は？

...
EOF
)
"$RUN_SH" paperpile note set --markdown "$NEW_ID" "$SUMMARY"
```

Verify with:

```bash
"$RUN_SH" paperpile note get --markdown "$NEW_ID"
```

### Step 7: Wait for Translation and Attach the Bilingual PDF

Wait for the background translation task kicked off in Step 4 to finish, then
attach the bilingual (side-by-side) PDF to the same item. The skill attaches
only `<basename>-dual.pdf` by default — it contains both the original and the
translated text so it covers both reading modes. If the user asks for the
translation-only version, attach `<basename>-mono.pdf` instead (or in
addition).

```bash
BASE=$(basename "$TMP_PDF" .pdf)
DUAL_PDF="/tmp/paperpile-add/${BASE}-dual.pdf"
"$RUN_SH" paperpile attach "$NEW_ID" "$DUAL_PDF"
```

If the translation task failed (non-zero exit), surface the error to the user
and skip the attach — do not attach a stale or empty PDF. The item still has
the original PDF and the summary note, so the user can retry translation
separately via the `pdf2zh` skill.

### Step 8: Cleanup and Report

- Remove the temp PDFs: `rm -f "$TMP_PDF" /tmp/paperpile-add/${BASE}-mono.pdf
  /tmp/paperpile-add/${BASE}-dual.pdf` (the workspace dir is a host path, so
  regular host `rm` works).
- Report to the user in Japanese: item ID, title, that the note was attached,
  and that the bilingual translation was attached (or that translation
  failed, if applicable). A preview of the summary is NOT required; just
  confirm both attachments.

## Error Handling

- `run.sh` refuses to start with a clear error if the image is missing, the config
  file is absent, or its permissions are too loose. Surface the error to the user
  rather than trying to recover automatically.
- `pdf2zh` run.sh refuses to start if its image is missing or `gemini.key` is
  missing/loose — surface the error and stop. Do not swap translation engines
  silently.
- Download fails (404, auth wall, HTML instead of PDF): stop, tell the user the URL did
  not yield a PDF, and ask for a direct PDF URL.
- `paperpile upload` errors (duplicate, auth expired): surface the CLI error verbatim.
  For duplicates, ask the user whether to retry with `--allow-duplicates`.
- Item ID not found after polling: show `"$RUN_SH" paperpile list | head -5` to the user
  and ask them to pick the right ID.
- `paperpile note set` fails: show the error; do not retry silently.
- Translation fails (Gemini rate limit, malformed PDF, pdf2zh non-zero exit):
  surface the error, skip Step 7's attach, and report to the user that the
  item was added with the original PDF and note but without the bilingual
  translation.

## Out of Scope

This skill only handles the add-from-URL + summary-note + translation flow.
Do NOT extend it to:

- Labeling, searching, or deleting items
- Editing existing notes or attachments
- Bulk imports
- Translating papers that are already in Paperpile without going through the
  add-from-URL path (that belongs in a separate skill)

Those belong in separate Paperpile-focused skills.
