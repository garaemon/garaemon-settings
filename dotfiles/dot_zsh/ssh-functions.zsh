# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-
# SSH and MOSH related functions

# This MOSH_ESCAPE_KEY setting does not work but it can ignore C-^ escape key
# of mosh.
export MOSH_ESCAPE_KEY="~"

# op-ssh runs ssh using the 1Password SSH agent, regardless of the global
# SSH_AUTH_SOCK. It resolves the 1Password agent socket per OS and overrides
# SSH_AUTH_SOCK for the single invocation.
function op-ssh() {
  local sock
  case "$(uname)" in
    Darwin)
      sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
      ;;
    *)
      sock="$HOME/.1password/agent.sock"
      ;;
  esac
  if [[ ! -S "$sock" ]]; then
    echo "op-ssh: 1Password SSH agent socket not found at: $sock" >&2
    echo "op-ssh: Make sure 1Password is running and its SSH agent is enabled." >&2
    return 1
  fi
  SSH_AUTH_SOCK="$sock" ssh "$@"
}

function ssh-remove-host() {
    local TARGET="$1"
    local KNOWN_HOSTS_FILE="${HOME}/.ssh/known_hosts"
    local RESOLVED_IPS

    # Display usage if no argument is provided
    if [ -z "$TARGET" ]; then
        echo "Usage: remove-ssh-host <hostname_or_ip>"
        echo "Example: remove-ssh-host example.com"
        echo "Example: remove-ssh-host 192.168.1.100"
        return 1
    fi

    echo "Removing ${TARGET} from ${KNOWN_HOSTS_FILE}..."

    # 1. First, attempt to remove the specified hostname or IP directly
    # Redirect stderr to /dev/null to suppress "Host not found" errors
    echo "  - Directly removing: ssh-keygen -R \"${TARGET}\""
    ssh-keygen -R "${TARGET}" 2>/dev/null

    # 2. If the target is a hostname, resolve its IP addresses and attempt to remove them too
    # Use getent hosts to get associated IP addresses (both IPv4 and IPv6) for the hostname.
    # Use awk to extract only the IP address part, filter out comment lines, and sort unique entries.
    # The 'if' condition around RESOLVED_IPS assignment prevents script exit on getent failure
    if RESOLVED_IPS=$(getent hosts "$TARGET" 2>/dev/null | awk '{print $1}' | grep -v '^#' | sort -u); then
        if [ -n "$RESOLVED_IPS" ]; then
            echo "  Attempting to remove IP addresses associated with hostname ${TARGET}..."
            for IP in ${(f)RESOLVED_IPS}; do # Zsh array loop for lines
                # Avoid redundant removal if the resolved IP is the same as the initial target (if target was an IP)
                if [ "$IP" != "$TARGET" ]; then
                    echo "  - Removing associated IP: ssh-keygen -R \"${IP}\""
                    ssh-keygen -R "${IP}" 2>/dev/null
                fi
            done
        else
            # getent hosts succeeded but returned no IPs (e.g., non-existent hostname)
            echo "  No IP addresses associated with hostname ${TARGET} were resolved. Only the directly specified host/IP was processed."
        fi
    else
        # getent hosts command itself failed (e.g., command not found, service not running)
        echo "  Failed to execute 'getent hosts' command. Associated IP addresses will not be removed."
    fi

    echo "Process completed."
}
