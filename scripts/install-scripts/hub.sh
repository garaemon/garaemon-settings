#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

source ~/.gvm/scripts/gvm
cyanecho ">>>> [building hub]"

gvm use go1.4
(cd $GPROG_DIR/hub && ./script/build && mkdir -p ~/.bin && cp hub ~/.bin)

cyanecho ">>>> [building setup completion]"
mkdir -p ~/.zsh_fpath/
cp ~/gprog/hub/etc/hub.zsh_completion ~/.zsh_fpath/_hub
