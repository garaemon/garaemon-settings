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

directory "#{home}/#{git_root_dir}" do
  action :create
  owner user
end

garaemon_emacs_path = "#{home}/#{git_root_dir}/emacs.d"
git garaemon_emacs_path do
  user user
  repository "https://github.com/garaemon/emacs.d.git"
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
