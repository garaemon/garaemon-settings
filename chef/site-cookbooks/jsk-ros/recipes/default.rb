#
# Cookbook Name:: jsk-ros
# Recipe:: default
#
# Copyright 2014, garaemon
#

%w{ros-hydro-openni-launch ros-groovy-openni-launch
   ros-hydro-openni-tracker ros-groovy-openni-tracker
   ros-hydro-moveit-core ros-groovy-moveit-core
   ros-hydro-moveit-ros-warehouse ros-groovy-moveit-ros-warehouse
   ros-hydro-manipulation-msgs ros-groovy-manipulation-msgs
   ros-hydro-pr2-controllers-msgs
   omniidl-python}.each do |pkg|
  package pkg do
    action :install
  end
end


# compile them
user = node["base_configuration"]["user"]
home = node["base_configuration"]["home_dir"]
catkin_ws_suffix = node["ros-desktop"]["catkin_ws"]
catkin_ws = "#{home}/#{catkin_ws_suffix}"

node["jsk-ros"]["distributions"].each do |distro|
  bash "wstool init" do
    user
    cwd "#{catkin_ws}/#{distro}/src"
    code <<-EOH
      source /opt/ros/#{distro}/setup.bash
      test -e #{catkin_ws}/#{distro}/src/.rosinstall || wstool init
    EOH
  end

  bash "wstool merge" do
    user
    cwd "#{catkin_ws}/#{distro}/src"
    code <<-EOH
      source /opt/ros/#{distro}/setup.bash
      wstool merge https://raw.github.com/garaemon/garaemon-settings/master/resources/rosinstall/garaemon.rosinstall
    EOH
  end

  bash "wstool update for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}/src"
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      wstool update -j10
    EOH
  end

  bash "catkin_make for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}"
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      catkin_make
    EOH
  end
end
