#!/bin/sh
set -e
# install.sh


#################################################
# setting up git
#################################################
echo installing commit-msg
sudo cp -fv resources/git/commit-msg /usr/share/git-core/templates/hooks

echo disabling git ff
git config --global --add merge.ff false

#################################################
# setting up emacs
#################################################
cd ~/gprog
rm -rf ~/.emacs ~/.emacs.d      # uninstalling .emacs
git clone git@github.com:garaemon/emacs.d.git
cd emacs.d
git submodule update --init .
./install.sh


