#!/bin/bash

function move()
{
    cd $1 > /dev/null
}

function redecho()
{
    echo -e "\e[1;31m" $1 "\e[m"
}

function cyanecho()
{
    echo -e "\e[36m" $1 "\e[m"
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
