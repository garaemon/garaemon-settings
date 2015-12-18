#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing gvm]"
python -c "import urllib2; print urllib2.urlopen('http://git.io/govm').read()" | python - setup

# source ~/.gvm/scripts/gvm
# cyanecho ">>>> [building go 1.4]"
# gvm install go1.4
