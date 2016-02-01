#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

# cyanecho ">>>> [installing git commit-msg]"
# if [ ! -e /usr/share/git-core/templates/hooks/commit-msg ]; then
#     runsudo cp -fv $GPROG_DIR/garaemon-settings/resources/git/commit-msg /usr/share/git-core/templates/hooks
# fi
# cyanecho ">>>> [disabling git ff merge]"
# git config --global --add merge.ff false
# git config branch.master.rebase true
# git config --global pull.rebase true
# #git config --global pull.rebase preserve
if [ `uname` == "Linux" ]; then
    if [ ! -e $HOME/.local/bin/git ]; then
	cyanecho ">>>> [cloning git]"
	cd $GPROG_DIR
	git clone https://github.com/git/git.git
	cd git
	make configure
	./configure --prefix=$HOME/.local
	make all -j8
	make install
    fi
fi

cyanecho ">>>> [setting up git user.name]"
git config --global user.name "Ryohei Ueda"
cyanecho ">>>> [setting up git user.email]"
git config --global user.email "garaemon@gmail.com"
