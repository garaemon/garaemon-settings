#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [link .atom]"
ln -sf $GPROG_DIR/garaemon-settings/resources/atom $HOME/.atom
