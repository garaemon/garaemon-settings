---
name: org-deepsearch
description: |
  Research a user-specified topic via web search and related-paper lookup,
  then draft an org-roam node summarising the findings and open a pull
  request against the configured org repository. The skill runs in two
  phases. Dry-run always runs first: it plans the searches, collects
  evidence from the web and academic sources, drafts the proposed `.org`
  file, and shows the result in chat for user review — no file writes,
  no git operations. Apply mode (opt-in, only when the user explicitly
  asks) creates the `.org` file under the roam directory, runs
  `org-roam-db-sync`, commits with a bot identity, and opens a PR. The
  workflow is for building a personal knowledge base from ad-hoc
  research questions: the user asks "look into X", the skill returns a
  structured, source-cited org node ready to merge.
  Trigger when the user asks to research, investigate, or summarise a
  topic into org/roam, or says things like "<topic> について調べて org に
  まとめて", "<topic> を調査して roam に入れて", "deepsearch <topic>",
  "<topic> のリサーチノート作って", "research <topic> and make a roam
  node". Also trigger on follow-up phrases like "apply this",
  "これで作って", "PR出して" once a proposal is already in the chat.
allowed-tools: Bash(date:*), Bash(uuidgen:*), Bash(sqlite3:*), Bash(git:*), Bash(gh:*), Bash(emacs:*), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
---

# Org Deepsearch Skill

Turn a user-specified research question into an org-roam node. The skill
plans search queries, runs `WebSearch` / `WebFetch` across the open web
and academic sources, and drafts a Japanese summary with source
citations. The user reviews the draft in chat; when they approve, apply
mode creates the file, runs `org-roam-db-sync`, and opens a pull request
against `$org_dir`.

The two modes mirror the `org-graduate` skill:

- **Dry-run** (Steps 1–7): always runs first. Plans searches, gathers
  evidence, drafts the proposed node, prints the proposal. No file
  writes, no git operations.
- **Apply** (Steps 8–14, optional): only runs when the user approves
  the dry-run proposal and explicitly asks to apply. Creates the
  `.org` file, runs `org-roam-db-sync`, commits with the bot
  identity, pushes, and opens a PR.

Apply mode operates on `$org_dir` (a separate git repo), never on the
skill's own repo.

## Prerequisites

### Dry-run mode

- Network access for `WebSearch` / `WebFetch`.
- `sqlite3` is installed and the org-roam DB exists (used to
  de-duplicate against existing nodes).

### Apply mode (in addition)

- `uuidgen` is installed (used to generate node IDs in the
  existing uppercase-hyphenated format).
- `emacs --batch` can load the user's `init.el` and has `org-roam`
  available, so that `(org-roam-db-sync)` resolves.
- `git` is installed and `$org_dir` is a clean git repo with a remote.
- `gh` (GitHub CLI) is authenticated and able to open PRs against the
  configured remote.

### Config

A config file at `~/.config/org-deepsearch/config.toml` tells the skill
where the org directory and roam DB live, plus the bot identity used
for apply-mode commits. A minimal config:

```toml
org_dir = "/home/garaemon/ghq/github.com/garaemon/org"
roam_dir = "/home/garaemon/ghq/github.com/garaemon/org/org-roam"
roam_db = "/home/garaemon/.emacs.d/org-roam.db"
default_filetags = ["deepsearch"]
default_web_results_per_query = 5
default_paper_results = 5

# Apply mode only
bot_name = "garaemon-bot"
bot_email = "garaemon+githubbot@gmail.com"
pr_remote = "origin"
pr_base_branch = "main"
```

Field notes:

- `default_filetags` is prepended to every generated node so the user
  can grep for AI-researched nodes (`:deepsearch:`). Topical tags are
  appended on top of this base.
- `default_web_results_per_query` / `default_paper_results` cap how
  many entries the skill inspects per query. Keep them small so search
  cost stays predictable; the user can ask for more on demand.
- `bot_name` / `bot_email` are the git identity used for apply-mode
  commits. The skill sets them per-commit via `GIT_COMMITTER_*` /
  `GIT_AUTHOR_*` env vars; the user's global git config stays
  untouched.
- `pr_remote` / `pr_base_branch` point at the remote and base branch
  of the org repo.

If the config file is missing, stop and print the example above. Do
not invent defaults; the paths are host-specific. Apply-mode-only
fields are optional when the user is only running dry-run. Fields
overlap with `~/.config/org-graduate/config.toml` on purpose — copy
the shared values across, or keep one authoritative copy and symlink.

## Inputs

