#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

APT_PACKAGES="ttyrec git-core vim tmux anthy-el ssh zsh curl htop atom \
toilet ffmpeg jq tcpflow quicksynergy emacs24 emacs24-el emacs24-common-non-dfsg \
python-pip build-essential man \
texinfo libncurses5-dev libgtk2.0-dev libgif-dev \
libjpeg-dev libpng-dev libxpm-dev libtiff4-dev \
libxml2-dev librsvg2-dev libotf-dev libm17n-dev \
libgpm-dev libgnutls-dev libgconf2-dev libdbus-1-dev glc"

cyanecho ">>>> [add apt repository for atom]"
runsudo add-apt-repository -y ppa:webupd8team/atom # for atom
cyanecho ">>>> [add apt repository for ffmpeg]"
runsudo add-apt-repository -y ppa:jon-severinsson/ffmpeg
cyanecho ">>>> [add emacs24 repository]"
runsudo add-apt-repository -y ppa:cassou/emacs
cyanecho ">>>> [add glc repository]"
sudo add-apt-repository -y ppa:arand/ppa


runsudo apt-get --quiet update
runsudo apt-get --quiet install aptitude
runsudo aptitude -q -y upgrade
cyanecho ">>>> [instal packages]"
runsudo aptitude -q -y install $APT_PACKAGES
