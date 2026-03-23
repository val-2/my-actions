#!/usr/bin/env bash
set -euo pipefail

: "${SERVER_IP:?Environment variable SERVER_IP is required}"
: "${SSH_USER:?Environment variable SSH_USER is required}"
: "${REPOSITORY_SLUG:?Environment variable REPOSITORY_SLUG is required}"
: "${DEPLOY_SHA:?Environment variable DEPLOY_SHA is required}"
: "${DEPLOY_REF:?Environment variable DEPLOY_REF is required}"

CONNECTION="$SSH_USER@$SERVER_IP"
REPO_NAME="${REPOSITORY_SLUG#*/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_SCRIPT="$SCRIPT_DIR/remote-deploy.sh"
SSH_OPTIONS=(
  -o
  StrictHostKeyChecking=no
  -o
  ConnectTimeout=10
)

echo "Attempting to connect to $CONNECTION"

if ! ssh "${SSH_OPTIONS[@]}" "$CONNECTION" 'echo "SSH connection successful"'; then
  echo "Error: Cannot establish SSH connection"
  exit 1
fi

ssh "${SSH_OPTIONS[@]}" "$CONNECTION" bash -s -- "$REPOSITORY_SLUG" "$REPO_NAME" "$DEPLOY_SHA" "$DEPLOY_REF" < "$REMOTE_SCRIPT"
