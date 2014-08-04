#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh
move $GPROG_DIR/ttygif

cyanecho ">>>> [building ttygif]"
make
