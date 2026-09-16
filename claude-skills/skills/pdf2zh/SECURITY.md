# pdf2zh: known advisories in the pinned dependencies

Maintainer notes, deliberately kept out of `SKILL.md`: that file is loaded into
context every time the skill runs, and an agent translating a PDF does not need
dependency triage to do it.

## Why the advisories cannot simply be fixed

`pdf2zh` hard-pins transitive dependencies that carry published advisories, and
the pins cannot move until upstream does. `pdf2zh` requires `gradio<5.36`, which
in turn caps `pillow<12.0`, so the `pillow` fix release 12.3.0 is unreachable.

Upgrading is not a way out either:

| Package | Version | `gradio` pin |
| --- | --- | --- |
| `pdf2zh` (in use) | 1.9.11, the latest release | `gradio<5.36` |
| `pdf2zh-next` (v2 successor) | 2.9.0 | `gradio<5.36`, unchanged |

Migrating to `pdf2zh-next` would relax `babeldoc<0.3.0` to `<0.7.0` but resolves
none of the reachable `pillow` advisories.

## How to triage an alert

Dependabot alerts track these; there is no `pip audit` CI job (see
[CLAUDE.md, DevSecOps](../../../CLAUDE.md) for why a blocking job was the wrong
tool here). Triage each alert against how this skill actually runs `pdf2zh`: a
batch CLI invocation, a positional PDF plus `-s gemini:<model>`, never
`pdf2zh -i`, inside the container described under
[Isolation guarantees](SKILL.md). That usage splits the advisories into three
groups.

### Not reachable: the web stack never starts

`gradio`, `starlette`, `python-multipart`, `msgpack`.

Every advisory in these needs an attacker to reach a running Gradio UI or HTTP
server, and we never launch one. Dismiss as *vulnerable code is not actually
used*.

### Not reachable: outbound calls go only to Gemini

`aiohttp`, `urllib3`, `cryptography`, `idna`.

These need a malicious redirect target, TLS peer, or hostname. The only outbound
destination is the trusted Gemini endpoint, and the input is a local PDF path,
never a URL we follow. Server-side `aiohttp` advisories additionally need the
never-started web server. Dismiss as *tolerable risk*.

### Reachable, and contained rather than absent

`pillow`, `pdfminer.six`, `babeldoc`.

`pillow` is the real surface: `pdf2zh` decodes images embedded in the input PDF,
so a crafted image can hit it. This matters because `add-paper-from-url` feeds
this skill PDFs fetched from arbitrary URLs.

`pdfminer.six` and `babeldoc` carry CMap pickle deserialization bugs, but those
fire only if an attacker can plant a malicious `.pickle` on disk. They are not
reachable from data inside the PDF: the read-only rootfs keeps the package
directory immutable and each run gets a fresh `/tmp` tmpfs, so there is no
writable path to poison.

**Treat a new `pillow` advisory as genuinely relevant.** The container bounds the
blast radius — non-root, `--cap-drop ALL`, `no-new-privileges`, read-only
rootfs, input mounted `:ro`, memory and CPU caps, and a crash dies with the
throwaway container — but it does not prevent the bug.

## When to revisit

Re-read this file whenever `pdf2zh` is bumped, and drop the accepted risk as
soon as the `gradio` pin moves far enough to allow `pillow` 12.3.0.
