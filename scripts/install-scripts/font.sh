#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

mkdir -p ~/.fonts
if [ -e $GPROG_DIR/RictyDiminished ]; then
    cp $GPROG_DIR/RictyDiminished/*.ttf ~/.fonts/
    runsudo fc-cache -vf
fi
