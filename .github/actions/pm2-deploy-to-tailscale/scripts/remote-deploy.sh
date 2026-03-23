set -euo pipefail

REPOSITORY_SLUG=$1
REPO_NAME=$2
DEPLOY_SHA=$3
DEPLOY_REF=$4

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$PATH:$HOME/.local/bin:$HOME/.bun/bin"

REPO_DIR="$HOME/$REPO_NAME"
OLD_HEAD='FIRST_RUN'
NEW_HEAD=''

declare -a APP_DIRS=()
declare -a SERVICE_DIRS=()
declare -a SERVICE_NAMES=()
declare -a SERVICE_ACTIONS=()

array_contains() {
  local needle=$1
  local item

  shift
  for item in "$@"; do
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done

  return 1
}

pm2_process_state() {
  local name=$1

  pm2 jlist | node -e '
    const fs = require("fs");
    const name = process.argv[1];
    const raw = fs.readFileSync(0, "utf8");
    const processes = JSON.parse(raw);
    const processInfo = processes.find((entry) => entry.name === name);

    if (!processInfo) {
      process.stdout.write("missing");
      process.exit(0);
    }

    const status = processInfo.pm2_env && processInfo.pm2_env.status
      ? processInfo.pm2_env.status
      : "unknown";
    process.stdout.write(status);
  ' "$name"
}

sync_repository() {
  if [ ! -d "$REPO_DIR/.git" ]; then
    echo 'Cloning repository...'
    git clone "https://github.com/${REPOSITORY_SLUG}" "$REPO_DIR"
    cd "$REPO_DIR"
  else
    echo 'Updating existing repository...'
    cd "$REPO_DIR"
    OLD_HEAD=$(git rev-parse HEAD 2>/dev/null || echo 'FIRST_RUN')
  fi

  git fetch --depth=1 origin "$DEPLOY_REF"
  git reset --hard FETCH_HEAD
  git config core.fileMode false

  NEW_HEAD=$(git rev-parse HEAD)

  if [ "$NEW_HEAD" != "$DEPLOY_SHA" ]; then
    echo "Error: fetched $DEPLOY_REF resolved to $NEW_HEAD, expected $DEPLOY_SHA"
    exit 1
  fi
}

discover_apps() {
  local build_file
  local dir_name

  while IFS= read -r -d '' build_file; do
    chmod +x "$build_file"
    dir_name=$(dirname "$build_file")
    dir_name=${dir_name#./}

    if [ "$dir_name" = "." ]; then
      continue
    fi

    if ! array_contains "$dir_name" "${APP_DIRS[@]}"; then
      APP_DIRS+=("$dir_name")
    fi
  done < <(
    find . \
      \( -path './.git' -o -path './node_modules' -o -path './.venv' -o -path './venv' \) -prune -o \
      -type f -name 'build.sh' -print0
  )

  if [ "${#APP_DIRS[@]}" -eq 0 ]; then
    echo 'Warning: No apps with build.sh found!'
  fi
}

plan_deploy() {
  local dir
  local pm2_name
  local process_state
  local has_changes

  for dir in "${APP_DIRS[@]}"; do
    echo "Checking component: $dir"
    pm2_name=${dir//\//-}
    process_state=$(pm2_process_state "$pm2_name")
    has_changes=0

    if [ "$OLD_HEAD" = 'FIRST_RUN' ] || ! git diff --quiet "$OLD_HEAD" "$NEW_HEAD" -- "$dir"; then
      has_changes=1
    fi

    SERVICE_DIRS+=("$dir")
    SERVICE_NAMES+=("$pm2_name")

    if [ "$process_state" = 'online' ] && [ "$has_changes" -eq 0 ]; then
      SERVICE_ACTIONS+=('skip')
      echo "-> No changes for '$dir' and '$pm2_name' is online. Skipping."
    elif [ "$process_state" = 'missing' ]; then
      SERVICE_ACTIONS+=('start')
      echo "-> '$pm2_name' is not registered in PM2. Will build and start it."
    elif [ "$process_state" = 'online' ]; then
      SERVICE_ACTIONS+=('reload')
      echo "-> Changes detected for '$dir'. Will build and reload '$pm2_name'."
    else
      SERVICE_ACTIONS+=('restart')
      echo "-> '$pm2_name' is currently '$process_state'. Will build and restart it."
    fi

    echo '----------------------------------------'
  done
}

build_targets() {
  local index
  local dir
  local action

  for index in "${!SERVICE_DIRS[@]}"; do
    dir=${SERVICE_DIRS[$index]}
    action=${SERVICE_ACTIONS[$index]}

    if [ "$action" = 'skip' ]; then
      continue
    fi

    echo "Building '$dir'..."
    (cd "$dir" && ./build.sh)
  done
}

apply_deploy() {
  local index
  local pm2_name
  local action

  for index in "${!SERVICE_NAMES[@]}"; do
    pm2_name=${SERVICE_NAMES[$index]}
    action=${SERVICE_ACTIONS[$index]}

    case "$action" in
      skip)
        continue
        ;;
      start)
        echo "Starting '$pm2_name'..."
        pm2 start ecosystem.config.js --only "$pm2_name" --update-env
        ;;
      reload)
        echo "Reloading '$pm2_name' with updated environment..."
        pm2 reload ecosystem.config.js --only "$pm2_name" --update-env 2>/dev/null || \
          pm2 restart ecosystem.config.js --only "$pm2_name" --update-env
        ;;
      restart)
        echo "Restarting '$pm2_name' with updated environment..."
        pm2 restart ecosystem.config.js --only "$pm2_name" --update-env
        ;;
      *)
        echo "Error: Unknown deploy action '$action' for '$pm2_name'"
        exit 1
        ;;
    esac
  done
}

sync_repository

echo '----------------------------------------'

discover_apps
plan_deploy
build_targets
apply_deploy

pm2 save > /dev/null
echo 'Deployment completed successfully!'
