#!/bin/bash

set -e

COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[1;34m'
COLOR_RED='\033[1;31m'
NO_COLOR='\033[0m'

if [ -f /opt/project_folder ]; then
  PROJECT_FOLDER=$(cat /opt/project_folder)
else
  echo -e "${COLOR_YELLOW}Project folder not set, using current directory${NO_COLOR}"
  PROJECT_FOLDER=$(pwd)
fi

cd $PROJECT_FOLDER

# Check if $1 is a ref if so pull it
if [ -n "$1" ]; then
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/github || echo  -e "${COLOR_YELLOW}SSH Key ~/.ssh/github not found${NO_COLOR}"

  git fetch
  git checkout $1
fi

git pull --recurse-submodules=on-demand

docker stack deploy -c swarm.docker-compose.yml "$STACK_NAME" --with-registry-auth -d

echo -e "${COLOR_GREEN}Deployment successful.${NO_COLOR}"

echo "Run 'docker service ls' to check the services"
echo "Run shell <service_name> [optional] <command> to attach to a service"
