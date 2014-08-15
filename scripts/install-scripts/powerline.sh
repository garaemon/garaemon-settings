#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing powerline]"
pip install --user git+git://github.com/Lokaltog/powerline

cyanecho ">>>> [installing powerline font]"
mkdir -p ~/.fonts
if [ ! -e ~/.fonts/PowerlineSymbols.otf ]; then
    wget https://github.com/Lokaltog/powerline/raw/develop/font/PowerlineSymbols.otf -O ~/.fonts/PowerlineSymbols.otf
    fc-cache -vf ~/.fonts
fi
if [ ! -e ~/.fonts.conf.d/10-powerline-symbols.conf ]; then
    mkdir -p ~/.fonts.conf.d
    wget https://github.com/Lokaltog/powerline/raw/develop/font/10-powerline-symbols.conf -O ~/.fonts.conf.d/10-powerline-symbols.conf
fi
if [ ! -e ~/.config/powerline ]; then
    mkdir -p ~/.config
    ln -sf $GRPOG_DIR/garaemon-settings/resources/powerline ~/.config/powerline
fi
