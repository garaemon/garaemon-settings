#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

mkdir -p $HOME/ros

mkdir -p $HOME/ros/hydro/src
mkdir -p $HOME/ros/groovy/src
mkdir -p $HOME/ros/groovy.catkin/src

# setup hydro by jsk script
wget -q -O /tmp/jsk.rosbuild https://raw.github.com/jsk-ros-pkg/jsk_common/master/jsk.rosbuild
bash /tmp/jsk.rosbuild hydro

rosenv register jsk.hydro ~/ros/hydro hydro
