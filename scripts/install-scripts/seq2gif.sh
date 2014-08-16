#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh
move $GPROG_DIR/seq2gif

cyanecho ">>>> [building ttygif]"
./configure
make clean
make -j
