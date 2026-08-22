# Repository scripts

## `gws-secure` — token-less Google Workspace CLI

`gws-secure` wraps the [`gws`](https://www.npmjs.com/package/@googleworkspace/cli)
Google Workspace CLI so that **no OAuth token is ever written to disk**.

Normally `gws` persists an encrypted refresh token and an access-token cache
under `~/.config/gws`. `gws-secure` instead keeps the OAuth client and refresh
token in 1Password and mints a short-lived access token in memory on every
call:

1. Read `client_secret.json` and the `refresh_token` field from the 1Password
   item (in memory only).
2. Exchange the refresh token for a short-lived access token via Google's token
   endpoint (in memory only).
3. Run the real `gws` with that access token supplied through
   `GOOGLE_WORKSPACE_CLI_TOKEN`. In this mode `gws` writes only the non-secret
   API discovery schema cache to `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`
   (default `~/.cache/gws-secure`) — never a credential.

### Prerequisites

- `op` (1Password CLI), signed in.
- `gws`, `curl`, and `jq` on `PATH`. `gws` is the `@googleworkspace/cli` npm
  package; install it globally with `npm install -g @googleworkspace/cli`.
- A 1Password item (default title `googleworkspace cli` in the `Private` vault)
  holding the OAuth desktop client as a `client_secret.json` document.

### One-time setup

Run the bootstrap once. It performs the standard installed-app loopback OAuth
flow in your browser and stores the resulting refresh token back into the same
1Password item as a concealed `refresh_token` field:

```bash
scripts/gws-secure-bootstrap
```

### Usage

`gws-secure` takes the exact same arguments as `gws`:

```bash
scripts/gws-secure gmail users getProfile --params '{"userId":"me"}'
```

Put it on your `PATH` (e.g. symlink into `~/.local/bin`) to call it as
`gws-secure` from anywhere.

### Configuration

All optional, via environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `GWS_SECURE_OP_ITEM` | `googleworkspace cli` | 1Password item title |
| `GWS_SECURE_OP_VAULT` | `Private` | 1Password vault |
| `GWS_SECURE_REFRESH_FIELD` | `refresh_token` | field label of the stored token |
| `GWS_SECURE_SCOPES` | current `gws` scopes | OAuth scopes (bootstrap only) |
| `GWS_SECURE_CACHE_DIR` | `~/.cache/gws-secure` | schema cache dir (non-secret) |
| `GWS_SECURE_GWS_BIN` | `gws` | path to the real `gws` binary |

### Tests

`scripts/tests/gws-secure-smoke.sh` covers the deterministic dependency-check
failure path (no network, 1Password, or browser needed). The OAuth and
1Password paths are verified live during bootstrap and first use.
