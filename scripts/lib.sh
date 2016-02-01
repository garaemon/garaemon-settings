#!/bin/bash

# replace echo if it runs on mac

# if [ `uname` == "Darwin" ]; then
#     function echo() {
#         gecho $@
#     }
#     export -f echo
# fi

function move()
{
    cd $1 > /dev/null
}

function redecho()
{
    if [ `uname` == "Darwin" ]; then
	echo $'\e[1;31m' $1 $'\e[m'
    else
	echo -e "\e[1;31m" $1 "\e[m"
    fi
}

function cyanecho()
{
    if [ `uname` == "Darwin" ]; then
	echo $'\e[36m' $1 $'\e[m'
    else
	echo -e "\e[36m" $1 "\e[m"
    fi
}

function yellowecho()
{
    echo -e "\e[33m" $1 "\e[m"
}


function runsudo()
{
    if [ "$NO_SUDO" != "true" ]; then
        sudo sh -c "$*"
    else
        yellowecho "[NO_SUDO=true] skipping $*"
    fi
}

export -f move
export -f redecho
export -f runsudo
export -f yellowecho
export -f cyanecho

if [ "$GPROG_DIR" = "" ]; then
    export GPROG_DIR=$HOME/gprog
fi
