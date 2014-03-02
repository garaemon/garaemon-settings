#!/bin/bash

BASE_DIR=$HOME/ros

export PATH=/usr/local/bin:/usr/local/share/python:$PATH
export PYTHONPATH="/usr/local/lib/python2.7/site-packages:$PYTHONPATH"

# a script to install ROS hydro on mavericks
# 1. setup homebrew
# 2. install pcl
# 3. install ros softwares

ROS_DISTRO=hydro

# utils
function echo_title() {
    echo "$(tput setaf 1)>>> $@$(tput sgr0)"
}
function echo_subtitle() {
    echo "$(tput setaf 2)>>>>> $@$(tput sgr0)"
}

echo_title setup homebrew
brew update
brew install cmake
brew tap ros/${ROS_DISTRO}
brew tap osrf/simulation  # Gazebo, sdformat, and ogre
brew tap homebrew/versions # VTK5
brew tap homebrew/science  # others

BREW_PACKAGES="gazebo cmake"
echo_title installing brew packages ${BREW_PACKAGES}
brew install ${BREW_PACKAGES}


echo_title setup python
pip install -U setuptools wstool rosdep rosinstall rosinstall_generator rospkg \
catkin-pkg Distribute sphinx


#############################
# install pcl
# echo_title compiling pcl
# rm -rf /tmp/pcl
# mkdir -p /tmp/pcl
# cd /tmp/pcl

# git clone --depth=1 https://github.com/garaemon/pcl.git
# cd pcl
# mkdir build
# cd build
# cmake ..
# make -j$(sysctl hw.ncpu | awk '{print $2}')
# sudo make install
rm -rf ${BASE_DIR}/${ROS_DISTRO}
echo_title setup base dir: ${BASE_DIR}/${ROS_DISTRO}/base
mkdir -p ${BASE_DIR}/${ROS_DISTRO}/base
cd ${BASE_DIR}/${ROS_DISTRO}/base
rosinstall_generator desktop --rosdistro ${ROS_DISTRO} --deps --wet-only --tar \
    > ${ROS_DISTRO}-desktop-wet.rosinstall
mkdir -p src
cd src
wstool init
wstool merge ../hydro-desktop-wet.rosinstall

##########################################################
# generate .rosinstall
echo_title modify rosinstall
echo_subtitle use the latest orocos_kdl
wstool rm orocos_kdl/orocos_kdl
wstool rm orocos_kdl/python_orocos_kdl

echo_subtitle remove rqt_image_view
wstool rm rqt_common_plugins/rqt_image_view
wstool set --git -y orocos_kdl \
    https://github.com/garaemon/orocos_kinematics_dynamics.git -v mavericks-fix

echo_subtitle use the latest robot_state_publisher
wstool rm robot_state_publisher
wstool set --git -y robot_state_publisher \
    https://github.com/garaemon/robot_state_publisher -v hydro-mavericks-fix

echo_subtitle use the latest robot_model
wstool rm robot_model/collada_parser
wstool rm robot_model/collada_urdf
wstool rm robot_model/joint_state_publisher
wstool rm robot_model/kdl_parser
wstool rm robot_model/resource_retriever
wstool rm robot_model/urdf
wstool rm robot_model/robot_model
wstool rm robot_model/urdf_parser_plugin
wstool set --git -y robot_model \
    https://github.com/garaemon/robot_model -v mavericks-hydro
wstool update -j10

cd ..
echo_title catkin_make_isolated
./src/catkin/bin/catkin_make_isolated --install --cmake-args -DCUSTOM_PYTHON_INCLUDE_DIRS=/usr/local/Frameworks/Python.framework/Headers -DCUSTOM_PYTHON_LIBRARY=/usr/local/lib/libpython2.7.dylib -DCMAKE_CXX_FLAGS="-DGTEST_HAS_TR1_TUPLE=0"


