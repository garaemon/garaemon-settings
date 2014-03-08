#
# Cookbook Name:: ros
# Recipe:: default
#
# Copyright 2014, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#

# catkin do
#   workspace "/home/jskuser/test_wstool/src"
#   action :init_workspace
#   setup_sh "/opt/ros/hydro/setup.sh"
#   user "jskuser"
# end

# wstool do
#   workspace "/home/jskuser/test_wstool/src"
#   action :init
#   user "jskuser"
# end

# wstool do
#   workspace "/home/jskuser/test_wstool/src"
#   action :merge
#   user "jskuser"
#   uri "https://raw.github.com/jsk-ros-pkg/jsk_common/master/jsk.rosinstall"
# end

# wstool do
#   workspace "/home/jskuser/test_wstool/src"
#   action :set
#   user "jskuser"
#   uri "https://github.com/start-jsk/rtmros_common.git"
#   vcs :git
#   local "start-jsk/rtmros_common"
#   version "master"
# end

# wstool do
#   workspace "/home/jskuser/test_wstool/src"
#   action :rm
#   user "jskuser"
#   local "start-jsk/rtmros_common"
# end

# wstool do
#   workspace "/home/jskuser/test_wstool/src"
#   action :update
#   user "jskuser"
#   parallel_jobs 10
# end

# catkin do
#   workspace "/home/jskuser/test_wstool/src"
#   action :make
#   setup_sh "/opt/ros/hydro/setup.sh"
#   user "jskuser"
# end

rosdep do
  action :init
end
rosdep do
  action :update
  user "jskuser"
  distro "hydro"
end
rosdep do
  action :install
  packages ["roscpp", "rospy"]
  setup_sh "/opt/ros/hydro/setup.sh"
  user "jskuser"
  distro "hydro"
end
