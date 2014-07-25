#!/bin/bash
set -e
# install.sh

function move()
{
    cd $1 > /dev/null
}

function redecho()
{
    echo -e "\e[1;31m" $1 "\e[m"
}

function cyanecho()
{
    echo -e "\e[36m" $1 "\e[m"
}

function yellowecho()
{
    echo -e "\e[33m" $1 "\e[m"
}


function runsudo()
{
    if [ "$NO_SUDO" != "true" ]; then
        sudo sh -c "$*"
    else
        yellowecho "[NO_SUDO=true] skipping $*"
    fi
}

export -f move
export -f redecho

RUN_APT=true
APT_PACKAGES="ttyrec git-core emacs vim tmux anthy-el ssh zsh curl htop atom \
toilet autoconf automake build-essential libass-dev libfreetype6-dev \
libgpac-dev libsdl1.2-dev libtheora-dev libtool libva-dev libvdpau-dev \
libvorbis-dev libx11-dev libxext-dev libxfixes-dev pkg-config texi2html \
zlib1g-dev yasm libmp3lame-dev libopus-dev"
runsudo add-apt-repository -y ppa:webupd8team/atom # for atom
runsudo apt-get update
runsudo apt-get install aptitude
runsudo aptitude install $APT_PACKAGES

export GPROG_DIR=$HOME/gprog

# GITHUB_REPOSITORIES="icholy/ttygif.git \
# garaemon/emacs.d.git \
# garaemon/garaemon-settings.git garaemon/rosenv.git \
# holman/spark.git joemiller/spark-ping.git seebi/dircolors-solarized.git \
# tomislav/osx-terminal.app-colors-solarized.git yonchu/shell-color-pallet.git \
# sigurdga/gnome-terminal-colors-solarized.git"
# GIT_REPOSITORIS=""

# function github_update_clone()
# {
#     repo=$1
#     redecho ">> [installing and updating $repo]"
#     DIR_NAME=$(basename $repo .git)
#     if [ -e $GPROG_DIR/$DIR_NAME ]; then
#         move $GPROG_DIR/$DIR_NAME
#         git pull
#         git submodule update --init
#     else
#         move $GPROG_DIR
#         git clone git@github.com:$repo
#         move $DIR_NAME
#         git submodule update --init
#     fi
# }
# export -f github_update_clone

# redecho ">> [setting up gprog]"
# mkdir -p $GPROG_DIR

# echo $GITHUB_REPOSITORIES | xargs -P $(grep -c processor /proc/cpuinfo) --delimiter ' ' -n 1 -I % bash -c "github_update_clone %"


# # compiling ttygif
# redecho ">> [compiling ttygif...]"
# move $GPROG_DIR/ttygif
# make

# redecho ">> [linking vimrc]"
# ln -sf $GRPOG_DIR/garaemon-settings/resources/rcfiles/vimrc ~/.vimrc

# redecho ">> [linking tmux.conf]"
# ln -sf $GPROG_DIR/garaemon-settings/resources/rcfiles/tmux.conf ~/.tmux.conf

# # #################################################
# # # setting up git
# # #################################################
# redecho ">> [installing git commit-msg]"
# if [ ! -e /usr/share/git-core/templates/hooks/commit-msg ]; then
#     runsudo cp -fv $GPROG_DIR/garaemon-settings/resources/git/commit-msg /usr/share/git-core/templates/hooks
# fi

# redecho ">> [disabling git ff merge]"
# git config --global --add merge.ff false

# redecho ">> [installing oh-my-zsh]"
# if [ ! -e ~/.oh-my-zsh ]; then
#     curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
# fi

# redecho ">> [linking zshrc]"
# if [ ! -e ~/.zshrc -o ! -L ~/.zshrc ]; then
#     rm -f ~/.zshrc
#     ln -sf $GPROG_DIR/garaemon-settings/resources/rcfiles/zshrc ~/.zshrc
# fi

# redecho ">> [installing nvm]"
# if [ ! -e ~/.nvm ]; then
#     curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | sh
# fi
# source ~/.nvm/nvm.sh

# redecho ">> [install node.js v0.10.28]"
# nvm install v0.10.28

# redecho ">> [installing rvm]"
# if [ ! -e ~/.rvm ]; then
#     curl -sSL https://get.rvm.io | bash -s stable
# # else
# #     rvm get stable
# fi
# source ~/.rvm/scripts/rvm

# redecho ">> [installing current ruby]"
# rvm install current

