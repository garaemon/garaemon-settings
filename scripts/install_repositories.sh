#!/bin/sh

REPOS="https://github.com/rhysd/Shiba.git \
git@github.com:garaemon/pltcli.git \
git@github.com:garaemon/multi_crop.git \
git@github.com:garaemon/simpler-dot.git \
https://github.com/dylang/npm-check.git"

for r in $REPOS
do
    add_project.py -q $r
done
