#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh
cd ~
if [ ! -e $HOME/prog ]; then
   cyanecho ">>>> [creating ~/prog]"
   svn co -N svn+ssh://ueda@aries.jsk.t.u-tokyo.ac.jp/home/jsk/svn/trunk prog
fi

cd ~/prog
cyanecho ">>>> [updating scripts and euslib]"
svn up scripts euslib > /dev/null
cd ~/prog/scripts

cyanecho ">>>> [Updating OpenHRP]"
./jsk-svn-co.sh openhrp
