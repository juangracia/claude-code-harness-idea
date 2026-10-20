#!/usr/bin/env bash
# PreToolUse hook for the Agent tool: deny calls that do not choose a model on purpose.
# Allows: model set, subagent_type "fork", or an agent definition with `model:` in frontmatter.
# Fails open (allow) if jq is missing or the input is not parsable.

if ! command -v jq >/dev/null 2>&1; then
  echo "require-agent-model: jq not found, allowing" >&2
  exit 0
fi

input=$(cat)
if ! parsed=$(printf '%s' "$input" | jq -r '[(.tool_input.model // ""), (.tool_input.subagent_type // "")] | @tsv' 2>/dev/null); then
  echo "require-agent-model: could not parse input, allowing" >&2
  exit 0
fi

model=${parsed%%$'\t'*}
subagent=${parsed#*$'\t'}

[ -n "$model" ] && exit 0
[ "$subagent" = "fork" ] && exit 0

if [ -n "$subagent" ]; then
  name=${subagent##*:}
  case "$name" in
    *[!A-Za-z0-9._-]*) name="" ;;
  esac
  if [ -n "$name" ]; then
    for dir in "${CLAUDE_PROJECT_DIR:-}/.claude/agents" "$HOME/.claude/agents"; do
      f="$dir/$name.md"
      if [ -f "$f" ] && awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{exit f?0:1} /^model:[[:space:]]*[^[:space:]]/{f=1}' "$f"; then
        exit 0
      fi
    done
  fi
fi

reason='Set `model` on this Agent call: haiku for mechanical work, sonnet for bounded code/tests/docs, opus only for design or hard judgment. Forks and agents with model in frontmatter are exempt.'
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
