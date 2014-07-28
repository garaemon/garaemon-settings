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


redecho ">> [setting up gprog]"
mkdir -p $GPROG_DIR

runscript apt.sh
runscript github.sh
runscript ttygif.sh
runscript vimrc.sh
runscript tmux.sh
runscript git.sh
runscript zsh.sh
runscript node.sh
source ~/.nvm/nvm.sh


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
