#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

PACKAGES="travis github-pages"
RUBY_VERSION="ruby-2.6.0"
cyanecho ">>>> [installing rvm]"

if [ ! -e ~/.rvm ]; then
    curl -sSL https://rvm.io/mpapis.asc | gpg2 --import -
    curl -sSL https://rvm.io/pkuczynski.asc | gpg2 --import -
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

