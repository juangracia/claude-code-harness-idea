#!/usr/bin/env bash
# Stop hook: nudge Claude once per change set to file durable learnings in wiki/.
# Blocks (decision "block") only when work exists outside wiki/ that is newer than wiki/log.md
# and this session was not already nudged for the same work. Fails open (exit 0) on any error.

warn() { echo "wiki-ingest-check: $1, allowing" >&2; exit 0; }

command -v jq >/dev/null 2>&1 || warn "jq not found"
input=$(cat)
parsed=$(printf '%s' "$input" | jq -r '[(.stop_hook_active // false | tostring), (.session_id // "")] | @tsv' 2>/dev/null) \
  || warn "could not parse input"
active=${parsed%%$'\t'*}
session=${parsed#*$'\t'}

[ "$active" = "true" ] && exit 0
case "$session" in
  ""|*[!A-Za-z0-9._-]*) warn "bad session_id" ;;
esac

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" 2>/dev/null || warn "cannot cd to project"
git rev-parse --git-dir >/dev/null 2>&1 || warn "not a git repo"

dirty=$(git status --porcelain -- . ':(exclude)wiki' 2>/dev/null) || warn "git status failed"
log_ct=$(git log -1 --format=%ct -- wiki/log.md 2>/dev/null)
head_ct=$(git log -1 --format=%ct 2>/dev/null)
log_ct=${log_ct:-0}
head_ct=${head_ct:-0}

newer_commits=0
[ "$head_ct" -gt "$log_ct" ] && newer_commits=1
[ -z "$dirty" ] && [ "$newer_commits" = 0 ] && exit 0

# An uncommitted wiki/log.md edit newer than HEAD counts as an ingest that already happened.
log_mtime=$(stat -f %m wiki/log.md 2>/dev/null || stat -c %Y wiki/log.md 2>/dev/null || echo 0)
if [ -z "$dirty" ] && [ "$log_mtime" -ge "$head_ct" ]; then
  exit 0
fi

sig=$(printf '%s\n%s' "$dirty" "$(git rev-parse HEAD 2>/dev/null)" | cksum | cut -d' ' -f1)
marker="${TMPDIR:-/tmp}/wiki-nudge-$session"
[ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$sig" ] && exit 0
printf '%s' "$sig" > "$marker" 2>/dev/null || warn "cannot write marker"

reason="Before stopping: if this work produced a durable learning (gotcha, decision, domain rule, new command), run the wiki-ingest skill (or the wiki-curator agent, model haiku) and append a wiki/log.md entry. If nothing durable, say 'no wiki update needed' and stop."
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
