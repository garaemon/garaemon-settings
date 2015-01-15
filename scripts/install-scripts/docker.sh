#!/bin/bash

cwd=`dirname "${0}"`
expr "${0}" : "/.*" > /dev/null || cwd=`(cd "${cwd}" && pwd)`

. $cwd/../lib.sh

cyanecho ">>>> [pull ubuntu:12.04]"
runsudo docker pull ubuntu:12.04

cyanecho ">>>> [pull ubuntu:12.10]"
runsudo docker pull ubuntu:12.10

cyanecho ">>>> [pull ubuntu:13.04]"
runsudo docker pull ubuntu:13.04

cyanecho ">>>> [pull ubuntu:13.10]"
runsudo docker pull ubuntu:13.10

cyanecho ">>>> [pull ubuntu:14.04]"
runsudo docker pull ubuntu:14.04

cyanecho ">>>> [pull ubuntu:14.10]"
runsudo docker pull ubuntu:14.10
