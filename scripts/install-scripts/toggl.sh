#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

if [ $(uname) = "Linux" ]; then
    if [ ! -e "$HOME/.local/toggl" ]; then
        cyanecho ">>>> [installing toggl desktop]"
        wget https://toggl.com/api/v8/installer\?app\=td\&platform\=linux\&channel\=stable -O /tmp/toggle.tar.gz
        tar xvzf /tmp/toggle.tar.gz -C /tmp
        mv /tmp/toggldesktop ~/.local/toggl
    fi
    # generate .desktop
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
Exec=~/.local/toggl/TogglDesktop
Name=Toggl
Icon=gnome-panel-clock

EOF
        chmod +x $HOME/.config/gnome-panel/launchers/TogglDesktop.desktop
    fi
fi
