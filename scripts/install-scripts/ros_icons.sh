#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

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
Exec=/opt/ros/hydro/lib/rqt_reconfigure/rqt_reconfigure
Name=rqt_reconfigure
Icon=ccsm
EOF
    chmod +x $HOME/.config/gnome-panel/launchers/rqt_reconfigure.desktop
fi
