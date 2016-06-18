#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [linking zshrc]"
if [ ! -e ~/.zshrc -o ! -L ~/.zshrc ]; then
    rm -f ~/.zshrc
    ln -sf $GPROG_DIR/garaemon-settings/resources/rcfiles/zshrc ~/.zshrc
fi

cyanecho ">>>> [installing auto-fu.zsh]"
if [ ! -e ~/.auto-fu ]; then
    git clone https://github.com/hchbaw/auto-fu.zsh.git ~/.auto-fu
fi
