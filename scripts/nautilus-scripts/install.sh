#!/bin/bash

# Install scripts under ~/.gnome2/nautilus-scripts or ~/.local/share/nautilus/scripts/
script_dir=$(cd $(dirname $BASH_SOURCE); pwd)
scripts="rename-spaces.sh"

for s in $scripts
do
    ln -sf ${script_dir}/${s} ~/.gnome2/nautilus-scripts
done
