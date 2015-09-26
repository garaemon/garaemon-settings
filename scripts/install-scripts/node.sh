#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh
packages="shiba prettyjson npm-check"

cyanecho ">>>> [installing nvm]"
if [ ! -e ~/.nvm ]; then
    curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | sh
fi
source ~/.nvm/nvm.sh
cyanecho ">>>> [install node.js v0.10.28]"
nvm install v0.10.28

npm install -g $packages
