#!/bin/sh
set -e
# install.sh

# packages
sudo apt-get install aptitude
sudo aptitude install git-core emacs vim tmux anthy-el

#################################################
# setting up git
#################################################
echo installing commit-msg
sudo cp -fv resources/git/commit-msg /usr/share/git-core/templates/hooks

echo disabling git ff
git config --global --add merge.ff false

#################################################
# setting up tmux
#################################################
echo installing .tmux.conf
cp -v resources/rcfiles/tmux.conf ~/.tmux.conf

#################################################
# setting up emacs
#################################################
cd ~/gprog
rm -rf ~/.emacs ~/.emacs.d ~/gprog/emacs.d     # uninstalling .emacs
#git clone git@github.com:garaemon/emacs.d.git
git clone https://github.com/garaemon/emacs.d.git
cd emacs.d
git submodule update --init .
./install.sh