The primary input is the research topic. Interpret intent liberally;
the user may phrase it as:

- A plain noun phrase: "MCP server security", "SWE-Bench"
- A question: "how does speculative decoding work?"
- A comparison: "RAG vs long-context vs fine-tuning — when to pick which"
- A problem: "why does my Postgres WAL grow unbounded under logical replication?"

The user may optionally specify:

- Depth: "quick overview" (3–4 queries, 1–2 papers) vs "deep dive"
  (6–10 queries, 4–6 papers). Default: balanced — 4–6 queries, 2–3
  papers.
- Scope hints: specific sub-questions, preferred sources (e.g. "only
  academic"), or existing nodes the result should link to.

If the topic is too broad to fit into a single node (e.g. "the history
of AI"), ask the user to narrow down or to split into multiple nodes.
Do not silently scope down.

## Workflow

### Step 1: Load config

Read `~/.config/org-deepsearch/config.toml` with the `Read` tool. The
format is flat TOML: extract `org_dir`, `roam_dir`, `roam_db`,
`default_filetags` (array of strings), `default_web_results_per_query`
(integer), `default_paper_results` (integer). Verify every path exists
before proceeding.

If the config file is missing or any required path does not exist,
stop and surface the error together with the example config from
Prerequisites.

### Step 2: Draft the search plan

Break the topic into 4–6 search queries (more or fewer based on the
depth hint) that together cover the topic. Mix query types:

- Definition / overview: `<topic> overview`, `what is <topic>`
- Technical depth: `<topic> implementation`, `<topic> architecture`
- Comparison: `<topic> vs <known alternative>`
- Current state: `<topic> 2025`, `<topic> recent advances`
- Academic: `<topic> arxiv`, `<topic> survey paper`

Print the plan as a short bullet list in chat before executing. The
user may adjust it ("add a query about X", "drop the comparison
one") — incorporate the adjustment and continue. This review gate
keeps wasted searches to a minimum.

### Step 3: Check for an existing roam node

Use the roam DB to see whether the topic already has a node. Strip
the surrounding double quotes org-roam stores around `id`, `title`,
and `alias` values.

```bash
sqlite3 "$roam_db" <<SQL
SELECT DISTINCT replace(n.id, '"', ''), replace(n.title, '"', '')
FROM nodes n
LEFT JOIN aliases a ON n.id = a.node_id
WHERE replace(n.title, '"', '') LIKE '%${TOPIC}%' COLLATE NOCASE
   OR replace(a.alias, '"', '') LIKE '%${TOPIC}%' COLLATE NOCASE;
SQL
```

Also run the `Grep` tool against `$roam_dir` (glob `*.org`) for
content-level matches. If a close match exists, ask the user:

- **Append**: add a new `* 事象ログ` entry to the existing node (see
  Step 12's append branch).
- **Create new**: proceed with a fresh node anyway (e.g. the existing
  match is too narrow, or about a different sense of the term).
- **Cancel**: stop.

If no close match exists, proceed with create-new by default.

### Step 4: Execute web searches

For each query in the plan, call `WebSearch`. From the top
`default_web_results_per_query` results, keep a note of:

- URL, title, one-line snippet.
- Whether the result is worth fetching in full (primary source,
  detailed blog post, official docs) or is a shallow aggregator.

For high-value results, call `WebFetch` to extract the full page
content. Budget: 3–5 `WebFetch` calls per run on balanced depth; the
user can ask for more.

Capture every URL the skill actually uses as evidence — the references
list in Step 6 will cite them.

### Step 5: Find related papers

Search arXiv and Google Scholar equivalents via `WebSearch`. Good
query shapes:

- `<topic> site:arxiv.org`
- `<topic> survey site:arxiv.org`
- `<topic> filetype:pdf`

For each paper candidate, use `WebFetch` on the arXiv abstract page
(`https://arxiv.org/abs/<id>`) to pull:

- Title, authors, year, arXiv ID.
- Abstract (distill into 1–2 Japanese sentences for the final node).

Cap at `default_paper_results`. Skip papers that are only loosely
related — a small curated list beats a long list of noise.

If the topic is clearly non-academic (e.g. a consumer product
review), skip this step and note in the proposal that no academic
search was run.

### Step 6: Synthesize findings

Draft the node body in Japanese. Required sections:

- `* 概要` — 3–5 sentence summary of what the topic is and why it
  matters. Ground every sentence in the gathered evidence.
- `* 背景 / 文脈` — surrounding context, prerequisites, adjacent
  concepts. Link to existing roam nodes with `[[id:...]]` when the
  DB query in Step 3 turned up near-matches.
- `* 主要なポイント` — the substantive content: how it works, what
  the trade-offs are, what the current state is. Use sub-headings
  (`**`) to structure.
- `* 関連研究` — the paper list from Step 5, one bullet per paper:
  `** <title> (<authors>, <year>) [[<arxiv-url>]]` followed by a
  1–2 sentence Japanese distillation of the abstract. Omit this
  section entirely if Step 5 was skipped.
- `* 参考文献` — every web URL cited as evidence, with a one-line
  label each. This is the audit trail; a future reader must be
  able to follow any claim back to a source.
- `* 次の調査候補` — 2–4 follow-up questions the current research
  opened up but did not resolve. These feed future deepsearch runs.

Rules for the content:

- Base every factual claim on a cited source. When a claim is the
  skill's own synthesis across several sources, phrase it as a
  tentative reading (e.g. `〜と考えられる`, `〜という整理ができる`)
  rather than an assertion.
- When sources disagree, surface the disagreement explicitly rather
  than picking a side silently.
- Do not fabricate paper titles, authors, or arXiv IDs. If a paper
  candidate's abstract cannot actually be retrieved, drop it from
  the list.
- Keep the total body around 800–1500 Japanese characters for a
  balanced-depth run. Deep-dive runs may go longer.

### Step 7: Render the proposal

Print a single markdown report to the chat. Structure:

````markdown
# org-deepsearch proposal (dry-run)

- Topic: <verbatim user question>
- Depth: <quick | balanced | deep>
- Search queries run: K
- Web results inspected: W (fetched in full: F)
- Papers cited: P

## Existing roam node check

<either "no near-match found — proposing a new node" or
"near-match: [[id:UUID]] <title>, <file>. User chose: create-new |
append | cancel">

## Proposed new node

Suggested filename: `YYYYMMDDHHMMSS-<file_slug>.org`
Suggested `#+title:`: `<title>`
Suggested `#+filetags:`: `:deepsearch:<tag1>:<tag2>:`

Proposed body:

```org
:PROPERTIES:
:ID:       <generate when applied>
:END:
#+title: <title>
#+date: <today>
#+filetags: :deepsearch:<tag1>:<tag2>:

* 概要
<body...>

* 背景 / 文脈
<body...>

* 主要なポイント
...

* 関連研究
...

* 参考文献
- [[<url>][<label>]] — <one-line note>
- ...

* 次の調査候補
- <question 1>
- <question 2>
```

## Next steps

To apply: ask Claude to apply this proposal. Claude will confirm the
scope with you before writing any files.
````

## Apply mode

After Step 7 has produced a dry-run proposal in the chat, the user
may ask to apply it (triggers: "apply", "これで作って", "PR出して").
Apply mode modifies the `$org_dir` git repo on disk: it creates the
`.org` file, runs `org-roam-db-sync`, commits with the bot identity,
pushes the branch, and opens a pull request.

Every git operation in this section targets `$org_dir` via
`git -C "$org_dir" ...`. The only place the skill changes directory
is when invoking `gh pr create`, so the CLI picks up the org repo's
remote. Never run git commands in the skill's own repo as part of
apply mode.

### Step 8: Confirm the apply scope

Summarise the pending write as a short bullet (action, node title,
filename). Ask the user to confirm: apply, edit first, or cancel. If
the user wants edits, fold them into the proposal and re-ask. If the
user cancels, stop without touching any file.

### Step 9: Verify org repo preconditions

Fail fast on any of the following. Surface the exact check that
failed and stop; do not attempt auto-recovery.

```bash
git -C "$org_dir" rev-parse --git-dir >/dev/null
[[ -z "$(git -C "$org_dir" status --porcelain)" ]]
git -C "$org_dir" fetch "$pr_remote" "$pr_base_branch"
git -C "$org_dir" checkout "$pr_base_branch"
git -C "$org_dir" pull --ff-only "$pr_remote" "$pr_base_branch"
```

If the working tree is dirty, do NOT stash. Stop and ask the user to
commit or shelve their changes first.

Branch name: `YYYY.MM.DD-org-deepsearch-<branch_slug>` using today's
date and the `branch_slug` from Step 10 (the ASCII-only slug, not the
file slug). Fail if it already exists on the local or remote side:

```bash
new_branch="$(date +%Y.%m.%d)-org-deepsearch-${branch_slug}"
if git -C "$org_dir" show-ref --quiet "refs/heads/$new_branch" \
|| git -C "$org_dir" ls-remote --exit-code --heads "$pr_remote" "$new_branch" >/dev/null 2>&1; then
  die "Branch $new_branch already exists. Delete or rename before retrying."
fi
```

### Step 10: Generate UUID, timestamp, slugs

- UUID: `uuidgen | tr 'a-z' 'A-Z'` — match the uppercase-hyphenated
  format used by the existing corpus.
- Filename timestamp: `date +%Y%m%d%H%M%S`.
- `file_slug` (used in the `.org` filename): lowercase the title,
  replace spaces with `_`, strip any characters other than
  alphanumerics, `_`, `-`, and CJK. Example: `MCP server security`
  becomes `mcp_server_security`, `逆運動学` stays `逆運動学`. This
  matches the existing roam corpus which routinely has CJK in
  filenames.
- `branch_slug` (used only in the git branch name): **ASCII-only**,
  matching `[a-z0-9-]+`, kebab-case, at most ~40 characters. Derive
  it from the title as follows:
  - If the title is already ASCII, lowercase it, replace whitespace
    and underscores with `-`, and strip remaining non-matching
    characters. Example: `MCP server security` →
    `mcp-server-security`.
  - If the title contains non-ASCII (e.g. Japanese), produce a short
    English translation / romanization of the core concept and
    apply the same ASCII rules to it. Examples: `逆運動学` →
    `inverse-kinematics`, `ソートアルゴリズム` → `sort-algorithms`,
    `擬似逆行列` → `pseudo-inverse`.
  - If nothing sensible can be produced (extremely unlikely), fall
    back to the filename timestamp: `node-${timestamp}`.
  The goal is a branch name that works cleanly in URLs, shell
  arguments, and `gh` commands without percent-encoding — keeping
  the non-ASCII expression reserved for the file and the PR title.
- Full path: `$roam_dir/${timestamp}-${file_slug}.org`.

### Step 11: Create the feature branch

```bash
git -C "$org_dir" checkout -b "$new_branch"
```

All subsequent writes happen on this branch.

### Step 12: Write the file

Build the body from the proposal template, substituting the
generated UUID into the `:ID:` line and replacing any placeholder
`<generate when applied>` tokens with the corresponding UUID. Set
`#+date:` to today in `<YYYY-MM-DD Ddd>` format.

#### Create-new branch (default)

Write the file at `$roam_dir/${timestamp}-${file_slug}.org` via the
`Write` tool. Fail if the file already exists (extremely unlikely
with a timestamped name, but the safety check is cheap).

#### Append branch (when Step 3 chose append)

Instead of writing a new file, edit the existing node's file:

1. Read the target file from the DB row (`n.file`).
2. Find the `* 事象ログ` top-level heading. If absent, append a new
   `* 事象ログ` heading at the end of the file, preceded by a blank
   line.
3. Append a `** <YYYY-MM-DD> <short heading>` block under the
   `* 事象ログ` section. The body is a distilled 3–6 line excerpt
   of the research findings plus a `参考文献:` footer listing the
   URLs — not the full multi-section report.
4. Preserve the file's existing content, line endings, indentation,
   and trailing newline. Edit in place using the `Edit` tool so the
   diff is minimal.

### Step 13: Run org-roam-db-sync

After the file write, refresh the roam DB so the committed branch
state matches Emacs's view:

```bash
emacs --batch -l ~/.emacs.d/init.el --eval '(org-roam-db-sync)' 2>&1
```

If the command exits non-zero or prints an org-roam error, stop and
surface the full output verbatim. Do NOT roll back the file change —
the branch contains an uncommitted edit the user may want to
inspect. Recommend that the user fix their Emacs config and re-run
sync manually, or drop the branch with
`git -C "$org_dir" checkout $pr_base_branch && git -C "$org_dir" branch -D $new_branch`.

### Step 14: Commit, push, open the PR

Stage only the file(s) the apply touched. Never use `git add -A`,
`git add .`, or `git add <dir>` — stage each file explicitly so
unrelated files (e.g. org-roam DB caches, backup `~` files, dailies
that got auto-committed during the run) are not swept in.

```bash
git -C "$org_dir" add "$roam_dir/${timestamp}-${file_slug}.org"   # create-new branch
# OR
git -C "$org_dir" add "<existing-node-file>"                 # append branch

GIT_COMMITTER_NAME="$bot_name" \
GIT_COMMITTER_EMAIL="$bot_email" \
GIT_AUTHOR_NAME="$bot_name" \
GIT_AUTHOR_EMAIL="$bot_email" \
  git -C "$org_dir" commit -m "$(cat <<'MSG'
org-deepsearch: add node <title>

Research digest for: <topic>
- Web sources cited: W
- Papers cited: P

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
MSG
)"

git -C "$org_dir" push -u "$pr_remote" "$new_branch"

cd "$org_dir"
gh pr create \
  --base "$pr_base_branch" \
  --title "org-deepsearch: add node <title>" \
  --body "$(cat <<BODY
## Summary

Research digest for: <topic>

- Web sources cited: W
- Papers cited: P
- Follow-up questions: Q

## Sources

<bulleted list of source URLs>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
BODY
)"
```

Report the resulting PR URL to the user in the chat reply. That is
the end of apply mode — the user takes over for review and merge.

## Output rules

- The proposal report itself (section headers, meta lines) stays in
  English. Claude's surrounding chat reply may be in Japanese per
  the user's preference.
- **All generated org content is written in Japanese**, matching the
  user's existing roam nodes. Section headings use `* 概要`,
  `* 背景 / 文脈`, `* 主要なポイント`, `* 関連研究`, `* 参考文献`,
  `* 次の調査候補` — never their English equivalents.
- `#+title:` uses the natural Japanese name when one exists; keep
  public proper nouns, product names, and tool names in their
  native spelling (e.g. `ros`, `docker`, `PostgreSQL`, `MCP`).
- `#+filetags:` starts with the `default_filetags` base (e.g.
  `:deepsearch:`) and appends topical tags the user's existing
  corpus uses — short romaji or English tokens like `:tool:`,
  `:paper:`, `:llm:`, `:infra:`.
- **Every factual claim must cite a source.** The `* 参考文献`
  section is the audit trail; omitting it is a bug, not a style
  choice. If a claim cannot be tied to a source, either find one or
  drop the claim.
- Do not fabricate paper titles, arXiv IDs, DOIs, author names, or
  publication years. When a paper search returns nothing usable,
  say so — do not invent placeholders.
- Do not fabricate URLs. Every citation must point at a page the
  skill actually fetched or that appeared in a real `WebSearch`
  result.
- Do not fabricate content from training data when searches fail.
  If every query returns empty, stop and tell the user the topic
  could not be researched under current network conditions; do not
  fall back to prior knowledge.
- Do not fabricate node IDs. Write `:ID:       <generate when applied>`
  verbatim in the dry-run proposal; the real UUID is generated in
  Step 10.

## Out of scope

- Iterating on an already-merged node (further research appended to
  the same node after merge). The skill always opens a fresh PR —
  amending is a manual workflow.
- Multi-node runs in a single invocation. One research question per
  invocation. Splitting a broad topic is an upstream decision the
  user makes before invoking.
- Automated fact-checking against authoritative databases (Wikipedia
  API, Crossref, Semantic Scholar). The skill uses only `WebSearch`
  and `WebFetch`; deeper verification is a follow-up the user does
  during PR review.
- Paywalled or login-gated content. If `WebFetch` returns a login
  wall, treat that URL as unreachable and drop it from citations.
- Merging the PR. The skill stops after `gh pr create`; the user
  reviews and merges.

## Error handling

### Dry-run

- Config file missing or malformed → stop; print the example config.
- Any path in the config does not exist → stop; ask the user to fix
  the config.
- `WebSearch` / `WebFetch` rate-limited or returning zero results
  for every query → stop and report the failure; do not fabricate
  content from training data.
- Roam DB query fails → show the sqlite error verbatim; proceed
  with create-new (the DB check is a nice-to-have for
  de-duplication, not a hard dependency for dry-run).
- Topic is too broad to fit a single node → stop; ask the user to
  narrow or split.

### Apply

- `uuidgen`, `emacs --batch`, `git`, or `gh` is missing → stop and
  ask the user to install it; do not try an alternative binary.
- Apply-mode config field missing (`bot_name`, `bot_email`,
  `pr_remote`, `pr_base_branch`) → stop with a clear message naming
  the missing key.
- `$org_dir` working tree is dirty → stop; ask the user to commit
  or shelve changes.
- Branch name already exists locally or on the remote → stop; ask
  the user to delete or rename.
- `$pr_base_branch` cannot be fast-forwarded from the remote → stop;
  ask the user to reconcile manually.
- `org-roam-db-sync` fails after the file write → surface output,
  leave the branch in place for the user to inspect. Do NOT roll
  back. Do NOT commit or push in this state.
- `git commit` / `git push` / `gh pr create` fails → surface the
  error, stop, and report the current local branch state so the
  user can recover (the uncommitted or unpushed work is still on
  disk).
