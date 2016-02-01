#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh
if [ `uname` == "Linux" ]; then
    if [ ! -e $HOME/.local/bin/emacs ]; then
	cyanecho ">>>> [compiling emacs]"
	cd $GPROG_DIR/emacs
	./autogen.sh && ./configure --prefix=$HOME/.local
	make -j$(grep -c processor /proc/cpuinfo)
	make install
    fi
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
