#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [linking .percol]"
mkdir -p $HOME/.percol.d
ln -sf $cwd/../../resources/rcfiles/percol_rc.py $HOME/.percol.d/rc.py
