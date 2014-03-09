#
# Cookbook Name:: jsk-ros
# Recipe:: default
#
# Copyright 2014, garaemon
#
apt_repository 'osrf' do
  uri 'http://packages.osrfoundation.org/drc/ubuntu'
  distribution node['lsb']['codename']
  key 'http://packages.osrfoundation.org/drc.key'
  components ['main']
end

%w{ros-hydro-openni-launch ros-groovy-openni-launch
   ros-hydro-openni-tracker ros-groovy-openni-tracker
   ros-hydro-moveit-core ros-groovy-moveit-core
   ros-hydro-moveit-ros-warehouse ros-groovy-moveit-ros-warehouse
   ros-hydro-manipulation-msgs ros-groovy-manipulation-msgs
   ros-hydro-pr2-controllers-msgs
   ros-hydro-collada-urdf ros-groovy-collada-urdf
   drcsim-hydro
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

  ["#{catkin_ws}", "#{catkin_ws}/#{distro}", "#{catkin_ws}/#{distro}/src"].each do |dir|
    directory dir do
      action :create
      recursive true
      owner user
    end
  end
  
  # create directory
  if node["jsk-ros"]["clear_catkin"] then
    bash "clear catkin ws for #{distro}" do
      user user
      cwd "#{catkin_ws}/#{distro}"
      code <<-EOH
        rm -rf build devel install src
        mkdir src
      EOH
    end
  end

  catkin do
    user user
    workspace "#{catkin_ws}/#{distro}/src"
    action :init
    setup_sh "/opt/ros/#{distro}/setup.sh"
  end
  
  wstool do
    user user
    workspace "#{catkin_ws}/#{distro}/src"
    action :init
  end

  wstool do
    user user
    workspace "#{catkin_ws}/#{distro}/src"
    action :merge
    #uri "https://raw.github.com/jsk-ros-pkg/jsk_common/master/jsk.rosinstall"
    uri "https://raw.github.com/garaemon/garaemon-settings/master/resources/rosinstall/garaemon.rosinstall"
  end
  
  wstool do
    user user
    workspace "#{catkin_ws}/#{distro}/src"
    action :update
    parallel_jobs 5
  end

  rosdep do
    action :init
  end
  rosdep do
    action :update
    user user
    distro distro
  end
  
  rosdep do
    action :install_from_source
    paths ["#{catkin_ws}/#{distro}/src"]
    distro distro
  end

  catkin do
    action :make
    setup_sh "/opt/ros/#{distro}/setup.sh"
    workspace "#{catkin_ws}/#{distro}/src"
    user user
  end
  
  catkin do
    action :make
    make_target "install"
    setup_sh "/opt/ros/#{distro}/setup.sh"
    workspace "#{catkin_ws}/#{distro}/src"
    user user
  end
  
end
