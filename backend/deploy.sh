#!/usr/bin/env bash
#
# Deploy unraid-monitor backend to the Unraid host.
#
# Usage:
#   ./deploy.sh           # rsync + rebuild + restart + tail logs
#   ./deploy.sh --quick   # rsync + restart (no rebuild; use when only code changed)
#   ./deploy.sh --logs    # just tail the live logs
#   ./deploy.sh --status  # show container state
#   ./deploy.sh --ssh     # open a shell on the container
#
# Targets (UNRAID_HOST / REMOTE_PATH / CONTAINER) come from, in order:
#   1. the shell environment
#   2. backend/.env.local (if USE_ENV_LOCAL=1 is set)
#   3. backend/.env
#   4. the built-in fallbacks at the top of the script
#
# To deploy against a test box: `USE_ENV_LOCAL=1 ./deploy.sh`

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Pick up deploy targets from .env (production) or .env.local (test) if present.
# Only fills vars that aren't already set in the shell, so `UNRAID_HOST=x ./deploy.sh`
# overrides the file.
load_env_file() {
  local f=$1
  [[ -f "$f" ]] || return
  while IFS='=' read -r key val; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${key// }" ]] && continue
    # Already exported in the shell → leave alone
    [[ -n "${!key+x}" && -n "${!key:-}" ]] && continue
    # Strip surrounding quotes, if any
    val="${val%\"}"; val="${val#\"}"
    val="${val%\'}"; val="${val#\'}"
    export "$key=$val"
  done < "$f"
}
if [[ -n "${USE_ENV_LOCAL:-}" && -f "$SCRIPT_DIR/.env.local" ]]; then
  load_env_file "$SCRIPT_DIR/.env.local"
elif [[ -f "$SCRIPT_DIR/.env" ]]; then
  load_env_file "$SCRIPT_DIR/.env"
fi

: "${REMOTE_PATH:=/mnt/user/appdata/unraid-monitor/backend}"
: "${CONTAINER:=unraid-monitor-backend}"

color() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
step()  { color "1;34" "▶ $*"; }
ok()    { color "1;32" "✓ $*"; }
warn()  { color "1;33" "! $*"; }
die()   { color "1;31" "✗ $*"; exit 1; }

# UNRAID_HOST has no fallback — it identifies the target server and must come
# from .env (or the shell). Fail fast with a helpful message if missing.
if [[ -z "${UNRAID_HOST:-}" ]]; then
  die "UNRAID_HOST not set. Put it in backend/.env (e.g. UNRAID_HOST=root@<UNRAID_IP>) or export it before running."
fi

cmd_deploy() {
  local rebuild="$1"

  step "Typechecking locally"
  (cd "$SCRIPT_DIR" && npx --no-install tsc --noEmit) || die "Typecheck failed — fix before deploying"
  ok "Typecheck clean"

  step "Rsync sources to $UNRAID_HOST:$REMOTE_PATH"
  rsync -az --delete \
    --exclude=node_modules \
    --exclude=dist \
    --exclude=data \
    --exclude=.env \
    --exclude=deploy.sh \
    "$SCRIPT_DIR/" "$UNRAID_HOST:$REMOTE_PATH/"
  ok "Sources synced"

  if [[ "$rebuild" == "yes" ]]; then
    step "docker compose build + up on $UNRAID_HOST"
    ssh "$UNRAID_HOST" "cd $REMOTE_PATH && docker compose up -d --build"
  else
    step "docker compose up (no rebuild) on $UNRAID_HOST"
    ssh "$UNRAID_HOST" "cd $REMOTE_PATH && docker compose up -d"
  fi
  ok "Container restarted"

  step "Waiting for startup..."
  sleep 3

  step "Recent logs"
  ssh "$UNRAID_HOST" "docker logs --tail 15 $CONTAINER"

  step "Health check (from host, unauth)"
  if ssh "$UNRAID_HOST" 'curl -sf -o /dev/null http://localhost:3000/healthz'; then
    ok "healthz → 200"
  else
    warn "healthz NOT responding — check logs above"
  fi
}

cmd_logs() {
  step "Streaming logs from $CONTAINER (Ctrl+C to stop)"
  ssh -t "$UNRAID_HOST" "docker logs -f --tail 50 $CONTAINER"
}

cmd_status() {
  step "Container state"
  ssh "$UNRAID_HOST" "docker ps -a --filter name=^/${CONTAINER}\$ --format 'table {{.Names}}\t{{.Status}}\t{{.RunningFor}}\t{{.Ports}}'"
  step "Disk usage of appdata"
  ssh "$UNRAID_HOST" "du -sh $REMOTE_PATH/data 2>/dev/null || true"
  step "Restart policy"
  ssh "$UNRAID_HOST" "docker inspect $CONTAINER --format 'RestartPolicy={{.HostConfig.RestartPolicy.Name}}'"
}

cmd_ssh() {
  step "Shell in $CONTAINER"
  ssh -t "$UNRAID_HOST" "docker exec -it $CONTAINER sh"

  step "Prune unused images"
  ssh "$UNRAID_HOST" "docker image prune -f"
  ok "Unused images pruned"
}

case "${1:-}" in
  ""|--build) cmd_deploy yes ;;
  --quick)    cmd_deploy no  ;;
  --logs)     cmd_logs       ;;
  --status)   cmd_status     ;;
  --ssh)      cmd_ssh        ;;
  -h|--help)
    sed -n '2,12p' "$0"
    ;;
  *) die "Unknown option: $1 (try --help)" ;;
esac
