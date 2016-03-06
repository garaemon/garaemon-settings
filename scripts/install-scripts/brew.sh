#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

# install homebrew itself
which brew > /dev/null
if [ -n $? ] ; then
    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi

cyanecho ">>>> install homebrew software"
brew install tmux wget w3m findutils imagemagick gnu-sed coreutils

cyanecho ">>>> install emacs"
brew install emacs --with-cocoa
brew linkapps emacs

cyanecho ">>>> enabling cask"
brew tap caskroom/cask

brew cask install hyperswitch google-chrome kindle dropbox unity
