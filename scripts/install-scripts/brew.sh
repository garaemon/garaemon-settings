#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> install gnu utilities"
brew install gnu-sed coreutils

brew install tmux wget w3m findutils

cyanecho ">>>> install emacs"
brew install emacs --with-cocoa
brew linkapps emacs

cyanecho ">>>> enabling cask"
brew tap caskroom/cask

brew cask install hyperswitch google-chrome kindle dropbox
