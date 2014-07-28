#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

ln -sf $GRPOG_DIR/garaemon-settings/resources/rcfiles/vimrc ~/.vimrc
