#!/bin/bash
# mkdir -p ~/.local/share/nautilus/scripts/
# cp rename-spaces.sh ~/.local/share/nautilus/scripts/
# mkdir -p ~/.gnome2/nautilus-scripts
# cp rename-spaces.sh ~/.gnome2/nautilus-scripts
IFS="
"
for f in $NAUTILUS_SCRIPT_SELECTED_FILE_PATHS
do
    mv -i "$f" "$(echo $f | sed -e 's/\s\+/_/g')"
done
exit
