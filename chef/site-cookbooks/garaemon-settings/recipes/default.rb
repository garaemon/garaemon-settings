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

# packages
%w{zsh aptitude git-core emacs vim tmux anthy-el ssh zsh curl htop
   python-pip tig ruby imagemagick
   ibus-mozc
   ttf-dejavu dconf gnome-tweak-tool
   sqlite3 libgdbm-dev bison libffi-dev dstat
   gawk g++ libreadline6-dev zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev autoconf libncurses5-dev automake libtool
   gnome-panel compizconfig-settings-manager
   apt-transport-https
   libgnome-keyring-dev
   virtualbox}.each do |pkg|
  package pkg do
    action :install
  end
end


# chrome
apt_repository "google-chrome" do
  uri "http://dl.google.com/linux/chrome/deb/"
  distribution "stable"
  components ["main"]
  action :add
end
execute "add chrome key" do
  command "wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -"
end

package "google-chrome-stable" do
  action :install
end

# use ubuntu classic
template "#{home}/.dmrc" do
  source "dmrc.erb"
  owner user
end

# dropbox
apt_repository "dropbox" do
  uri "http://linux.dropbox.com/ubuntu"
  distribution node['lsb']['codename']
  components ["main"]
  keyserver "pgp.mit.edu"
  key "5044912E"
end
package "dropbox" do
  action :install
end

#docker
# execute "add coker key" do
#   command "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9"
# end
# apt_repository "docker" do
#   uri "https://get.docker.io/ubuntu"
#   components ["main"]
#   distribution "docker"
#   action :add
# end
# package "lxc-docker"
# # setting up docker
# execute "docker pull ubuntu:12.04"

remote_file "/tmp/gyazo.deb" do
  source "https://github.com/downloads/kambara/Gyazo-for-Linux/gyazo_1.0-1_all.deb"
  mode 0644
  #  shasum -a 256
  checksum "bc7d91598294322fd693e846a215f8ab9cd196046d1bb630f04c2117c8d244b6"
end

dpkg_package "gyazo" do
  source "/tmp/gyazo.deb"
  action :install
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

github_packages = ["garaemon/garaemon-settings.git",
                   "garaemon/rosenv.git",
                   "holman/spark.git",
                   "joemiller/spark-ping.git",
                   "seebi/dircolors-solarized.git",
                   "tomislav/osx-terminal.app-colors-solarized.git",
                   "yonchu/shell-color-pallet.git",
                   "sigurdga/gnome-terminal-colors-solarized.git",
                   "atom/atom.git"]
github_packages.each do |pkg|
  target_path = "#{home}/#{git_root_dir}/#{File.basename(pkg, ".git")}"
  git target_path do
    repository "#{git_prefix}#{pkg}"
    enable_submodules true
    user user
  end
end

garaemon_settings_path = "#{home}/#{git_root_dir}/garaemon-settings"

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

cmds = ["git config --global --add merge.ff false",
        "git config --global color.ui auto",
        "git config --global user.name 'Ryohei Ueda'",
        "git config --global user.email garaemon@gmail.com",
        "git config --global alias.graph 'log --graph --decorate --oneline'",
        "git config --global alias.co checkout",
        "git config --global alias.st status"]
cmds.each do |cmd|
  bash cmd do
    user user
    code <<-EOH
#{cmd}
EOH
  end
end

# update gconf value
[{:type => "string",
  :key => "/desktop/gnome/interface/gtk_key_theme",
  :value => "Emacs"
   }].each do |conf|
  cmd = "gconftool --type #{conf[:type]} --set #{conf[:key]} #{conf[:value]}"
  execute cmd do
    user user
  end
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
curl https://raw.githubusercontent.com/creationix/nvm/v0.7.0/install.sh | sh
  EOH
end

# installing npm packages
node["garaemon-settings"]["node-versions"].each do |version|
  bash "install node.js #{version}" do
    user user
    code <<-EOH
      source #{home}/.nvm/nvm.sh
      nvm install #{version}
    EOH
  end
  npm_packages = ["express", "grunt", "grunt-cli", "yo", "generator-webapp"]
  bash "install npm packages for #{version}" do
    user user
    code <<-EOH
      source #{home}/.nvm/nvm.sh
      nvm use #{version}
      npm install -g express grunt grunt-cli
    EOH
  end
