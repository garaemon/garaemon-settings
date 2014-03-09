#!/bin/sh

mkdir -p .ssh
touch ~/.ssh/authorized_keys
curl https://github.com/garaemon.keys >> ~/.ssh/authorized_keys
