#
# Cookbook Name:: ros-desktop
# Recipe:: default
#
# Copyright 2014, garaemon
#
#

# adding ROS repository
apt_repository 'ros-latest' do
  uri 'http://packages.ros.org/ros/ubuntu'
  #uri 'http://ros.jsk.imi.i.u-tokyo.ac.jp/packages/ros/ubuntu'
  distribution node['lsb']['codename']
  key 'http://packages.ros.org/ros.key'
  components   ['main']
end

# install ros package
%w{ros-hydro-desktop-full ros-groovy-desktop-full
   ros-hydro-rosbuild ros-groovy-rosbuild
   ros-hydro-catkin ros-groovy-catkin}.each do |pkg|
  package pkg do
    action :install
  end
end

def create_dirs(dirs)
  user = node["base_configuration"]["user"]
  dirs.each do |dir|
    directory dir do
    action :create
    owner user
    end
  end
end

# create catkin workspace

def setup_catkin(distro)
  catkin_ws = node["ros-desktop"]["catkin_ws"]
  home_directory = node["base_configuration"]["home_dir"]
  directories = ["#{home_directory}/#{catkin_ws}",
                 "#{home_directory}/#{catkin_ws}/#{distro}",
                 "#{home_directory}/#{catkin_ws}/#{distro}/src"]
  create_dirs(directories)
  
  unless File.exists? "#{home_directory}/#{catkin_ws}/#{distro}/src/CMakeLists.txt" then
    bash "catkin_init_workspace for #{distro}" do
      user user
      cwd "#{home_directory}/#{catkin_ws}/#{distro}/src"
      code <<-EOH
       source /opt/ros/#{distro}/setup.sh
       catkin_init_workspace
      EOH
    end
    bash "catkin_make for #{distro}" do
      user user
      cwd "#{home_directory}/#{catkin_ws}/#{distro}"
      code <<-EOH
       source /opt/ros/#{distro}/setup.sh
       catkin_make
      EOH
    end
  end
end

setup_catkin("hydro")
setup_catkin("groovy")

# create rosbuild workspace
def setup_rosbuild(distro)
  rosbuild_ws = node["ros-desktop"]["rosbuild_ws"]
  catkin_ws = node["ros-desktop"]["catkin_ws"]
  home_directory = node["base_configuration"]["home_dir"]
  directories = ["#{home_directory}/#{rosbuild_ws}",
                 "#{home_directory}/#{rosbuild_ws}/#{distro}"]
  create_dirs(directories)
  # run rosws init
  unless File.exists? "#{home_directory}/#{rosbuild_ws}/#{distro}/.rosinstall" then
    bash "rosws_init for #{distro}" do
      user user
      cwd "#{home_directory}/#{rosbuild_ws}/#{distro}"
      code <<-EOH
        source #{home_directory}/#{catkin_ws}/#{distro}/devel/setup.bash
        rosws init . #{home_directory}/#{catkin_ws}/#{distro}/devel
      EOH
    end
  end
end

setup_rosbuild("hydro")
setup_rosbuild("groovy")
