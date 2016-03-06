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

# need to install sudo and apt-utils python-software-properties

redecho ">> [setting up gprog]"
mkdir -p $GPROG_DIR
if [ `uname` == "Linux" ]; then
    runscript apt.sh
fi
if [ `uname` == "Darwin" ]; then
    runscript brew.sh
fi
runscript ssh.sh
runscript github.sh
if [ `uname` == "Linux" ]; then
    runscript ttygif.sh
fi
runscript vimrc.sh
runscript tmux.sh
runscript git.sh
runscript zsh.sh

#runscript go.sh
# runscript hub.sh
if [ `uname` == "Linux" ]; then
    runscript ruby.sh
    source ~/.rvm/scripts/rvm
fi

runscript ispell.sh
runscript emacs.sh
runscript powerline.sh
runscript pip.sh
runscript percol.sh
runscript font.sh
if [ `uname` == "Linux" ]; then
    runscript ros.sh
fi
runscript node.sh
source ~/.nvm/nvm.sh
