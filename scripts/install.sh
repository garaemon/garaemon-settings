#!/bin/bash
set -e
# install.sh

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/lib.sh

function runscript()
{
    redecho ">> running [$1]"
    $cwd/install-scripts/$1
}


redecho ">> [setting up gprog]"
mkdir -p $GPROG_DIR

runscript apt.sh
runscript github.sh
runscript ttygif.sh
runscript vimrc.sh
runscript tmux.sh
runscript git.sh
runscript zsh.sh
runscript node.sh
source ~/.nvm/nvm.sh
runscript ruby.sh
source ~/.rvm/scripts/rvm
runscript emacs.sh
# powerline
runscript powerline.sh
runscript ros.sh
