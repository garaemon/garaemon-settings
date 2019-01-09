#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh
if [ `uname` == "Linux" ]; then
    sudo add-apt-repository ppa:kelleyk/emacs -y
    sudo apt update
    sudo apt install emacs26 -y
    sudo update-alternatives --set emacs /usr/bin/emacs26
fi

cyanecho ">>>> [installing .emacs]"
if [ ! -e $GPROG_DIR/emacs.d ]; then
    (cd $GPROG_DIR; git clone git@github.com:garaemon/emacs.d.git)
fi

if [ ! -e ~/.emacs -o ! -L ~/.emacs ]; then
    cyanecho ">>>> [linking .emacs]"
    rm -rf ~/.emacs
    ln -sfv $GPROG_DIR/emacs.d/dot.emacs ~/.emacs
fi

cyanecho ">>>> [linking .emacs.d]"
if [ ! -e ~/.emacs.d -o ! -L ~/.emacs.d ]; then
    rm -rf ~/.emacs
    ln -sfv $GPROG_DIR/emacs.d ~/.emacs.d
fi
