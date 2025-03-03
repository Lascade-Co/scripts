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

git pull

# Create env based on .env.sample if .env does not exist
if [ ! -f .env ]; then
  echo -e "${COLOR_YELLOW}.env file not found${NO_COLOR}"
  read -p "Create .env file based on .env.sample? [y/N]: " CREATE_ENV

  # Exit if user does not want to create .env file
  if [ "$CREATE_ENV" != "y" ]; then
    echo -e "${COLOR_RED}Please create .env file and run this script again${NO_COLOR}"
    exit 1
  fi

  # Read the .env.sample file line by line and ask user to input values
  echo -e "${COLOR_BLUE}Leave blank to use default value, enter \$random to generate random value${NO_COLOR}"

  # Open .env.sample on file descriptor 3
  exec 3< .env.sample

  while IFS= read -r line <&3; do
    # Skip comments and empty lines
    if [[ "$line" == \#* ]] || [ -z "$line" ] || [[ ! "$line" == *=* ]]; then
      continue
    fi

    # Extract key and value from line
    key=$(echo "$line" | cut -d'=' -f1)
    value=$(echo "$line" | cut -d'=' -f2)

    # Ask user to input value
    read -p "$key ( $value ): " user_value

    # Use default value if user input is empty
    if [ -z "$user_value" ]; then
      user_value=$value
    fi

    # Generate random value if user input is $random
    if [ "$user_value" == "\$random" ]; then
      user_value=$(openssl rand -hex 16)
    fi

    # Append key and value to .env file
    echo "$key=$user_value" >> .env
  done

  # Close file descriptor 3
  exec 3<&-
fi

source .env

export $(grep -v '^#' .env | xargs)
docker stack deploy -c swarm.docker-compose.yml "$STACK_NAME" --with-registry-auth -d

echo -e "${COLOR_GREEN}Deployment successful.${NO_COLOR}"

echo "Run 'docker service ls' to check the services"
echo "Run shell <service_name> [optional] <command> to attach to a service"
