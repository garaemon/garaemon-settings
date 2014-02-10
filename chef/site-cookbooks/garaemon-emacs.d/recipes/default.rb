#
# Cookbook Name:: garaemon-emacs.d
# Recipe:: default
#
# Copyright 2014, garaemon
#
# All rights reserved - Do Not Redistribute
#

user = node["base_configuration"]["user"]
home = node["base_configuration"]["home_dir"]
git_root_dir = node["garaemon-settings"]["git_root"]

# installing emacs24 for ubuntu 12.04
apt_repository 'emacs-24' do
  uri          'http://ppa.launchpad.net/cassou/emacs/ubuntu'
  distribution node['lsb']['codename']
  components   ['main']
  keyserver    'keyserver.ubuntu.com'
  key          'CEC45805'
end


%w{emacs24 emacs24-el}.each do |pkg|
  package pkg do
    action :install
  end
end

directory "#{home}/#{git_root_dir}" do
  action :create
  owner user
end

if node["garaemon-settings"]["git_ssh"] then
  git_prefix = "git@github.com:"
else
  git_prefix = "https://github.com/"
end

garaemon_emacs_path = "#{home}/#{git_root_dir}/emacs.d"
git garaemon_emacs_path do
  user user
  repository "#{git_prefix}garaemon/emacs.d.git"
  enable_submodules true
end

link "#{home}/.emacs" do
  owner user
  to "#{garaemon_emacs_path}/dot.emacs"
end

link "#{home}/.emacs.d" do
  owner user
  to "#{garaemon_emacs_path}"
end

