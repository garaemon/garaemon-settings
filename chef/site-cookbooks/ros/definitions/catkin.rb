# catkin.rb
#   action -> :init_workspace, :make
#   common parameter
#     workspace (required)
#     user (required)
#     setup_sh (required)
#   :init_workspace
#   :make
#     only_pkg_with_deps => array of packages (optional)
#     make_target => target of make

define :catkin, :only_pkg_with_deps => [] do
  if not params[:workspace] then
    log "no :workspace is specified" do
      level :error
    end
    return
  end
  case params[:action]
  when :init_workspace
    directory params[:workspace] do
      action :create
      recursive true
      owner params[:user]
    end
    cmd = ". #{params[:setup_sh]}; catkin_init_workspace"
    execute cmd do
      user params[:user]
      command cmd
      cwd params[:workspace]
      not_if do
        ::File.exists?("#{params[:workspace]}/CMakeLists.txt")
      end
    end
  when :make
    if params[:only_pkg_with_deps].size != 0 then
      only_pkg_with_deps_option = params[:only_pkg_with_deps].join(" ")
    end
    if params[:make_target] then
      make_target_option = params[:make_target]
    end
    cmd = ". #{params[:setup_sh]}; catkin_make #{make_target_option} #{only_pkg_with_deps_option}"
  end
end
