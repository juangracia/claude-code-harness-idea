# Loads per-machine overrides from $ROOT/.dev.env (gitignored) and derives the ports and
# connection URL the backend, frontend and tests use. Every script sources this file, so the
# same script works for the main stack (slot 0) and for any worktree slot.
load_dev_env() {
  local root="$1"
  if [[ -f "$root/.dev.env" ]]; then
    set -a
    source "$root/.dev.env"
    set +a
  fi
  export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
  export BACKEND_PORT="${BACKEND_PORT:-8080}"
  export FRONTEND_PORT="${FRONTEND_PORT:-3000}"
  export DB_NAME="${DB_NAME:-app}"
  # Docker container that holds the database. Slot 0 uses the compose one; a worktree slot has its own.
  export PG_CONTAINER="${PG_CONTAINER:-app-postgres}"
  export DATABASE_URL="${DATABASE_URL:-jdbc:postgresql://localhost:${POSTGRES_PORT}/${DB_NAME}}"
  # Tie the server port to this slot so a stray PORT from the caller's shell cannot clash.
  export PORT="$BACKEND_PORT"
}
