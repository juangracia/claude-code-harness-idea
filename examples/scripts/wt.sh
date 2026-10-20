#!/usr/bin/env bash
# Parallel worktree stacks (trimmed example). Each worktree gets a slot: its own backend port,
# frontend port and database container (own volume), so databases never mix. Slot 0 is the main stack.
#   scripts/wt.sh new <name> [base-ref]   worktree .claude/worktrees/<name>, branch feat/<name>, next free slot
#   scripts/wt.sh up <name> [--force]     start the slot's database, backend and frontend in the background
#   scripts/wt.sh seed <name>             reset and seed only that slot's database
#   scripts/wt.sh verify <name> [--e2e]   scripts/verify.sh inside that worktree against its own stack
#   scripts/wt.sh down <name>
#   scripts/wt.sh rm <name> [--force]     down, delete its container and volume, remove the worktree (branch stays)
# Limits (override in .dev.env): MAX_STACKS=4, MIN_FREE_MEM_PCT=15.
# Omitted from this example: ls (memory per stack), dependency cloning, process-tree stop.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/env.sh"
load_dev_env "$ROOT"

MAX_STACKS="${MAX_STACKS:-4}"
MIN_FREE_MEM_PCT="${MIN_FREE_MEM_PCT:-15}"
MAIN_ROOT="$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)/.." && pwd)"
WT_DIR="$MAIN_ROOT/.claude/worktrees"

