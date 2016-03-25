#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing powerline]"
if [ ! -e $HOME/.pyenv ]; then
    pip install --user git+git://github.com/Lokaltog/powerline
else
    pip install git+git://github.com/Lokaltog/powerline
fi

cyanecho ">>>> [installing powerline font]"
if [ `uname` == "Linux" ]; then
    mkdir -p ~/.fonts
    if [ ! -e ~/.fonts/PowerlineSymbols.otf ]; then
        wget https://github.com/Lokaltog/powerline/raw/develop/font/PowerlineSymbols.otf -O ~/.fonts/PowerlineSymbols.otf
        fc-cache -vf ~/.fonts
    fi
    if [ ! -e ~/.fonts.conf.d/10-powerline-symbols.conf ]; then
        mkdir -p ~/.fonts.conf.d
        wget https://github.com/Lokaltog/powerline/raw/develop/font/10-powerline-symbols.conf -O ~/.fonts.conf.d/10-powerline-symbols.conf
    fi
fi

mkdir -p ~/.config
ln -sf $GPROG_DIR/garaemon-settings/resources/powerline ~/.config/powerline
