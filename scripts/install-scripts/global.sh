#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

wget --timestamping http://tamacom.com/global/global-6.3.3.tar.gz -O /tmp/global.tar.gz
cd /tmp
tar xvzf global.tar.gz
cd global-6.3.3
./configure --prefix=$HOME/.local
make -j$(grep -c processor /proc/cpuinfo)
make install
cp ~/.local/share/gtags/gtags.conf ~/.globalrc

if [ -e $HOME/ros/hydro ]; then
    cd $HOME/ros/hydro/src
    gtags --gtagslabel=pygments --debug
fi
