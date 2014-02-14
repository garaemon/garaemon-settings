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

  # create directory
  directories = ["#{catkin_ws}",
                 "#{catkin_ws}/#{distro}",
                 "#{catkin_ws}/#{distro}/src"]
  directories.each do |dir|
    directory dir do
      action :create
      owner user
    end
  end

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

  bash "catkin init for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}/src"
    code <<-EOH
      source /opt/ros/#{distro}/setup.bash
      test -e CMakeLists.txt || catkin_init_workspace
    EOH
  end
  
  bash "wstool init for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}/src"
    code <<-EOH
      source /opt/ros/#{distro}/setup.bash
      test -e #{catkin_ws}/#{distro}/src/.rosinstall || wstool init
    EOH
  end

  bash "wstool merge for #{distro}" do
    user user
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

  bash "rosdep update for #{distro}" do
    user user
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      rosdep update
    EOH
  end
  
  bash "rosdep install for #{distro}" do
    cwd "#{catkin_ws}/#{distro}"
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      rosdep install -r -n --from-paths src --ignore-src --rosdistro #{distro} -y
    EOH
  end
  
  #should clear before catkin_make ???
  bash "catkin_make for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}"
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      catkin_make --only-pkg-with-deps hrpsys_gazebo_tutorials
    EOH
  end
  bash "catkin_make install for #{distro}" do
    user user
    cwd "#{catkin_ws}/#{distro}"
    code <<-EOH
      source /opt/ros/#{distro}/setup.sh
      catkin_make install
    EOH
  end
end
