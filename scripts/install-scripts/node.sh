#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh
target_node_version=v5.7.0
packages="shiba prettyjson npm-check yo bower grunt-cli gulp generator-electron babel-cli"

cyanecho ">>>> [installing nvm]"
if [ ! -e ~/.nvm ]; then
    curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | sh
fi
source ~/.nvm/nvm.sh
cyanecho ">>>> [install node.js ${target_node_version}]"
nvm install ${target_node_version}
cyanecho ">>>> [install npm packages]"
npm install -g $packages
