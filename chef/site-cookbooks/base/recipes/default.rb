#
# Cookbook Name:: base
# Recipe:: default
#
# Copyright 2014, garaemon
#
# All rights reserved - Do Not Redistribute
#

%w{zsh mosh}.each do |pkg|
  package pkg do
    action :install
  end
end

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
