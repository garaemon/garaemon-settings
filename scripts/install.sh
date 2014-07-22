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

export -f move
export -f redecho

RUN_APT=true
APT_PACKAGES="ttyrec git-core emacs vim tmux anthy-el ssh zsh curl htop"
sudo apt-get install aptitude
sudo aptitude install $APT_PACKAGES

export GPROG_DIR=$HOME/gprog
GITHUB_REPOSITORIES="icholy/ttygif.git garaemon/emacs.d.git \
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

echo $GITHUB_REPOSITORIES | xargs -P $(grep -c processor /proc/cpuinfo) --delimiter ' ' -n 1 -I % bash -c "github_update_clone %"


# compiling ttygif
redecho ">> [compiling ttygif...]"
move $GPROG_DIR/ttygif
make

redecho ">> [linking vimrc]"
#################################################
# setting up vim
#################################################
ln -sf $GRPOG_DIR/garaemon-settings/resources/rcfiles/vimrc ~/.vimrc


# #################################################
# # setting up git
# #################################################
# echo installing commit-msg
# sudo cp -fv resources/git/commit-msg /usr/share/git-core/templates/hooks

# echo disabling git ff
# git config --global --add merge.ff false

# #################################################
# # setting up zsh
# #################################################

# # oh-my-zsh
# curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
# if [ ! -e ~/.zshrc ]; then
#     ln -sf $PWD/resources/rcfiles/zshrc ~/.zshrc
# fi

# #################################################
# # setting up nvm
# #################################################
# curl https://raw.github.com/creationix/nvm/master/install.sh | sh

# #################################################
# # setting up rvm
# #################################################
# curl -sSL https://get.rvm.io | bash -s stable

# #################################################
# # setting up tmux
# #################################################
# echo installing .tmux.conf
# cp -v resources/rcfiles/tmux.conf ~/.tmux.conf

# #################################################
# # setting up emacs
# #################################################
# cd ~/gprog
# rm -rf ~/.emacs ~/.emacs.d     # uninstalling .emacs
# if [ ! -d ~/gprog/emacs.d ]; then
#     git clone https://github.com/garaemon/emacs.d.git
# fi

# cd emacs.d
# git submodule update --init .
# ./install.sh
