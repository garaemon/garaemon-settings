#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

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