# redecho ">> [settingup .emacs.d]"
# if [ ! -e ~/.emacs -o ! -L ~/.emacs ]; then
#     rm -rf ~/.emacs
#     ln -sf $GPROG_DIR/emacs.d/dot.emacs ~/.emacs
# fi
# if [ ! -e ~/.emacs.d -o ! -L ~/.emacs.d ]; then
#     rm -rf ~/.emacs
#     ln -sf $GPROG_DIR/emacs.d ~/.emacs.d
# fi

# # powerline
# redecho ">> [installing powerline]"
# pip install --user git+git://github.com/Lokaltog/powerline

# redecho ">> [installing powerline font]"
# mkdir -p ~/.fonts
# wget https://github.com/Lokaltog/powerline/raw/develop/font/PowerlineSymbols.otf -O ~/.fonts/PowerlineSymbols.otf
# fc-cache -vf ~/.fonts
# mkdir -p ~/.fonts.conf.d
# wget https://github.com/Lokaltog/powerline/raw/develop/font/10-powerline-symbols.conf -O ~/.fonts.conf.d/10-powerline-symbols.conf
# mkdir -p ~/.config
# ln -sf $GRPOG_DIR/garaemon-settings/resources/powerline ~/.config/powerline

redecho ">> [installing ffmpeg from source]"
FFMPEG_SOURCE_DIR=$GPROG_DIR/ffmpeg-source
FFMPEG_BUILD_DIR=$GPROG_DIR/ffmpeg-source/ffmpeg_build
FFMPEG_BIN_DIR=$GPROG_DIR/ffmpeg-source/bin
mkdir -p $FFMPEG_SOURCE_DIR

redecho ">>   [compiling yasm]"
cd $FFMPEG_SOURCE_DIR
wget -N http://www.tortall.net/projects/yasm/releases/yasm-1.2.0.tar.gz
tar xzvf yasm-1.2.0.tar.gz
cd yasm-1.2.0
./configure --prefix="$FFMPEG_BUILD_DIR" --bindir="$FFMPEG_BIN_DIR"
make -j
make install
make distclean

redecho ">>   [compiling x264]"
cd $FFMPEG_SOURCE_DIR
wget -N http://download.videolan.org/pub/x264/snapshots/last_x264.tar.bz2
tar xjvf last_x264.tar.bz2
cd x264-snapshot*
PATH="$FFMPEG_BIN_DIR:$PATH" ./configure --prefix="$FFMPEG_BUILD_DIR" --bindir="$FFMPEG_BIN_DIR" --enable-static
PATH="$FFMPEG_BIN_DIR:$PATH" make -j
make install
make distclean

redecho ">>   [compiling libfdk-aac]"
cd $FFMPEG_SOURCE_DIR
wget -O fdk-aac.zip https://github.com/mstorsjo/fdk-aac/zipball/master
unzip fdk-aac.zip
cd mstorsjo-fdk-aac*
autoreconf -fiv
./configure --prefix="$FFMPEG_BUILD_DIR" --disable-shared
make -j
make install
make distclean

redecho ">>   [compiling liopus]"
cd $FFMPEG_SOURCE_DIR
wget -N http://downloads.xiph.org/releases/opus/opus-1.1.tar.gz
tar xzvf opus-1.1.tar.gz
cd opus-1.1
./configure --prefix="$FFMPEG_BUILD_DIR" --disable-shared
make -j
make install
make distclean

redecho ">>   [compiling libvpx]"
cd $FFMPEG_SOURCE_DIR
wget -N http://webm.googlecode.com/files/libvpx-v1.3.0.tar.bz2
tar xjvf libvpx-v1.3.0.tar.bz2
cd libvpx-v1.3.0
./configure --prefix="$FFMPEG_BUILD_DIR" --disable-examples
make -j
make install
make clean

redecho ">>   [compiling ffmpeg]"
cd $FFMPEG_SOURCE_DIR
wget -N http://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2
tar xjvf ffmpeg-snapshot.tar.bz2
cd ffmpeg
PATH="$FFMPEG_BIN_DIR:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure \
  --prefix="$FFMPEG_BUILD_DIR" \
  --extra-cflags="-I$FFMPEG_BUILD_DIR/include" \
  --extra-ldflags="-L$FFMPEG_BUILD_DIR/lib" \
  --bindir="$FFMPEG_BIN_DIR" \
  --extra-libs="-ldl" \
  --enable-gpl \
  --enable-libass \
  --enable-libfdk-aac \
  --enable-libfreetype \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libtheora \
  --enable-libvorbis \
  --enable-libvpx \
  --enable-libx264 \
  --enable-nonfree \
  --enable-x11grab
PATH="$FFMPEG_BIN_DIR:$PATH" make -j
make install
make distclean
