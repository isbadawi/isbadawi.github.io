#!/bin/bash
set -x

if [ ! -d _deploy ]; then
  git clone -b main git@github.com:isbadawi/isbadawi.github.io _deploy
fi

hugo --baseURL "https://ismail.badawi.io" --destination _deploy
sha=`git rev-parse HEAD`
(cd _deploy && git add --all . && git commit -m $sha && git push origin HEAD)
