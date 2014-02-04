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
user = node[
home = node['etc']['passwd'][user]['dir'] # Chef DSL

git "#{home}/gprog/garaemon-settings" do
  repository "https://github.com/garaemon/garaemon-settings.git"
  enable_submodules true
end
