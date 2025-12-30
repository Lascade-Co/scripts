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
  echo "  scale <replicas>: Scale the service to specified replica count"
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
  docker service logs --timestamps --no-task-ids --tail "$TAIL_LINES" --follow "$FULL_SERVICE_NAME" | \
    sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+Z /\1 \2 /'
elif [ "$COMMAND" == "restart" ]; then
  # Get current replica count before stopping
  CURRENT_REPLICAS=$(docker service ls --filter "name=${FULL_SERVICE_NAME}" --format "{{.Replicas}}" | cut -d'/' -f2)

  if [ -z "$CURRENT_REPLICAS" ] || [ "$CURRENT_REPLICAS" -lt 1 ]; then
    CURRENT_REPLICAS=1
  fi

  echo "Restarting service '$FULL_SERVICE_NAME'..."
  echo "Stopping service..."
  docker service scale "${FULL_SERVICE_NAME}=0"

  echo "Waiting for service to stop..."
  sleep 2

  echo "Starting service with $CURRENT_REPLICAS replica(s)..."
  docker service scale "${FULL_SERVICE_NAME}=${CURRENT_REPLICAS}"
  echo "Service restarted."

elif [ "$COMMAND" == "scale" ]; then
  if [ -z "$3" ]; then
    echo "Usage: shell.sh <service_name> scale <replicas>"
    echo "Example: shell.sh server scale 0  # Stop service"
    echo "         shell.sh server scale 3  # Scale to 3 replicas"
    exit 1
  fi

  REPLICA_COUNT="$3"

  # Validate replica count is a number
  if ! [[ "$REPLICA_COUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: Replica count must be a valid number"
    exit 1
  fi

  echo "Scaling service '$FULL_SERVICE_NAME' to $REPLICA_COUNT replica(s)..."
  docker service scale "${FULL_SERVICE_NAME}=${REPLICA_COUNT}"
  echo "Service scaled."

else
  echo "Invalid command: $COMMAND"
  exit 1
fi
