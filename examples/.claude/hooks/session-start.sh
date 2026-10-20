#!/usr/bin/env bash
# SessionStart hook: plain stdout is added to Claude's context. Read-only, never blocks.
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" 2>/dev/null || exit 0
echo "Read wiki/index.md before exploring code. Last wiki events:"
grep "^## \[" wiki/log.md 2>/dev/null | tail -5
exit 0
