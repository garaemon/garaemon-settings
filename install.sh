#!/bin/sh

# install.sh


#################################################
# installing git's commit-msg
#################################################
echo installing commit-msg
sudo cp -fv resources/git/commit-msg /usr/share/git-core/templates/hooks
