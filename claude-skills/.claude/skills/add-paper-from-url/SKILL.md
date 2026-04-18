---
name: add-paper-from-url
description: |
  Add a paper to Paperpile from a PDF URL, then attach a Japanese summary (Ochiai format)
  as a note via the `paperpile` CLI (github.com/garaemon/paperpile).
  Trigger when the user provides a PDF URL and wants it added to Paperpile with a summary,
  or says things like "この論文追加して <url>", "paperpileに追加して <url>",
  "add this paper <url>", "PDFから論文追加して".
  Scope: this skill is specialized for adding a paper from a URL. Other Paperpile workflows
  should live in separate skills.
---

# Add Paper from URL Skill

Download a PDF from a URL, upload it to Paperpile, generate a Japanese Ochiai-format
summary from the PDF content, and attach it as a note on the newly added item.

## Prerequisites

- `paperpile` CLI is installed and authenticated (`paperpile me` should succeed).
- `curl` is available for downloading the PDF.

If `paperpile` is missing, stop and ask the user to install it
(`go install github.com/garaemon/paperpile@latest` + `paperpile login`).

## Inputs

- A single PDF URL. If the user gave an abstract page URL (e.g., arXiv abs/, ACM, IEEE),
  resolve it to the direct PDF URL first (arXiv: replace `/abs/` with `/pdf/` and add `.pdf`).
- If the URL is ambiguous or the user gave multiple URLs, ask which one to add.

## Workflow

### Step 1: Download the PDF

Use a temp path under `/tmp` with a stable filename derived from the URL basename.

```bash
mkdir -p /tmp/paperpile-add
URL='<url>'
TMP_PDF="/tmp/paperpile-add/$(date +%s)-$(basename "$URL" | sed 's/[^A-Za-z0-9._-]/_/g').pdf"
curl -L -f -o "$TMP_PDF" "$URL"
```

Always store the URL in a shell variable first and then reference it as `"$URL"`. Do not
interpolate the raw URL into single-quoted command arguments — URLs containing single
quotes or shell metacharacters would break the command.

Verify the download:

- File size > 0
- First bytes are `%PDF` (run `file "$TMP_PDF"` and confirm it says PDF)

If the download failed or the file is not a PDF (e.g., HTML login wall), stop and report
the problem to the user. Do not upload a non-PDF.

### Step 2: Upload to Paperpile

```bash
paperpile upload "$TMP_PDF"
```

Expected stdout:

```
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

First extract the expected title from the PDF (via `Read` in Step 4, or a quick metadata
probe), then poll until the top-of-list title contains it:

```bash
EXPECTED_TITLE="<short substring of the PDF title>"
NEW_ID=""
for i in 1 2 3 4 5 6; do
  # paperpile list output uses whitespace-aligned columns; $1 is the ID, columns 4+ are the title.
  LINE=$(paperpile list | sed -n '2p')
  CANDIDATE_ID=$(echo "$LINE" | awk '{print $1}')
  CANDIDATE_TITLE=$(echo "$LINE" | awk '{for (i=4; i<=NF; i++) printf "%s ", $i; print ""}')
  if [[ "$CANDIDATE_TITLE" == *"$EXPECTED_TITLE"* ]]; then
    NEW_ID="$CANDIDATE_ID"
    break
  fi
  sleep 2
done
```

Verification: read the PDF title (from the PDF itself — see Step 4) and confirm the
top-of-list title roughly matches. If the top item looks stale (e.g., created minutes ago
and title mismatches), wait longer or ask the user to confirm the item ID.

If multiple papers might be uploaded concurrently, show the user the top 3 rows of
`paperpile list` and confirm which ID corresponds to the paper just uploaded.

### Step 4: Read the PDF and Generate the Summary

Use the `Read` tool on `$TMP_PDF` to extract the paper's content. For long papers (>10
pages), read targeted page ranges: title page + intro, method section, results,
discussion, references page (for "next papers to read").

Generate a Japanese summary following the Ochiai format below. The note is written in
Markdown (pass `--markdown` to `paperpile note set`).

**Content generation instructions (internal — follow when writing the note):**

```
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

### Step 5: Attach the Note

Save the generated summary to a temp file, then pass it as the note body. Because
`paperpile note set` takes the text as positional args, use a shell variable with proper
quoting:

```bash
SUMMARY=$(cat <<'EOF'
## どんなもの？

...

## 次読むべき論文は？

...
EOF
)
paperpile note set --markdown "$NEW_ID" "$SUMMARY"
```

Verify with:

```bash
paperpile note get --markdown "$NEW_ID"
```

### Step 6: Cleanup and Report

- Remove the temp PDF: `rm -f "$TMP_PDF"`
- Report to the user in Japanese: item ID, title, and that the note was attached.
  A preview of the summary (e.g., the first 1–2 lines of each section) is NOT required;
  just confirm the note was set.

## Error Handling

- Download fails (404, auth wall, HTML instead of PDF): stop, tell the user the URL did
  not yield a PDF, and ask for a direct PDF URL.
- `paperpile upload` errors (duplicate, auth expired): surface the CLI error verbatim.
  For duplicates, ask the user whether to retry with `--allow-duplicates`.
- Item ID not found after polling: show `paperpile list | head -5` to the user and ask
  them to pick the right ID.
- `paperpile note set` fails: show the error; do not retry silently.

## Out of Scope

This skill only handles the add-from-URL + summary-note flow. Do NOT extend it to:

- Labeling, searching, or deleting items
- Editing existing notes
- Bulk imports

Those belong in separate Paperpile-focused skills.
