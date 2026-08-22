---
paths:
  - "**/*.sh"
  - "**/*.bash"
---

# Shell Script Rules

Apply these rules when creating or editing shell scripts (`*.sh`, `*.bash`).

- Place `set -euo pipefail` at the very top of the script, right after the shebang.
- The script must pass `shellcheck` with no warnings.
- Use `#!/bin/bash` as the shebang unless another interpreter is explicitly requested.
- Always quote variable expansions (e.g. `"$var"`, `"${arr[@]}"`) to prevent word splitting and globbing.