end
### ruby

bash "install rvm" do
  user user
  code <<-EOH
    curl -sSL https://get.rvm.io | bash -s stable
  EOH
end

ruby_versions = node["garaemon-settings"]["ruby-versions"]
gem_packages = %w{travis fluentd t fluent-plugin-dstat fluent-plugin-datacounter fluent-plugin-mongo bson_ext fluent-plugin-out-http}
ruby_versions.each do |version|
  bash "install ruby #{version}" do
    user user
    code <<-EOH
      source #{home}/.rvm/scripts/rvm
      rvm install #{version}
    EOH
  end
  gem_str = gem_packages.join(" ")
  bash "install gems for #{version}" do
    user user
    code <<-EOH
      source #{home}/.rvm/scripts/rvm
      rvm use #{version}
      gem install #{gem_str} --no-ri --no-rdoc
    EOH
  end
end

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


###########################################################
# powerline
bash "install powerline pip" do
  code <<-EOH
    pip install git+git://github.com/Lokaltog/powerline
  EOH
end

directory "#{home}/.fonts" do
  action :create
  owner user
end

remote_file "#{home}/.fonts/PowerlineSymbols.otf" do
  source "https://github.com/Lokaltog/powerline/raw/develop/font/PowerlineSymbols.otf"
  owner user
end

bash "fc-cache" do
  user user
  code <<-EOH
    fc-cache -vf ~/.fonts
  EOH
end

directory "#{home}/.fonts.conf.d" do
  action :create
  owner user
end

remote_file "#{home}/.fonts.conf.d/10-powerline-symbols.conf" do
  source "https://github.com/Lokaltog/powerline/raw/develop/font/10-powerline-symbols.conf"
  owner user
end

directory "#{home}/.config" do
  action :create
  owner user
end

link "#{home}/.config/powerline" do
  owner user
  to "#{garaemon_settings_path}/resources/powerline"
end

# end of powerline
###########################################################

# bash "install gnome solarized" do
#   user user
#   code <<-EOH
#     cd #{home}/gnome-terminal-colors-solarized
#     ./install.sh
#   EOH
# end

#################################################
# install the latest node.js on system
remote_file "/tmp/node-v0.10.28.tar.gz" do
  not_if 'test $(node -v) = "v0.10.28"'
  source "http://nodejs.org/dist/v0.10.28/node-v0.10.28.tar.gz"
  mode 0644
  #  shasum -a 256
  checksum "abddc6441e0f208f6ed8a045e0293f713ea7f6dfb2d6a9a2024bf8b1b4617710"
end
bash "compile and install node.js" do
  not_if 'test $(node -v) = "v0.10.28"'
  code <<-EOH
  cd /tmp/
  tar xvzf node-v0.10.28.tar.gz
  cd node-v0.10.28
  ./configure && make -j`grep -c processor /proc/cpuinfo` && make install
EOH
end

#################################################
# atom
# bash "set python for npm" do
#   user user
#   code <<-EOH
#       source #{home}/.nvm/nvm.sh
#       nvm use #{node["garaemon-settings"]["node-versions"][0]}
#       npm config set python /user/bin/python2 -g
#     EOH
# end

# bash "build atom" do
#   user user
#   not_if 'which atom'
#   code <<-EOH
#   source #{home}/.nvm/nvm.sh
#   nvm use #{node["garaemon-settings"]["node-versions"][0]}
#   cd #{home}/#{git_root_dir}/atom
#   ./script/build
# EOH
# end

# bash "grunt atom" do
#   not_if 'which atom'
#   code <<-EOH
#   cd #{home}/#{git_root_dir}/atom
#   ./script/grunt install
# EOH
# end

# bash "install atom" do
#   not_if 'which atom'
#   code <<-EOH
#   source #{home}/.nvm/nvm.sh
#   nvm use #{node["garaemon-settings"]["node-versions"][0]}
#   cd #{home}/#{git_root_dir}/atom
#   ./script/grunt mkdeb
# EOH
# end
