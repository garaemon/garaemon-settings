#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

PACKAGES="travis github-pages"
RUBY_VERSION="ruby-2.2.0"
cyanecho ">>>> [installing rvm]"

if [ ! -e ~/.rvm ]; then
    gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
    curl -sSL https://get.rvm.io | bash -s stable
# else
#     rvm get stable
fi
source ~/.rvm/scripts/rvm

cyanecho ">>>> [installing current ruby]"
rvm install $RUBY_VERSION
rvm use $RUBY_VERSION


cyanecho ">>>> [installing $PACKAGES]"
gem install $PACKAGES
