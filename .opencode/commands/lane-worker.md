---
description: Run a task in the current lane with a background lane-worker subagent
agent: lane-worker
subagent: true
---

Work in the current lane.

1. Confirm the current path is inside `.slim/worktrees/`. If not, stop and tell the parent to run `/lane <slug> <task>` first.
2. Read AGENTS.md and docs/PARALLEL_SESSIONS.md.
3. Do this task: $ARGUMENTS

Build with `./deploy.sh --no-install` only. Do not install, respring, or run the full `./deploy.sh`. Commit only if the task explicitly asks for a commit. Report the branch, files changed, commands run, and any blockers.
