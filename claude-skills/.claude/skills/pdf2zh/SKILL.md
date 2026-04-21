---
name: pdf2zh
description: |
  Translate a PDF to Japanese (or another target language) with the `pdf2zh`
  (PDFMathTranslate) CLI using Gemini. The CLI runs inside a hardened Docker
  container with a read-only Gemini API key file mount. Outputs a monolingual
  PDF and a bilingual side-by-side PDF while preserving formulas and layout.
  Trigger when the user wants a PDF translated, or says things like
  "この論文翻訳して", "PDFを日本語に", "pdf2zhで翻訳", "translate this PDF",
  "英語の論文を日本語にして".
  Scope: translation only. Uploading the translated PDF to Paperpile is out
  of scope and belongs in a separate skill.
allowed-tools: Bash($CLAUDE_PLUGIN_ROOT/skills/pdf2zh/run.sh:*)
---

# pdf2zh Skill

Translate a PDF file using the
[PDFMathTranslate](https://github.com/PDFMathTranslate/PDFMathTranslate) CLI
(`pdf2zh`) backed by Gemini. The CLI runs inside a hardened Docker container
so it cannot touch the host filesystem beyond the single input PDF, the chosen
output directory, and a read-only mount of the Gemini API key.

## Prerequisites

- Docker is installed and the daemon is running.
- A Gemini API key from Google AI Studio with access to the chosen model.
- Input PDF accessible on the host filesystem.

## One-time setup

1. Save the Gemini API key to the default location and tighten permissions:

   ```bash
   mkdir -p ~/.config/pdf2zh
   printf '%s' "$YOUR_GEMINI_API_KEY" > ~/.config/pdf2zh/gemini.key
   chmod 600 ~/.config/pdf2zh/gemini.key
   ```

   To use a different path, export `GEMINI_KEY_FILE` pointing at the file.

2. Build the Docker image once:

   ```bash
   docker build -t pdf2zh:local \
     "$CLAUDE_PLUGIN_ROOT/skills/pdf2zh"
   ```

   Rebuild after updating the skill to pick up script or dependency changes.

## Usage

```text
run.sh <input.pdf> [--output DIR] [--source-lang LANG] [--target-lang LANG]
                   [--model MODEL] [--pages RANGE] [-- <extra pdf2zh args>]
```

| Flag | Default | Description |
| --- | --- | --- |
| `<input.pdf>` | (required) | Absolute or relative path to the source PDF |
| `--output DIR` | `/tmp/pdf2zh` | Directory the translated PDFs are written to |
| `--source-lang LANG` | `en` | Source language code (pdf2zh `-li`) |
| `--target-lang LANG` | `ja` | Target language code (pdf2zh `-lo`) |
| `--model MODEL` | `${PDF2ZH_GEMINI_MODEL:-gemini-3-flash-preview}` | Gemini model name |
| `--pages RANGE` | (all pages) | Page range, e.g. `1-3,5` (pdf2zh `-p`) |

Arguments after a literal `--` are forwarded to pdf2zh verbatim, for cases
where an advanced flag is needed.

### Output file naming contract

pdf2zh writes two files into the output directory, named from the input
basename:

- `<basename>-mono.pdf` — translated text only
- `<basename>-dual.pdf` — original and translated side-by-side

These names are a stable contract so downstream skills (e.g. a future
Paperpile uploader) can find the files without additional configuration.

### Example invocations

```bash
# Translate a single PDF with defaults (en→ja, Gemini 3 Flash preview).
.claude/skills/pdf2zh/run.sh ~/Downloads/paper.pdf

# Pick a specific model and pages, write into a project-local directory.
.claude/skills/pdf2zh/run.sh ~/Downloads/paper.pdf \
  --output ./translations \
  --model gemini-2.5-pro \
  --pages 1-5
```

## Isolation guarantees

Each `run.sh` invocation starts a container with:

- `--read-only` root filesystem, writable `/tmp` tmpfs only
- `--cap-drop ALL` and `--security-opt no-new-privileges`
- `--memory 2g --cpus 1.0` resource limits
- Non-root `nobody` user inside the container
- Gemini API key mounted read-only at `/secrets/gemini.key`
- Input PDF mounted read-only at `/input/<basename>.pdf`
- Output directory mounted read-write at `/output`
- `--network bridge` (outbound only; required to reach the Gemini API)

`run.sh` additionally guards against common misconfigurations before
launching:

- Refuses to run if the Docker image is missing and prints the build command.
- Rejects the key file if it is a symlink or not a regular file.
- Requires mode `600` or `400` on the key file.
- Fails fast if the input PDF does not exist or is not a regular file.

## When to use

- The user asks to translate a PDF, a paper, or a document into Japanese.
- The user mentions pdf2zh, PDFMathTranslate, or bilingual PDFs.
- A PDF path or URL is provided together with a translation request (resolve
  the URL to a local path before invoking this skill; downloading is the
  caller's responsibility).

## Out of scope

This skill only translates a PDF. It does NOT:

- Download PDFs from URLs.
- Upload translated PDFs to Paperpile (belongs in a separate skill).
- Summarise or otherwise post-process the translation.
