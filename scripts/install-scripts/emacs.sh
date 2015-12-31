#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

if [ ! -e $HOME/.local/bin/emacs ]; then
    cyanecho ">>>> [compiling emacs]"
    cd $GPROG_DIR/emacs
    ./autogen.sh && ./configure --prefix=$HOME/.local
    make -j$(grep -c processor /proc/cpuinfo)
    make install
fi

cyanecho ">>>> [linking .emacs]"
if [ ! -e ~/.emacs -o ! -L ~/.emacs ]; then
    rm -rf ~/.emacs
    ln -sf $GPROG_DIR/emacs.d/dot.emacs ~/.emacs
fi
cyanecho ">>>> [linking .emacs.d]"
if [ ! -e ~/.emacs.d -o ! -L ~/.emacs.d ]; then
    rm -rf ~/.emacs
    ln -sf $GPROG_DIR/emacs.d ~/.emacs.d
fi
