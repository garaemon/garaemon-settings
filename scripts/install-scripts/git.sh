#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [installing git commit-msg]"
if [ ! -e /usr/share/git-core/templates/hooks/commit-msg ]; then
    runsudo cp -fv $GPROG_DIR/garaemon-settings/resources/git/commit-msg /usr/share/git-core/templates/hooks
fi
cyanecho ">>>> [disabling git ff merge]"
git config --global --add merge.ff false
git config branch.master.rebase true
git config --global pull.rebase true
git config --global pull.rebase preserve

cyanecho ">>>> [setting up git user.name]"
git config --global user.name "Ryohei Ueda"
cyanecho ">>>> [setting up git user.email]"
git config --global user.email "garaemon@gmail.com"
