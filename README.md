garaemon-settings
=================

some script to setup garaemon's environment

Setting up vagrant
---
```sh
gem install vagrant
# Ubuntu 12,04 for VirtualBox
vagrant box add ubuntu-12.04 http://cloud-images.ubuntu.com/vagrant/precise/current/precise-server-cloudimg-amd64-vagrant-disk1.box
vagrant init ubuntu-12.04
vagrant up
vagrant ssh-config --host vagrant >> ~/.ssh/config
```

* running chef for that vagrant
```sh
knife solo cook vagrant
```
