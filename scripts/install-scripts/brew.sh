#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

HOMEBREW_RB_PATH="https://raw.githubusercontent.com/Homebrew/install/master/install"

# install homebrew itself
if ! which brew > /dev/null ; then
    /usr/bin/ruby -e "$(curl -fsSL ${HOMEBREW_RB_PATH})"
fi

cyanecho ">>>> install homebrew software"
brew install tmux wget w3m findutils imagemagick gnu-sed coreutils cowsay \
     hub ag hg clang-format shellcheck

cyanecho ">>>> install ffmpeg on homebrew"
brew install ffmpeg --with-fdk-aac --with-ffplay --with-freetype \
     --with-libass --with-libquvi --with-libvorbis --with-libvpx --with-opus --with-x265


cyanecho ">>>> install emacs"
brew install emacs --with-cocoa
brew linkapps emacs

cyanecho ">>>> enabling cask"
brew tap caskroom/cask

if [ ! $(sw_vers -productVersion | grep 10.12)] ; then
    brew cask install karabiner hyperswitch
fi
brew cask install google-chrome kindle dropbox vlc skype google-japanese-ime libreoffice \
     meshlab
