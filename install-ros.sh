#!/bin/sh
# install-ros.sh

wget 'https://sourceforge.net/p/jsk-ros-pkg/code/HEAD/tree/trunk/jsk.rosbuild?format=raw' -O /tmp/jsk.rosbuild
yes | bash /tmp/jsk.rosbuild groovy
sudo aptitude install ros-groovy-pr2-moveit-config openni_launch openni_camera
source ~/ros/groovy/setup.zsh
rosdep install euslisp
