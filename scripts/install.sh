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
toilet"
runsudo add-apt-repository -y ppa:webupd8team/atom # for atom
runsudo apt-get update
runsudo apt-get install aptitude
runsudo aptitude install $APT_PACKAGES

export GPROG_DIR=$HOME/gprog

GITHUB_REPOSITORIES="icholy/ttygif.git \
garaemon/emacs.d.git \
garaemon/garaemon-settings.git garaemon/rosenv.git \
holman/spark.git joemiller/spark-ping.git seebi/dircolors-solarized.git \
tomislav/osx-terminal.app-colors-solarized.git yonchu/shell-color-pallet.git \
sigurdga/gnome-terminal-colors-solarized.git"
GIT_REPOSITORIS=""

function github_update_clone()
{
    repo=$1
    redecho ">> [installing and updating $repo]"
    DIR_NAME=$(basename $repo .git)
    if [ -e $GPROG_DIR/$DIR_NAME ]; then
        move $GPROG_DIR/$DIR_NAME
        git pull
        git submodule update --init
    else
        move $GPROG_DIR
        git clone git@github.com:$repo
        move $DIR_NAME
        git submodule update --init
    fi
}
export -f github_update_clone

redecho ">> [setting up gprog]"
mkdir -p $GPROG_DIR

echo $GITHUB_REPOSITORIES | xargs -P $(grep -c processor /proc/cpuinfo) --delimiter ' ' -n 1 -I % bash -c "github_update_clone %"


# compiling ttygif
redecho ">> [compiling ttygif...]"
move $GPROG_DIR/ttygif
make

redecho ">> [linking vimrc]"
ln -sf $GRPOG_DIR/garaemon-settings/resources/rcfiles/vimrc ~/.vimrc

redecho ">> [linking tmux.conf]"
ln -sf $GPROG_DIR/garaemon-settings/resources/rcfiles/tmux.conf ~/.tmux.conf

# #################################################
# # setting up git
# #################################################
redecho ">> [installing git commit-msg]"
if [ ! -e /usr/share/git-core/templates/hooks/commit-msg ]; then
    runsudo cp -fv $GPROG_DIR/garaemon-settings/resources/git/commit-msg /usr/share/git-core/templates/hooks
fi

redecho ">> [disabling git ff merge]"
git config --global --add merge.ff false

redecho ">> [installing oh-my-zsh]"
if [ ! -e ~/.oh-my-zsh ]; then
    curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
fi

redecho ">> [linking zshrc]"
if [ ! -e ~/.zshrc ]; then
    ln -sf $GPROG_DIR/garaemon-settings/resources/rcfiles/zshrc ~/.zshrc
fi

redecho ">> [installing nvm]"
if [ ! -e ~/.nvm ]; then
    curl https://raw.github.com/creationix/nvm/master/install.sh | sh
fi

redecho ">> [install node.js]"
source ~/.nvm/nvm.sh; nvm install v0.10.28

redecho ">> [installing rvm]"
if [ ! -e ~/.rvm ]; then
    curl -sSL https://get.rvm.io | bash -s stable
fi

redecho ">> [installing current ruby]"
rvm install current

redecho ">> [settingup .emacs.d]"
if [ ! -e ~/.emacs -o ! -L ~/.emacs ]; then
    rm -rf ~/.emacs
    ln -sf $GPROG_DIR/emacs.d/dot.emacs ~/.emacs
fi
if [ ! -e ~/.emacs.d -o ! -L ~/.emacs.d ]; then
    rm -rf ~/.emacs
    ln -sf $GPROG_DIR/emacs.d ~/.emacs.d
fi

# powerline
