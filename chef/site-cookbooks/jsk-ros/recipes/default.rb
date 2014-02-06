#
# Cookbook Name:: jsk-ros
# Recipe:: default
#
# Copyright 2014, garaemon
#



def wstool_set(distro, vcs, dir, repo)
  user = node["base_configuration"]["user"]
  home = node["base_configuration"]["home_dir"]
  catkin_ws_suffix = node["ros-desktop"]["catkin_ws"]
  catkin_ws = "#{home}/#{catkin_ws_suffix}"
  unless File.exists? "#{catkin_ws}/#{distro}/src/#{dir}" then
    bash "wstool set for #{dir}" do
      user user
      cwd "#{catkin_ws}/#{distro}/src"
      code <<-EOH
        source /opt/ros/#{distro}/setup.sh
        wstool set #{vcs} -y #{dir} #{repo} 
      EOH
    end
  end
end

wstool_set("hydro",
           "--git", "moveit_ros", "https://github.com/ros-planning/moveit_ros.git")
wstool_set("hydro",
           "--git", "rviz_animated_view_controller",
           "https://github.com/ros-visualization/rviz_animated_view_controller.git")
wstool_set("hydro",
           "--git", "view_controller_msgs",
           "https://github.com/ros-visualization/view_controller_msgs.git")
wstool_set("hydro",
           "--svn", "rtm-ros-robotics",
           "https://rtm-ros-robotics.googlecode.com/svn/trunk")
wstool_set("hydro",
           "--svn", "jsk-ros-pkg",
           "https://svn.code.sf.net/p/jsk-ros-pkg/code/trunk")
wstool_set("hydro",
           "--git", "baxter_common",
           "https://github.com/RethinkRobotics/baxter_common")

# compile them
user = node["base_configuration"]["user"]
home = node["base_configuration"]["home_dir"]
catkin_ws_suffix = node["ros-desktop"]["catkin_ws"]
catkin_ws = "#{home}/#{catkin_ws_suffix}"

node["jsk-ros"]["distributions"].each do |distro|
  bash "wstool update for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}/src"
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      wstool update -j 10
    EOH
  end
end

node["jsk-ros"]["distributions"].each do |distro|
  bash "catkin_make for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}"
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      catkin_make
    EOH
  end
end
