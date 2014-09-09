#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

APT_PACKAGES="ttyrec git-core vim tmux anthy-el ssh zsh curl htop atom \
toilet ffmpeg jq tcpflow quicksynergy emacs24 emacs24-el emacs24-common-non-dfsg"

cyanecho ">>>> [add apt repository for atom]"
runsudo add-apt-repository -y ppa:webupd8team/atom # for atom
cyanecho ">>>> [add apt repository for ffmpeg]"
runsudo add-apt-repository -y ppa:jon-severinsson/ffmpeg
cyanecho ">>>> [add emacs24 repository]"
runsudo add-apt-repository -y ppa:cassou/emacs
runsudo apt-get --quiet update
runsudo apt-get --quiet install aptitude
runsudo aptitude -q -y upgrade
cyanecho ">>>> [instal packages]"
runsudo aptitude -q -y install $APT_PACKAGES
