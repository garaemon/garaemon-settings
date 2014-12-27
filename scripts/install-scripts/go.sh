#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing gvm]"
wget https://raw.github.com/moovweb/gvm/master/binscripts/gvm-installer -O - -q | bash

source ~/.gvm/scripts/gvm
cyanecho ">>>> [building go 1.4]"
gvm install go1.4
