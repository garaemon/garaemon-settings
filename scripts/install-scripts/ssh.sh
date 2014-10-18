#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

mkdir -p $HOME/.ssh
cyanecho ">>>> [setting up authorized_keys]"
touch ~/.ssh/authorized_keys
curl https://github.com/garaemon.keys >> ~/.ssh/authorized_keys
# run uniq for authorized_keys
cat ~/.ssh/authorized_keys | sort | uniq > /tmp/authorized_keys.temp
cp /tmp/authorized_keys.temp ~/.ssh/authorized_keys
