#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh


cyanecho ">>>> [setup ~/.aspell.conf]"
echo "lang en_US" > $HOME/.aspell.conf
