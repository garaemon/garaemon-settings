#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

mkdir -p $HOME/ros

mkdir -p $HOME/ros/hydro/src
mkdir -p $HOME/ros/groovy/src
mkdir -p $HOME/ros/groovy.catkin/src
