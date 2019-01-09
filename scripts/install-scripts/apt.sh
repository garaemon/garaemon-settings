#!/bin/bash
cwd=$(dirname "${0}")
expr "${0}" : "/.*" > /dev/null || cwd=$(cd "${cwd}" && pwd)

# shellcheck source=../lib.sh disable=SC1091
source "${cwd}"/../lib.sh

APT_PACKAGES="ttyrec git-core vim tmux anthy-el ssh zsh curl htop \
toilet ffmpeg jq tcpflow quicksynergy \
python-pip build-essential man \
texinfo libncurses5-dev libgtk2.0-dev libgif-dev \
libjpeg-dev libpng-dev libxpm-dev libtiff4-dev \
libxml2-dev librsvg2-dev libotf-dev libm17n-dev \
libgpm-dev libgnutls-dev libgconf2-dev libdbus-1-dev glc \
r-base ess rlwrap golang xclip w3m libzlma-dev quicksynergy \
compizconfig-settings-manager imagemagick libicu-dev conky conky-all \
silversearcher-ag"

runsudo apt-get --quiet update
runsudo apt-get --quiet install aptitude
runsudo aptitude -q -y upgrade
cyanecho ">>>> [instal packages]"
runsudo aptitude -q -y install "$APT_PACKAGES"
