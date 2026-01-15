#!/bin/bash

set -e

COLOR_YELLOW='\033[1;33m'
COLOR_GREEN='\033[1;32m'
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
  if git show-ref --verify --quiet "refs/remotes/origin/$1"; then
    git checkout -B "$1" "origin/$1"
    git pull --ff-only
  else
    git checkout "$1"
    echo -e "${COLOR_YELLOW}Checked out '$1' in detached HEAD state; skipping 'git pull'.${NO_COLOR}"
  fi
fi

# Only pull if we're on a branch (not in detached HEAD)
if git symbolic-ref -q HEAD > /dev/null; then
  git pull --recurse-submodules=on-demand
fi

set -a
source .env
set +a

RENDERED_SWARM_COMPOSE_FILE=/tmp/.swarm.docker-compose.rendered.yml

docker stack -f base/swarm.docker-compose.yml -f swarm.docker-compose.yml config > "$RENDERED_SWARM_COMPOSE_FILE"

docker compose -f "$RENDERED_SWARM_COMPOSE_FILE" pull
docker stack deploy -c "$RENDERED_SWARM_COMPOSE_FILE" "$STACK_NAME" --with-registry-auth -d

echo -e "${COLOR_GREEN}Deployment successful.${NO_COLOR}"

echo "Run 'docker service ls' to check the services"
echo "Run shell <service_name> [optional] <command> to attach to a service"
