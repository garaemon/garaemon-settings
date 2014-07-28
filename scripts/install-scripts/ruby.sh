#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing rvm]"
if [ ! -e ~/.rvm ]; then
    curl -sSL https://get.rvm.io | bash -s stable
# else
#     rvm get stable
fi
source ~/.rvm/scripts/rvm

cyanecho ">>>> [installing current ruby]"
rvm install current
