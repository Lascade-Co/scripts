#!/bin/bash

set -e

# Check if a service name was provided
if [ -z "$1" ]; then
  echo "Usage: shell.sh <service_name> [optional] <command> [optional] <command_argument>"
  echo "Commands:"
  echo "  shell: Start an interactive bash shell in the container (default)"
  echo "  run <command>: Run a command in the container"
  echo "  logs: Show logs for the container"
  echo "  restart: Restart the container"
  exit 1
fi

SERVICE_NAME="$1"
COMMAND="$2"

if [ -z "$COMMAND" ]; then
  COMMAND="shell"
fi

# Find all running containers for services ending with the given service name
CONTAINER_IDS=($(docker ps --filter "name=_${SERVICE_NAME}\." --format "{{.ID}}"))

if [ ${#CONTAINER_IDS[@]} -eq 0 ]; then
  if [ "$COMMAND" == "restart" ]; then
    echo "No running containers found for service ending with '${SERVICE_NAME}'. Attempting to infer stack from any running service..."
    # Fallback: pick any running container that belongs to a Docker stack
    FALLBACK_CONTAINER_ID=$(docker ps --filter "label=com.docker.stack.namespace" --format "{{.ID}}" | head -n 1)
    if [ -z "$FALLBACK_CONTAINER_ID" ]; then
      echo "No stack-labeled running containers found to infer stack. Cannot restart '${SERVICE_NAME}'."
      exit 1
    fi
    CONTAINER_ID="$FALLBACK_CONTAINER_ID"
  else
    echo "No running containers found for service ending with '${SERVICE_NAME}'."
    exit 1
  fi
fi

# If multiple containers are found, let the user select one
if [ ${#CONTAINER_IDS[@]} -gt 1 ]; then
  echo "Multiple containers found for service '${SERVICE_NAME}'. Select one:"
  PS3="Enter the number of the container to connect to: "
  select CONTAINER_ID in "${CONTAINER_IDS[@]}"; do
    if [ -n "$CONTAINER_ID" ]; then
      break
    else
      echo "Invalid selection."
    fi
  done
elif [ ${#CONTAINER_IDS[@]} -eq 1 ]; then
  CONTAINER_ID=${CONTAINER_IDS[0]}
fi

# Get stack name from container label
STACK_NAME=$(docker inspect "$CONTAINER_ID" --format "{{ index .Config.Labels \"com.docker.stack.namespace\" }}")
FULL_SERVICE_NAME="${STACK_NAME}_${SERVICE_NAME}"

if [ "$COMMAND" == "shell" ]; then
  # Start an interactive bash shell in the container
  docker exec -it "$CONTAINER_ID" /bin/bash
elif [ "$COMMAND" == "run" ]; then
  if [ -z "$3" ]; then
    echo "Usage: shell <service_name> run <command>"
    exit 1
  fi
  docker exec "$CONTAINER_ID" "${@:3}"
elif [ "$COMMAND" == "logs" ]; then
  # Show logs for the container
  docker logs -f "$CONTAINER_ID"
elif [ "$COMMAND" == "restart" ]; then
  # Restart the container by scaling it down to 0 and then back to 1
  echo "Stopping container..."
  docker service scale "${FULL_SERVICE_NAME}=0"
  # Wait for the container to stop, and print a dot every second
  while docker ps --filter "name=${FULL_SERVICE_NAME}\." --format "{{.ID}}" | grep -q .; do
    echo -n "."
    sleep 1
  done
  echo "Starting container..."
  docker service scale "${FULL_SERVICE_NAME}=1"
else
  echo "Invalid command: $COMMAND"
  exit 1
fi
