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
fi
