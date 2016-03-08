#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh


if [ ! -e "$HOME/.pyenv" ]; then
    git clone https://github.com/yyuu/pyenv.git $HOME/.pyenv
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    pyenv install 2.7.10
    pyenv global 2.7.10
fi
