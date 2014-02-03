#
# Cookbook Name:: ros
# Recipe:: default
#
# Copyright 2014, garaemon
#
#

# adding ROS repository
apt_repository 'ros-latest' do
  uri 'http://packages.ros.org/ros/ubuntu'
  distribution node['lsb']['codename']
  key 'http://packages.ros.org/ros.key'
  components   ['main']
end

# install ros package
%w{ros-hydro-desktop-full ros-groovy-desktop-full}.each do |pkg|
  package pkg do
    action :install
  end
end

# create catkin workspace



# create rosbuild workspace
