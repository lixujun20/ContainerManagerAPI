#!/bin/bash

USER_ID=$1
HOME=/home/lixujun
DIFY_PATH=/home/lixujun/meta-agent/dify

docker compose -f $DIFY_PATH/docker/docker-compose.yaml -p dify_$USER_ID down
rm -rf ~/dify_data/user_$USER_ID