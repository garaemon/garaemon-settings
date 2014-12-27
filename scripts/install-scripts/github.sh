#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

GITHUB_REPOSITORIES="icholy/ttygif.git \
garaemon/emacs.d.git \
garaemon/garaemon-settings.git garaemon/rosenv.git \
holman/spark.git joemiller/spark-ping.git seebi/dircolors-solarized.git \
tomislav/osx-terminal.app-colors-solarized.git yonchu/shell-color-pallet.git \
sigurdga/gnome-terminal-colors-solarized.git \
github/hub.git \
garaemon/ffmpeg-movie-builder.git saitoha/seq2gif.git \
garaemon/madmagazine-blog-watcher.git"

function github_update_clone()
{
    repo=$1
    cyanecho ">>>> [installing and updating $repo]"
    DIR_NAME=$(basename $repo .git)
    if [ -e $GPROG_DIR/$DIR_NAME ]; then
        move $GPROG_DIR/$DIR_NAME
        git pull
        git submodule update --init
    else
        move $GPROG_DIR
        if [ "$USE_HTTPS_FOR_GIT" = "true" ]; then
            git clone https://github.com/$repo
        else
            git clone git@github.com:$repo
        fi
        move $DIR_NAME
        git submodule update --init
    fi
}

function github_update_clone_depth1()
{
    repo=$1
    cyanecho ">>>> [installing and updating $repo]"
    DIR_NAME=$(basename $repo .git)
    if [ -e $GPROG_DIR/$DIR_NAME ]; then
        move $GPROG_DIR/$DIR_NAME
        git pull
        git submodule update --init
    else
        move $GPROG_DIR
        if [ "$USE_HTTPS_FOR_GIT" = "true" ]; then
            git clone https://github.com/$repo --depth=1
        else
            git clone git@github.com:$repo --depth=1
        fi
        move $DIR_NAME
        git submodule update --init
    fi
}

export -f github_update_clone
echo $GITHUB_REPOSITORIES | xargs -P 0 --delimiter ' ' -n 1 -I % bash -c "github_update_clone %"
github_update_clone_depth1 emacs-mirror/emacs.git
