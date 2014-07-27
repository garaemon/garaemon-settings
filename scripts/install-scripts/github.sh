GITHUB_REPOSITORIES="icholy/ttygif.git \
garaemon/emacs.d.git \
garaemon/garaemon-settings.git garaemon/rosenv.git \
holman/spark.git joemiller/spark-ping.git seebi/dircolors-solarized.git \
tomislav/osx-terminal.app-colors-solarized.git yonchu/shell-color-pallet.git \
sigurdga/gnome-terminal-colors-solarized.git \
garaemon/ffmpeg-movie-builder"

function github_update_clone()
{
    repo=$1
    redecho ">> [installing and updating $repo]"
    DIR_NAME=$(basename $repo .git)
    if [ -e $GPROG_DIR/$DIR_NAME ]; then
        move $GPROG_DIR/$DIR_NAME
        git pull
        git submodule update --init
    else
        move $GPROG_DIR
        git clone git@github.com:$repo
        move $DIR_NAME
        git submodule update --init
    fi
}

export -f github_update_clone
echo $GITHUB_REPOSITORIES | xargs -P $(grep -c processor /proc/cpuinfo) --delimiter ' ' -n 1 -I % bash -c "github_update_clone %"
