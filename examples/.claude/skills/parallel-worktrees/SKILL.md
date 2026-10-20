---
name: parallel-worktrees
description: Run extra stacks (own backend, frontend and database) in separate git worktrees so parallel sessions can test independently. Use when starting parallel feature work, when two sessions fight over :8080/:3000 or the same database, or when asked to create, start, seed, verify, list or remove a worktree stack.
---

# Parallel worktrees

One database container per slot (own volume, memory cap, small buffers), so databases never mix. Slot 0 is the main stack.

| Slot | Backend | Frontend | Database |
|---|---|---|---|
| 0 (main) | 8080 | 3000 | main container |
| N (1..4) | 8080+N | 3000+N | `app-pg-wtN` :5440+N |

## Commands

```bash
scripts/wt.sh new <name> [base-ref]   # worktree .claude/worktrees/<name>, branch feat/<name>, next free slot
scripts/wt.sh up <name> [--force]     # starts the slot's database, backend and frontend in the background
scripts/wt.sh seed <name>             # resets and seeds only that slot's database
scripts/wt.sh verify <name> [--e2e]   # scripts/verify.sh inside the worktree against its own stack
scripts/wt.sh down <name>
scripts/wt.sh rm <name> [--force]     # down, delete its container and volume, remove the worktree; the branch stays
```

Flow: `new`, `up`, `seed`, work in `.claude/worktrees/<name>`, `verify <name> --e2e`, then `rm`. Logs and pid files: `<worktree>/.stack/` (gitignored).

## Rules

- The base ref must already contain `scripts/wt.sh`. Uncommitted harness changes in another worktree are not copied.
- Inside a slot worktree every script reads that worktree's `.dev.env`. Do not hand-edit its port keys.
- Re-run `seed` after schema changes.
- Record the SHA you tested. If HEAD moves, test again.

## Limits

- `MAX_STACKS=4`: `new` refuses a fifth slot, `up` refuses a fifth running stack.
- `MIN_FREE_MEM_PCT=15`: `up` refuses below that free memory. `--force` skips both checks.
- Run `scripts/resource-watch.sh` under a monitor while stacks are up.

## Cleanup

`rm` refuses with uncommitted changes. Delete the branch when merged: `git branch -D feat/<name>`. Check `docker ps -a` and `docker volume ls` for leftovers.
