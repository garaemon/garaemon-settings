#!/bin/bash
cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

GEM_PACKAGES="hub"

gem install $GEM_PACKAGES

# setup hub command
# rm ~/.bin/hub
# mkdir -p ~/.bin
# hub hub standalone > ~/.bin/hub
# chmod +x ~/.bin/hub
