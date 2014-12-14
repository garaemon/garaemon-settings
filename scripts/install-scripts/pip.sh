#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

packages="percol"
cyanecho ">>>> [installing $packages]"
pip install --user $packages
