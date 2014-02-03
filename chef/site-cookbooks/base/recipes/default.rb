#
# Cookbook Name:: base
# Recipe:: default
#
# Copyright 2014, garaemon
#
# All rights reserved - Do Not Redistribute
#

%w{zsh aptitude git-core emacs vim tmux anthy-el ssh zsh curl htop}.each do |pkg|
  package pkg do
    action :install
  end
end

