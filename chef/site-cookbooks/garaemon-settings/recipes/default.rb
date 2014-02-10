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
%w{zsh aptitude git-core emacs vim tmux anthy-el ssh zsh curl htop
   python-pip
   virtualbox}.each do |pkg|
  package pkg do
    action :install
  end
end

# creating gprog
directory "#{home}/#{git_root_dir}" do
  action :create
  owner user
end

if node["garaemon-settings"]["git_ssh"] then
  git_prefix = "git@github.com:"
else
  git_prefix = "https://github.com/"
end

garaemon_settings_path = "#{home}/#{git_root_dir}/garaemon-settings"
git "#{garaemon_settings_path}" do
  repository "#{git_prefix}garaemon/garaemon-settings.git"
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

bash "git auto color" do
  user user
  code <<-EOH
    git config --global color.ui auto
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

link "#{home}/.profile" do
  owner user
  to "#{garaemon_settings_path}/resources/rcfiles/profile"
end


bash "install nvm" do
  user user
  code <<-EOH
    curl https://raw.github.com/creationix/nvm/master/install.sh | sh
  EOH
end

# installing npm packages
bash "install node.js" do
  user user
  code <<-EOH
    source #{home}/.nvm/nvm.sh
    nvm install v0.10.21
  EOH
end

bash "install npm packages" do
  user user
  code <<-EOH
    source #{home}/.nvm/nvm.sh
    nvm use v0.10.21
    npm install -g express grunt grunt-cli
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

### python
bash "install pip packages" do
  code <<-EOH
    pip install percol
  EOH
end

# setup percol
directory "#{home}/.percol.d" do
  action :create
  owner user
end

link "#{home}/.percol.d/rc.py" do
  owner user
  to "#{garaemon_settings_path}/resources/rcfiles/percol_rc.py"
end
