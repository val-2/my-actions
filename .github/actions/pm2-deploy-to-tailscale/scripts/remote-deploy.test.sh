#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE_HOME="$TMP_DIR/home"
FIXTURE_REPO="$FIXTURE_HOME/repo"
FAKE_BIN="$TMP_DIR/bin"
TEST_LOG="$TMP_DIR/deploy.log"
TEST_SHA=0123456789abcdef0123456789abcdef01234567

mkdir -p "$FIXTURE_REPO/.git" "$FIXTURE_REPO/apps/web" "$FIXTURE_REPO/apps/worker" "$FAKE_BIN"
printf '24.14.1\n' > "$FIXTURE_REPO/.nvmrc"

cat > "$FIXTURE_REPO/ecosystem.config.js" <<'EOF'
module.exports = {
  apps: [
    { name: "web", cwd: `${__dirname}/apps/web` },
    { name: "worker", cwd: `${__dirname}/apps/worker` },
    { name: "manual", cwd: __dirname, deploy_managed: false },
  ],
};
EOF

cat > "$FIXTURE_REPO/build.sh" <<'EOF'
#!/usr/bin/env bash
printf 'build\n' >> "$TEST_LOG"
EOF

cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  rev-parse) printf '%s\n' "$TEST_SHA" ;;
  diff) exit 1 ;;
esac
EOF

cat > "$FAKE_BIN/pm2" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  jlist) printf '[]\n' ;;
  start|reload|restart) printf 'pm2 %s\n' "$*" >> "$TEST_LOG" ;;
esac
EOF

cat > "$FAKE_BIN/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$FAKE_BIN/nvm" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = 'use' ]; then
  printf 'nvm use\n' >> "$TEST_LOG"
fi
EOF

chmod +x "$FIXTURE_REPO/build.sh" "$FAKE_BIN/git" "$FAKE_BIN/pm2" "$FAKE_BIN/flock" "$FAKE_BIN/nvm"

HOME="$FIXTURE_HOME" \
PATH="$FAKE_BIN:$PATH" \
TEST_LOG="$TEST_LOG" \
TEST_SHA="$TEST_SHA" \
bash "$SCRIPT_DIR/remote-deploy.sh" owner/repo repo "$TEST_SHA" refs/heads/main push 1 >/dev/null

test "$(grep -c '^build$' "$TEST_LOG")" -eq 1
test "$(grep -c '^nvm use$' "$TEST_LOG")" -eq 1
test "$(grep -n '^nvm use$' "$TEST_LOG" | cut -d: -f1)" -lt "$(grep -n '^build$' "$TEST_LOG" | cut -d: -f1)"
test "$(grep -c -- '--only web ' "$TEST_LOG")" -eq 1
test "$(grep -c -- '--only worker ' "$TEST_LOG")" -eq 1
! grep -q -- '--only manual ' "$TEST_LOG"
