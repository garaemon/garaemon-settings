#!/bin/sh
# install-ros.sh

wget 'https://sourceforge.net/p/jsk-ros-pkg/code/HEAD/tree/trunk/jsk.rosbuild?format=raw' -O /tmp/jsk.rosbuild
yes | bash /tmp/jsk.rosbuild groovy
sudo aptitude install ros-groovy-pr2-moveit-config ros-groovy-openni-launch ros-groovy-openni-camera ros-groovy-rosbridge-suite
source ~/ros/groovy/setup.zsh
rosdep install euslisp

# adding some packages
rosws set --git roswww https://github.com/jihoonl/roswww.git
rosws update roswww
if [ `whoami` == garaemon ]; then
    rosws set --git garaemon-ros-pkg git@github.com:garaemon/garaemon-ros-pkg.git
else
    rosws set --git garaemon-ros-pkg https://github.com/garaemon/garaemon-ros-pkg.git
fi
rosws update garaemon-ros-pkg