#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

if [ ! -e ~/.local/bin/hub ]; then
    cyanecho ">>>> [installing hub binary]"
    wget https://github.com/github/hub/releases/download/v2.2.0/hub-linux-amd64-2.2.0.tar.gz -O /tmp/hub.tar.gz -q
    cd /tmp
    tar xvzf hub.tar.gz
    mv hub-linux*/hub ~/.local/bin/hub
fi
