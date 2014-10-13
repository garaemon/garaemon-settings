#!/bin/sh

cd /tmp
rm -rf garaemon-settings
git clone https://github.com/garaemon/garaemon-settings.git
cd garaemon-settings/scripts
./install.sh