die() { echo "wt: $*" >&2; exit 1; }
dev_env_get() { grep -s "^$2=" "$1/.dev.env" | tail -1 | cut -d= -f2- || true; }
slot_names() {
  local d
  for d in "$WT_DIR"/*/; do
    d="${d%/}"
    [[ -n "$(dev_env_get "$d" SLOT)" && "$(dev_env_get "$d" SLOT)" != 0 ]] && basename "$d"
  done
  return 0
}
wt_path() {
  local dir="$WT_DIR/$1"
  [[ -d "$dir" && -n "$(dev_env_get "$dir" SLOT)" ]] || die "no slot worktree named '$1'"
  echo "$dir"
}
# Runs a command with the slot's own settings, not the caller's (env leaks are a real bug source).
in_slot() {
  local dir="$1"; shift
  ( unset DATABASE_URL PORT BACKEND_PORT FRONTEND_PORT DB_NAME PG_CONTAINER
    load_dev_env "$dir"
    "$@" )
}
pid_of() { local f="$1/.stack/$2.pid"; [[ -f "$f" ]] && cat "$f" || true; }
alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }
port_free() { ! lsof -ti "tcp:$1" -sTCP:LISTEN >/dev/null 2>&1; }
# macOS. On Linux read MemAvailable from /proc/meminfo instead.
free_mem_pct() { memory_pressure | awk '/free percentage/ { gsub("%", "", $5); print $5 }'; }
wait_for() { local i; for ((i = 0; i < $3; i++)); do curl -sf -o /dev/null "$1" && return 0; alive "$2" || return 1; sleep 1; done; return 1; }

# One small database per slot: hard memory cap, small buffers, few connections.
pg_create() { # container port
  docker run -d --name "$1" --memory 256m -p "$2:5432" -v "$1-data:/var/lib/postgresql/data" \
    -e POSTGRES_USER=app -e POSTGRES_PASSWORD=app -e POSTGRES_DB=app \
    postgres:15 -c shared_buffers=32MB -c max_connections=30 >/dev/null
}
pg_wait() { local i; for i in {1..60}; do docker exec "$1" pg_isready -U app >/dev/null 2>&1 && return 0; sleep 1; done; die "database $1 not ready"; }

cmd_new() {
  local name="${1:-}" base="${2:-main}" slot used dir
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "usage: wt.sh new <name> [base-ref]"
  dir="$WT_DIR/$name"
  [[ ! -e "$dir" ]] || die "$dir already exists"
  used=" $(for n in $(slot_names); do dev_env_get "$WT_DIR/$n" SLOT; done | tr '\n' ' ') "
  for ((slot = 1; slot <= MAX_STACKS; slot++)); do
    [[ "$used" != *" $slot "* ]] && port_free $((8080 + slot)) && port_free $((3000 + slot)) && port_free $((5440 + slot)) && break
  done
  (( slot <= MAX_STACKS )) || die "all $MAX_STACKS slots are taken. Remove one: wt.sh rm <name>"

  git -C "$ROOT" worktree add "$dir" -b "feat/$name" "$base"
  cat > "$dir/.dev.env" <<EOF
SLOT=$slot
BACKEND_PORT=$((8080 + slot))
FRONTEND_PORT=$((3000 + slot))
PG_CONTAINER=app-pg-wt$slot
POSTGRES_PORT=$((5440 + slot))
EOF
  pg_create "app-pg-wt$slot" $((5440 + slot))
  pg_wait "app-pg-wt$slot"
  echo "wt: '$name' is slot $slot. Backend :$((8080 + slot)), frontend :$((3000 + slot)), db :$((5440 + slot))."
}

cmd_up() {
  local name="${1:-}" force=false dir slot running=0 n pct
  [[ "${2:-}" == "--force" ]] && force=true
  dir="$(wt_path "$name")"; slot="$(dev_env_get "$dir" SLOT)"
  alive "$(pid_of "$dir" backend)" && die "'$name' is already up"
  if [[ "$force" == false ]]; then
    for n in $(slot_names); do alive "$(pid_of "$WT_DIR/$n" backend)" && running=$((running + 1)); done
    (( running < MAX_STACKS )) || die "$running stacks already up (MAX_STACKS=$MAX_STACKS)"
    pct="$(free_mem_pct)"
    (( pct >= MIN_FREE_MEM_PCT )) || die "free memory is ${pct}% (min $MIN_FREE_MEM_PCT). Close something or use --force."
  fi
  docker start "$(dev_env_get "$dir" PG_CONTAINER)" >/dev/null; pg_wait "$(dev_env_get "$dir" PG_CONTAINER)"
  mkdir -p "$dir/.stack"
  # Small JVM so several stacks fit. Replace with your own server start command.
  in_slot "$dir" bash -c 'cd "$1/backend" && nohup java -Xmx512m -XX:+UseSerialGC -jar target/app.jar > "$1/.stack/backend.log" 2>&1 & echo $! > "$1/.stack/backend.pid"' _ "$dir"
  wait_for "http://localhost:$((8080 + slot))/api/health" "$(pid_of "$dir" backend)" 180 || die "backend did not start, see $dir/.stack/backend.log"
  # Strict port: fail instead of silently moving onto another slot's port.
  in_slot "$dir" bash -c 'cd "$1/frontend" && nohup npx vite --port "$FRONTEND_PORT" --strictPort > "$1/.stack/frontend.log" 2>&1 & echo $! > "$1/.stack/frontend.pid"' _ "$dir"
  wait_for "http://localhost:$((3000 + slot))/" "$(pid_of "$dir" frontend)" 60 || die "frontend did not start"
  echo "wt: '$name' up. UI http://localhost:$((3000 + slot))"
}

cmd_down() {
  local dir; dir="$(wt_path "${1:-}")"
  kill "$(pid_of "$dir" frontend)" "$(pid_of "$dir" backend)" 2>/dev/null || true
  rm -f "$dir/.stack/"*.pid
  docker stop "$(dev_env_get "$dir" PG_CONTAINER)" >/dev/null 2>&1 || true  # data stays in the volume
}

cmd_seed() {
  local dir slot; dir="$(wt_path "${1:-}")"; slot="$(dev_env_get "$dir" SLOT)"
  python3 "$ROOT/scripts/seed.py" --reset --api "http://localhost:$((8080 + slot))/api" --container "$(dev_env_get "$dir" PG_CONTAINER)"
}

cmd_verify() {
  local dir; dir="$(wt_path "${1:-}")"; shift
  ( cd "$dir" && in_slot "$dir" scripts/verify.sh "$@" )
}

cmd_rm() {
  local dir pg; dir="$(wt_path "${1:-}")"; pg="$(dev_env_get "$dir" PG_CONTAINER)"
  [[ "${2:-}" == "--force" || -z "$(git -C "$dir" status --porcelain)" ]] || die "'$1' has uncommitted changes"
  cmd_down "$1"
  docker rm -f "$pg" >/dev/null 2>&1 || true
  docker volume rm "$pg-data" >/dev/null 2>&1 || true
  git -C "$ROOT" worktree remove --force "$dir"
  echo "wt: '$1' removed. Branch feat/$1 is kept."
}

case "${1:-}" in
  new|up|down|seed|verify|rm) c="$1"; shift; "cmd_$c" "$@" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
