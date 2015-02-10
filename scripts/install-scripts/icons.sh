#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

mkdir -p $HOME/.config/gnome-panel/launchers

if [ ! -e "$HOME/.config/gnome-panel/launchers/rqt_reconfigure.desktop" ]; then
    cyanecho ">>>> [generating rqt_reconfigure icon]"
    cat <<EOF > "$HOME/.config/gnome-panel/launchers/rqt_reconfigure.desktop"
#!/usr/bin/env xdg-open
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Icon[en_US]=ccsm
Name[en_US]=rqt_reconfigure
Exec=$HOME/gprog/garaemon-settings/scripts/run-ros.sh rqt_reconfigure rqt_reconfigure
Name=rqt_reconfigure
Icon=ccsm
EOF
    chmod +x $HOME/.config/gnome-panel/launchers/rqt_reconfigure.desktop
fi

if [ ! -e "$HOME/.config/gnome-panel/launchers/rqt_image_view.desktop" ]; then
    cyanecho ">>>> [generating rqt_image_view icon]"
    cat <<EOF > "$HOME/.config/gnome-panel/launchers/rqt_image_view.desktop"
#!/usr/bin/env xdg-open
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Icon[en_US]=remmina
Name[en_US]=rqt_image_view
Exec=$HOME/gprog/garaemon-settings/scripts/run-ros.sh rqt_image_view rqt_image_view
Name=rqt_image_view
Icon=remmina
EOF
    chmod +x $HOME/.config/gnome-panel/launchers/rqt_image_view.desktop
fi

if [ ! -e "$HOME/.config/gnome-panel/launchers/TogglDesktop.desktop" ]; then
    cyanecho ">>>> [generating toggl desktop]"
    cat <<EOF > $HOME/.config/gnome-panel/launchers/TogglDesktop.desktop
#!/usr/bin/env xdg-open
[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Icon[en_US]=gnome-panel-clock
Name[en_US]=Toggl
Exec=$HOME/.local/toggl/TogglDesktop
Name=Toggl
Icon=gnome-panel-clock

EOF
    chmod +x $HOME/.config/gnome-panel/launchers/TogglDesktop.desktop
fi
if [ ! -e "$HOME/.config/gnome-panel/launchers/emacs.desktop" ]; then
    cyanecho ">>>> [generating emacs desktop]"
    cat <<EOF > $HOME/.config/gnome-panel/launchers/emacs.desktop
[Desktop Entry]
Name=Emacs
GenericName=Text Editor
Comment=Edit text
MimeType=text/english;text/plain;text/x-makefile;text/x-c++hdr;text/x-c++src;text/x-chdr;text/x-csrc;text/x-java;text/x-moc;text/x-pascal;text/x-tcl;text/x-tex;application/x-shellscript;text/x-c;text/x-c++;
Exec=$HOME/.local/bin/emacs %F
Icon=emacs
Type=Application
Terminal=false
Categories=Development;TextEditor;
StartupWMClass=Emacs
EOF
    chmod +x $HOME/.config/gnome-panel/launchers/emacs.desktop
fi

xdg-open $HOME/.config/gnome-panel/launchers
