#!/usr/bin/env bash
# One command to check the project. Runs every stage, prints a summary, exits non-zero if any stage failed.
#   scripts/verify.sh            backend tests + frontend lint + frontend build
#   scripts/verify.sh --e2e      also runs the e2e specs (needs this slot's backend running and seeded)
#   scripts/verify.sh --only backend|frontend|e2e
# Lint has a baseline of pre-existing errors (LINT_ERROR_BASELINE); it fails only if the count goes up.
# Example stack: Maven backend in backend/, npm frontend in frontend/, Playwright e2e. Adapt the commands.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT_ERROR_BASELINE=28   # lower it when you fix some, never raise it
RUN_E2E=false
ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --e2e) RUN_E2E=true ;;
    --only) ONLY="$2"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

source "$ROOT/scripts/lib/env.sh"
load_dev_env "$ROOT"

RESULTS=()
FAILED=0
stage() { echo; echo "==> $1"; }
record() {
  RESULTS+=("$1: $2")
  [[ "$2" == FAIL* ]] && FAILED=1
  return 0
}
wants() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

if wants backend; then
  stage "backend: tests (DB $DATABASE_URL)"
  if (cd "$ROOT/backend" && mvn -q test); then
    record "backend tests" "PASS"
  else
    record "backend tests" "FAIL (see test output above)"
  fi
fi

if wants frontend; then
  stage "frontend: lint (baseline $LINT_ERROR_BASELINE errors)"
  lint_errors=$(cd "$ROOT/frontend" && npx eslint . -f json 2>/dev/null \
    | python3 -c 'import json,sys; print(sum(f["errorCount"] for f in json.load(sys.stdin)))')
  if [[ -z "$lint_errors" ]]; then
    record "frontend lint" "FAIL (eslint did not run)"
  elif (( lint_errors > LINT_ERROR_BASELINE )); then
    record "frontend lint" "FAIL ($lint_errors errors, baseline $LINT_ERROR_BASELINE)"
  else
    record "frontend lint" "PASS ($lint_errors errors, baseline $LINT_ERROR_BASELINE)"
  fi

  stage "frontend: build"
  if (cd "$ROOT/frontend" && npm run -s build); then
    record "frontend build" "PASS"
  else
    record "frontend build" "FAIL"
  fi
fi

if [[ "$RUN_E2E" == true || "$ONLY" == "e2e" ]]; then
  stage "e2e"
  # Absolute paths + nullglob: a glob that matches nothing must not pass silently.
  shopt -s nullglob
  e2e_specs=("$ROOT"/frontend/e2e/*.spec.js)
  shopt -u nullglob
  if (( ${#e2e_specs[@]} == 0 )); then
    record "e2e" "FAIL (no spec files found)"
  elif ! curl -sf -o /dev/null "http://localhost:$BACKEND_PORT/api/health"; then
    record "e2e" "FAIL (backend not running on :$BACKEND_PORT)"
  elif (cd "$ROOT/frontend" && npx playwright test "${e2e_specs[@]}" --reporter=line); then
    record "e2e" "PASS (${#e2e_specs[@]} spec files)"
  else
    record "e2e" "FAIL"
  fi
fi

echo; echo "==> summary"
printf '  %s\n' "${RESULTS[@]}"
if (( FAILED )); then echo "verify: FAILED"; exit 1; fi
echo "verify: OK"
