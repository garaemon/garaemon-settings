#!/bin/sh
set -e
# install.sh

# packages
sudo apt-get install aptitude
sudo aptitude install git-core emacs vim tmux anthy-el ssh zsh curl

#################################################
# setting up git
#################################################
echo installing commit-msg
sudo cp -fv resources/git/commit-msg /usr/share/git-core/templates/hooks

echo disabling git ff
git config --global --add merge.ff false

#################################################
# setting up zsh
#################################################

# oh-my-zsh
curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
if [ ! -e ~/.zshrc ]; then
    ln -sf $PWD/resources/rcfiles/zshrc ~/.zshrc
fi

#################################################
# setting up nvm
#################################################
curl https://raw.github.com/creationix/nvm/master/install.sh | sh


#################################################
# setting up tmux
#################################################
echo installing .tmux.conf
cp -v resources/rcfiles/tmux.conf ~/.tmux.conf

#################################################
# setting up emacs
#################################################
cd ~/gprog
rm -rf ~/.emacs ~/.emacs.d     # uninstalling .emacs
if [ ! -d ~/gprog/emacs.d ]; then
    git clone https://github.com/garaemon/emacs.d.git
fi
cd emacs.d
git submodule update --init .
./install.sh

