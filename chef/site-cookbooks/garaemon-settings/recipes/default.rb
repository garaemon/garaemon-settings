#
# Cookbook Name:: garaemon-settings
# Recipe:: default
#
# Copyright 2014, garaemon
#
include_recipe "rvm"

# make directory
# directory node['etc']['passwd'][user]['dir'] + '/gprog' do
#   action :create
# done

# checkout
user = node["base_configuration"]["user"]
home = node["base_configuration"]["home_dir"]
git_root_dir = node["garaemon-settings"]["git_root"]

# packages
%w{zsh aptitude git-core emacs vim tmux anthy-el ssh zsh curl htop virtualbox}.each do |pkg|
  package pkg do
    action :install
  end
end



# creating gprog
directory "#{home}/#{git_root_dir}" do
  action :create
  owner user
end

garaemon_settings_path = "#{home}/#{git_root_dir}/garaemon-settings"
git "#{garaemon_settings_path}" do
  repository "https://github.com/garaemon/garaemon-settings.git"
  enable_submodules true
  user user
end


# installing vimrc
link "#{home}/.vimrc" do
  owner user
  to "#{garaemon_settings_path}/resources/rcfiles/vimrc"
end

# installing tmux.conf
link "#{home}/.tmux.conf" do
  owner user
  to "#{garaemon_settings_path}/resources/rcfiles/tmux.conf"
end


# setting up git
link "/usr/share/git-core/templates/hooks/commit-msg" do
  to "#{garaemon_settings_path}/resources/git/commit-msg"
end
bash "git no-ff" do
  user user
  code <<-EOH
    git config --global --add merge.ff false
  EOH
end

# zsh
git "#{home}/.oh-my-zsh" do
  repository "https://github.com/robbyrussell/oh-my-zsh.git"
  enable_submodules true
  user user
end

link "#{home}/.zshrc" do
  owner user
  to "#{garaemon_settings_path}/resources/rcfiles/zshrc"
end

bash "install nvm" do
  user user
  code <<-EOH
    curl https://raw.github.com/creationix/nvm/master/install.sh | sh
  EOH
end

### ruby


# bash "install rvm" do
#   user user
#   code <<-EOH
#     curl -sSL https://get.rvm.io | bash -s stable
#   EOH
# end

# %w{2.1.0}.each do |pkg|
#   bash "install gem #{pkg}" do
#     user user
#     code <<-EOH
#       source #{home}/.rvm/scripts/rvm
#       rvm install #{pkg}
#     EOH
#   end
# end

# %w{vagrant}.each do |pkg|
#   bash "install gem #{pkg}" do
#     user user
#     code <<-EOH
#       source #{home}/.rvm/scripts/rvm
#       gem install #{pkg} --no-ri --no-rdoc
#     EOH
#   end
# end

