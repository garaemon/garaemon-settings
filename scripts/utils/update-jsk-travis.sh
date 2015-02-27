#!/bin/bash
set -e
target=$1
cd $target
user_name=garaemon
repo=$(git remote show origin -n | grep 'Fetch URL' | cut -f5 -d" " \
    | xargs -n 1 -i basename {} .git)
echo adding git@github.com:${user_name}/${repo}.git as ${user_name}
git remote add ${user_name} git@github.com:${user_name}/${repo}.git && echo 0
git checkout master
git pull
git branch -D update-travis-$(date +%Y-%m-%d) && echo 0
git checkout -b update-travis-$(date +%Y-%m-%d)
cd .travis
git checkout master
git pull
cd ..
git add .travis
git commit -m "Update .travis"
git push -f garaemon update-travis-$(date +%Y-%m-%d)
hub pull-request -m "update .travis"
cd ..
