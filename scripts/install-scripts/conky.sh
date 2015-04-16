#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

# Update .conky directory
if [ ! -e $HOME/.conky ] ; then
    cyanecho ">>>> [installing .conky]"
    cp -r $GPROG_DIR/ConkyInfinitySVG/.conky $HOME/.conky
fi

if [ ! -e $HOME/.conkyrc ] ; then
    cyanecho ">>>> [installing .conkyrc]"
    cp -r $GPROG_DIR/garaemon-settings/resources/rcfiles/conkyrc $HOME/.conkyrc
    # Update window size
    size=$(xrandr | grep '*+' | head -n 1 | awk '{print $1}')
    width=$(echo $size |cut -f1 -dx)
    height=$(echo $size |cut -f2 -dx)
    sed -i -e "1i minimum_size $width $height" $HOME/.conkyrc
fi
