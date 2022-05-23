#!/bin/bash

set -e

running=false

if [[ "$(docker-compose top caddy)" != "" ]]; then
    running=true
    docker-compose down
fi

git fetch
git reset --hard origin/main

if $running; then
    docker-compose up -d --build
fi
