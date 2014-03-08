# catkin.rb
#   action -> :init_workspace, :make
#   common parameter
#     workspace (required)
#     user (required)
#     setup_sh (required)

define :catkin do
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
  end
end
