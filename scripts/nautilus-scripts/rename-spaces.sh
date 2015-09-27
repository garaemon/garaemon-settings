#!/bin/bash
# mkdir -p ~/.local/share/nautilus/scripts/
# cp rename-spaces.sh ~/.local/share/nautilus/scripts/
# mkdir -p ~/.gnome2/nautilus-scripts
# cp rename-spaces.sh ~/.gnome2/nautilus-scripts
mv -i "$*" "$(echo ${NAUTILUS_SCRIPT_SELECTED_FILE_PATHS} | sed -e 's/\s\+/_/g')"
exit0
