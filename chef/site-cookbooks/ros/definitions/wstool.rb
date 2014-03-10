# wstool
#   action -> :set, :rm, :merge, :init, :update
#   common parameter
#     workspace (required)
#     user (required)
#   :merge
#     uri -> uri of the .rosinstall file (required)
#   :set
#      uri -> uri of the repo (required)
#      version -> version (optional)
#      vcs -> :git, :svn, :hg or :bzr (required)
#      local -> local relative path from :workspace (required)
#   :rm, :remove
#      local -> local relative path from :workspace (required)

define :wstool do
  if not params[:workspace] then
    log "no :workspace is specified" do
      level :error
    end
    return
  end
  case params[:action]
  when :init 
    directory params[:workspace] do
      action :create
      recursive true
      owner params[:user]
    end
    cmd = "wstool init #{params[:workspace]}"
    execute cmd do
      user params[:user]
      command cmd
      not_if do
        ::File.exists?("#{params[:workspace]}/.rosinstall")
      end
    end
  when :merge
    cmd = "wstool merge #{params[:uri]} -t #{params[:workspace]} -y"
    execute cmd do
      user params[:user]
      command cmd
    end
  when :set
    if params[:version] then
      version_string = "-v #{params[:version]}"
    end
    case params[:vcs]
    when :git
      vcs_option = "--git"
    when :svn
      vcs_option = "--svn"
    when :hg
      vcs_option = "--hg"
    when :bzr
      vcs_option = "--bzr"
    end
    cmd = "wstool set #{params[:local]} #{params[:uri]} -t #{params[:workspace]} -y #{version_string} #{vcs_option} || :"
    execute cmd do
      user params[:user]
      command cmd
    end
  when :rm, :remove
    cmd = "wstool rm #{params[:local]} || :"
    execute cmd do
      cwd params[:workspace]
      user params[:user]
      command cmd
    end
  when :update
    if params[:parallel_jobs] then
      parallel_option = "-j#{params[:parallel_jobs]}"
    end
    cmd = "wstool update #{parallel_option} --delete-changed-uris"
    execute cmd do
      cwd params[:workspace]
      user params[:user]
      command cmd
    end
  end
end
