#!/bin/bash
set -e
git checkout -b update-travis-$(date +%Y-%m-%d)
cd .travis
git checkout master
git pull
cd ..
git add .travis
git commit -m "Update .travis"
git push garaemon update-travis-$(date +%Y-%m-%d)
hub pull-request -m "update .travis"
