---
description: Start an isolated worktree lane and move this session into it
---

Current checkout:

!`pwd; git branch --show-current; git status --short; git worktree list`

Lane slug: $1
Task: $2

You are switching this session into an isolated RemoteCompanion lane.

1. Read AGENTS.md and docs/PARALLEL_SESSIONS.md.
2. If the current path is already inside `.slim/worktrees/`, stop and tell me which lane this session is in. Do not create a nested lane.
3. If `.slim/worktrees/$1` already exists, verify it is a git worktree with `git -C ".slim/worktrees/$1" rev-parse --is-inside-work-tree`. If it is, reuse it exactly as it is. If it is not, stop and tell me. Do not reset, clean, or delete anything.
4. Otherwise create it from `alpha-4.5` with the shell tool:

   ./tools/new-lane.sh "$1" alpha-4.5

5. Move this session to the absolute path of `.slim/worktrees/$1` with the session move tool. Do not keep editing the main checkout.
6. Verify `pwd`, `git branch --show-current`, and `git status --short` inside the lane.
7. Do the task: $2

If the task is empty, ask what to work on after the move.

Do not run the full `./deploy.sh` (it installs and resprings) unless I explicitly ask. `./deploy.sh --no-install` is fine for builds.
