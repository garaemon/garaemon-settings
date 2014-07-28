#!/bin/bash
set -e
# install.sh

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/lib.sh

function runscript()
{
    redecho ">> running [$1]"
    $cwd/install-scripts/$1
}

runscript apt.sh

redecho ">> [setting up gprog]"
mkdir -p $GPROG_DIR

runscript github.sh

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
if [ ! -e ~/.zshrc -o ! -L ~/.zshrc ]; then
    rm -f ~/.zshrc
    ln -sf $GPROG_DIR/garaemon-settings/resources/rcfiles/zshrc ~/.zshrc
fi

redecho ">> [installing nvm]"
if [ ! -e ~/.nvm ]; then
    curl https://raw.githubusercontent.com/creationix/nvm/master/install.sh | sh
fi
source ~/.nvm/nvm.sh

redecho ">> [install node.js v0.10.28]"
nvm install v0.10.28

redecho ">> [installing rvm]"
if [ ! -e ~/.rvm ]; then
    curl -sSL https://get.rvm.io | bash -s stable
# else
#     rvm get stable
fi
source ~/.rvm/scripts/rvm

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
redecho ">> [installing powerline]"
pip install --user git+git://github.com/Lokaltog/powerline

redecho ">> [installing powerline font]"
mkdir -p ~/.fonts
wget https://github.com/Lokaltog/powerline/raw/develop/font/PowerlineSymbols.otf -O ~/.fonts/PowerlineSymbols.otf
fc-cache -vf ~/.fonts
mkdir -p ~/.fonts.conf.d
wget https://github.com/Lokaltog/powerline/raw/develop/font/10-powerline-symbols.conf -O ~/.fonts.conf.d/10-powerline-symbols.conf
mkdir -p ~/.config
ln -sf $GRPOG_DIR/garaemon-settings/resources/powerline ~/.config/powerline
