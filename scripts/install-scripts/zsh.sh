#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing oh-my-zsh]"
if [ ! -e ~/.oh-my-zsh ]; then
    curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
fi

cyanecho ">>>> [linking zshrc]"
if [ ! -e ~/.zshrc -o ! -L ~/.zshrc ]; then
    rm -f ~/.zshrc
    ln -sf $GPROG_DIR/garaemon-settings/resources/rcfiles/zshrc ~/.zshrc
fi
