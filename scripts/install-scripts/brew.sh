#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> install gnu utilities"
brew install gnu-sed coreutils

brew install tmux

cyanecho ">>>> install emacs"
brew install emacs --cocoa
brew linkapps emacs
