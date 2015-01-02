#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing rvm]"
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
if [ ! -e ~/.rvm ]; then
    curl -sSL https://get.rvm.io | bash -s stable
# else
#     rvm get stable
fi
source ~/.rvm/scripts/rvm

cyanecho ">>>> [installing current ruby]"
rvm install ruby-v2.2.0
