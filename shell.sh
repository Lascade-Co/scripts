#!/bin/bash

set -e

# Check if a service name was provided
if [ -z "$1" ]; then
  echo "Usage: shell.sh <service_name> [command] [args...]"
  echo "Commands:"
  echo "  shell: Start an interactive bash shell in the container (default)"
  echo "  run <command>: Run a command in the container"
  echo "  logs [tail_lines]: Show logs for the service (default tail: 100)"
  echo "  restart: Restart the service"
  echo "  stop: Stop the service (scale to 0)"
  echo "  start: Start the service (scale to configured replicas)"
  exit 1
fi

SERVICE_NAME="$1"
COMMAND="${2:-shell}"

# Get stack name from environment or use first stack
if [ -z "$STACK_NAME" ]; then
  STACK_NAME=$(docker stack ls --format "{{.Name}}" | head -n 1)
  if [ -z "$STACK_NAME" ]; then
    echo "No Docker stacks found and STACK_NAME environment variable not set."
    exit 1
  fi
  echo "Using stack: $STACK_NAME"
fi

FULL_SERVICE_NAME="${STACK_NAME}_${SERVICE_NAME}"

# Verify service exists
if ! docker service inspect "$FULL_SERVICE_NAME" &> /dev/null; then
  echo "Service '$FULL_SERVICE_NAME' not found."
  exit 1
fi

if [ "$COMMAND" == "shell" ] || [ "$COMMAND" == "run" ]; then
  # Find running tasks for the service
  mapfile -t TASK_LINES < <(docker service ps "$FULL_SERVICE_NAME" \
    --filter "desired-state=running" \
    --format "{{.ID}}|{{.Node}}|{{.Name}}" \
    --no-trunc)

  if [ ${#TASK_LINES[@]} -eq 0 ]; then
    echo "No running tasks found for service '$FULL_SERVICE_NAME'."
    exit 1
  fi

  # If multiple tasks, let user select one
  if [ ${#TASK_LINES[@]} -gt 1 ]; then
    echo "Multiple tasks found for service '$FULL_SERVICE_NAME'. Select one:"
    PS3="Enter the number of the task to connect to: "

    # Create display array for selection
    DISPLAY_OPTIONS=()
    for line in "${TASK_LINES[@]}"; do
      TASK_ID=$(echo "$line" | cut -d'|' -f1)
      NODE_NAME=$(echo "$line" | cut -d'|' -f2)
      TASK_NAME=$(echo "$line" | cut -d'|' -f3)
      DISPLAY_OPTIONS+=("$TASK_NAME (Node: $NODE_NAME)")
    done

    select choice in "${DISPLAY_OPTIONS[@]}"; do
      if [ -n "$choice" ]; then
        # Get the index of selected option (REPLY is 1-based)
        SELECTED_INDEX=$((REPLY - 1))
        SELECTED_LINE="${TASK_LINES[$SELECTED_INDEX]}"
        break
      else
        echo "Invalid selection."
      fi
    done
  else
    SELECTED_LINE="${TASK_LINES[0]}"
  fi

  TASK_ID=$(echo "$SELECTED_LINE" | cut -d'|' -f1)

  # Get container ID from the task
  CONTAINER_ID=$(docker inspect "$TASK_ID" \
    --format "{{.Status.ContainerStatus.ContainerID}}" 2>/dev/null)

  if [ -z "$CONTAINER_ID" ]; then
    echo "Could not find container ID for task."
    exit 1
  fi

  if [ "$COMMAND" == "shell" ]; then
    docker exec -it "$CONTAINER_ID" /bin/bash
  elif [ "$COMMAND" == "run" ]; then
    if [ -z "$3" ]; then
      echo "Usage: shell.sh <service_name> run <command>"
      exit 1
    fi
    docker exec "$CONTAINER_ID" "${@:3}"
  fi

elif [ "$COMMAND" == "logs" ]; then
  TAIL_LINES="${3:-100}"
  docker service logs --timestamps --no-task-ids --tail "$TAIL_LINES" --follow "$FULL_SERVICE_NAME"
elif [ "$COMMAND" == "restart" ]; then
  echo "Restarting service '$FULL_SERVICE_NAME'..."
  docker service update --force "$FULL_SERVICE_NAME"
  echo "Service restart initiated."

elif [ "$COMMAND" == "stop" ]; then
  echo "Stopping service '$FULL_SERVICE_NAME'..."
  docker service scale "${FULL_SERVICE_NAME}=0"
  echo "Service stopped."

elif [ "$COMMAND" == "start" ]; then
  # Get the configured replica count from service spec
  REPLICA_COUNT=$(docker service inspect "$FULL_SERVICE_NAME" \
    --format "{{.Spec.Mode.Replicated.Replicas}}" 2>/dev/null)

  if [ -z "$REPLICA_COUNT" ] || [ "$REPLICA_COUNT" == "<no value>" ]; then
    # Fallback to 1 if we can't determine or if it's a global service
    REPLICA_COUNT=1
  fi

  echo "Starting service '$FULL_SERVICE_NAME' with $REPLICA_COUNT replica(s)..."
  docker service scale "${FULL_SERVICE_NAME}=${REPLICA_COUNT}"
  echo "Service started."

else
  echo "Invalid command: $COMMAND"
  exit 1
fi
