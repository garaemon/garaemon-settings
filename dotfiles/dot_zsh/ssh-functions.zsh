# -*- mode: shell-script -*-
# -*- coding: utf-8 -*-
# SSH and MOSH related functions

function ssh-with-copy-id() {
  command ssh -o "PasswordAuthentication=no" $1 exit
  if [ $? != "0" ]; then
    echo "Failed to ssh w/o password. Copy id_rsa.pub to the machine."
    ssh-copy-id $1
  fi
  command ssh -o "PasswordAuthentication=no" $@
}

function mosh-with-copy-id() {
  command ssh -o "PasswordAuthentication=no" $1 exit
  if [ $? != "0" ]; then
    echo "Failed to ssh w/o password. Copy id_rsa.pub to the machine."
    ssh-copy-id $1
  fi
  command mosh --ssh='ssh -o "PasswordAuthentication=no"' $@
}

# This MOSH_ESCAPE_KEY setting does not work but it can ignore C-^ escape key
# of mosh.
export MOSH_ESCAPE_KEY="~"

# Change title before mosh for iTerm
# Please uncheck all the check box in Preference > Appearance > Window & Tab Titles
OS=$(uname)
if [ "$OS" = "Darwin" ]; then
  function mosh() {
    echo -ne "\033]0;$@\007"
    mosh-with-copy-id $@
  }
  function ssh() {
    echo -ne "\033]0;$@\007"
    ssh-with-copy-id $@
  }
else
  function mosh() {
    mosh-with-copy-id $@
  }
  function ssh() {
    ssh-with-copy-id $@
  }
fi

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
