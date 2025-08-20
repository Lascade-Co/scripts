#!/bin/bash

set -Eeuo pipefail

COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[1;34m'
COLOR_RED='\033[1;31m'
COLOR_GREEN='\033[1;32m'
NO_COLOR='\033[0m'

# Lightweight logging helpers
log() { echo -e "${COLOR_BLUE}$*${NO_COLOR}"; }
warn() { echo -e "${COLOR_YELLOW}$*${NO_COLOR}"; }
err() { echo -e "${COLOR_RED}$*${NO_COLOR}" >&2; }

if [ -f /opt/project_folder ]; then
  PROJECT_FOLDER=$(cat /opt/project_folder)
else
  warn "Project folder not set, using current directory"
  PROJECT_FOLDER=$(pwd)
fi

cd "$PROJECT_FOLDER"

# Parse options (optional). Supports:
# --infisical_project_id=, --infisical_env=, --infisical_domain=, --infisical_token=, --ref=
# Backward-compatible: first positional arg is treated as Git ref.
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --infisical_project_id=*) INFISICAL_PROJECT_ID="${arg#*=}";;
    --infisical_env=*) INFISICAL_ENV="${arg#*=}";;
    --infisical_domain=*) INFISICAL_DOMAIN="${arg#*=}";;
    --infisical_token=*) INFISICAL_TOKEN="${arg#*=}";;
    --ref=*) GIT_REF="${arg#*=}";;
    -h|--help)
      echo "Usage: $0 [--ref=<git_ref>] [--infisical_project_id=ID] [--infisical_env=ENV] [--infisical_domain=DOMAIN] [--infisical_token=TOKEN]"
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      err "Unknown option: $arg"
      exit 1
      ;;
    *)
      POSITIONAL+=("$arg")
      ;;
  esac
done
# Back-compat: if --ref not provided, use first positional (if any)
if [ -z "${GIT_REF:-}" ] && [ ${#POSITIONAL[@]} -gt 0 ]; then
  GIT_REF="${POSITIONAL[0]}"
fi

# If a ref is provided, checkout that ref (only if this is a git repo)
if [ -n "${GIT_REF:-}" ]; then
  if [ -d .git ]; then
    # Start ssh-agent only if not already present
    if [ -z "${SSH_AUTH_SOCK:-}" ]; then
      eval "$(ssh-agent -s)"
    fi
    # Add GitHub key if present
    if [ -f "$HOME/.ssh/github" ]; then
      ssh-add "$HOME/.ssh/github" >/dev/null 2>&1 || warn "Could not add SSH key $HOME/.ssh/github"
    else
      warn "SSH Key $HOME/.ssh/github not found"
    fi
    git fetch --all --tags --prune
    if ! (git checkout "$GIT_REF" && git pull); then
      err "Failed to checkout and pull ref: $GIT_REF"
      exit 1
    fi
    git submodule update --init --recursive
    log "Checked out ref: $GIT_REF"
  else
    warn "Not a git repository at $PROJECT_FOLDER; skipping checkout of ref '$GIT_REF'"
  fi
fi

# Load environment:
# - If INFISICAL_* vars are fully provided (via flags or .env), use Infisical export.
# - Otherwise, fall back to sourcing .env if present.
if [ -n "${INFISICAL_PROJECT_ID:-}" ] && [ -n "${INFISICAL_ENV:-}" ] && [ -n "${INFISICAL_DOMAIN:-}" ] && [ -n "${INFISICAL_TOKEN:-}" ]; then
  # Ensure Infisical CLI is available before attempting export
  if ! command -v infisical &> /dev/null; then
    err "Infisical CLI not found. Install it or provide a .env file instead."
    exit 1
  fi
  # Sanitize domain: strip surrounding quotes and trailing slashes
  SANITIZED_DOMAIN="${INFISICAL_DOMAIN%/}"
  # Strip matching surrounding quotes
  if [[ "${SANITIZED_DOMAIN}" == \'*\' || "${SANITIZED_DOMAIN}" == \"*\" ]]; then
    SANITIZED_DOMAIN="${SANITIZED_DOMAIN:1:-1}"
  fi

  # Perform export and capture output; bail out on failure to avoid eval of error text
  infisical export \
    --projectId="${INFISICAL_PROJECT_ID}" \
    --env="${INFISICAL_ENV}" \
    --domain="${SANITIZED_DOMAIN}" \
    --token="${INFISICAL_TOKEN}" > .env
  
else
  if [ ! -f ".env" ]; then
    err "Error: INFISICAL_* not fully provided and .env not found. Aborting."
    exit 1
  else
    log "Loaded variables from .env (Infisical export skipped)."
  fi
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

docker stack deploy -c swarm.docker-compose.yml "$STACK_NAME" --with-registry-auth -d

echo -e "${COLOR_GREEN}Deployment successful.${NO_COLOR}"

echo "Run 'docker service ls' to check the services"
echo "Run shell <service_name> [optional] <command> to attach to a service"
