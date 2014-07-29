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
