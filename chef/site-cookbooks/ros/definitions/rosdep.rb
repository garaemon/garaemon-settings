# rosdep.rb

define :rosdep, :packages => [] do
  case params[:action]
  when :init
    cmd = "rosdep init"
    execute cmd do
      command cmd
      creates "/etc/ros/rosdep/sources.list.d/20-default.list"
    end
  when :update
    cmd = "rosdep update"
    env = {"ROS_DISTRO" => params[:distro]}
    execute cmd do
      command cmd
      user params[:user]
      environment env
    end
  when :install
    if params[:packages].size != 0 then
      packages_args = params[:packages].join(" ")
      cmd = ". #{params[:setup_sh]}; rosdep install #{packages_args}"
      env = {"ROS_DISTRO" => params[:distro]}
      execute cmd do
        command cmd
        user params[:user]
        environment env
      end
    end
  end
end
