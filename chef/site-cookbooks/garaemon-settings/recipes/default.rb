#
# Cookbook Name:: garaemon-settings
# Recipe:: default
#
# Copyright 2014, garaemon
#

# make directory
# directory node['etc']['passwd'][user]['dir'] + '/gprog' do
#   action :create
# done

# checkout
user = node["base_configuration"]["user"]
home = node["base_configuration"]["home_dir"]
git_root_dir = node["garaemon-settings"]["git_root"]
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
file "/usr/share/git-core/templates/hooks/commit-msg" do
  content IO.read("#{garaemon_settings_path}/resources/git/commit-msg")
end
bash "git no-ff" do
  user user
  code <<-EOH
    git config --global --add merge.ff false
  EOH
end

# zsh
bash "install oh-my-zsh" do
  user user
  code <<-EOH
   curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
  EOH
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

bash "install rvm" do
  user user
  code <<-EOH
    curl -sSL https://get.rvm.io | bash -s stable
  EOH
end

