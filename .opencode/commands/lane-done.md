---
description: Verify the current lane, commit it, and prepare it for integration
---

Finish the current lane. Do not run the full `./deploy.sh`.

1. Confirm the current path is inside `.slim/worktrees/`. If not, stop.
2. Read AGENTS.md and docs/PARALLEL_SESSIONS.md.
3. Show `git status --short`, `git diff --stat`, and `git log --oneline origin/alpha-4.5..HEAD`.
4. Build and run the lane checks:

   cd RemoteCompanion && make stage -j1
   cd ..
   ./deploy.sh --no-install

5. If there are changes, commit them with a plain human message. No `fix:`, `feat:`, or other prefixes.
6. Rebase onto `origin/alpha-4.5`. Resolve conflicts inside the lane, and stop if a conflict is ambiguous.
7. Show the final diff summary and the branch name. Do not merge, push, or remove the worktree unless I explicitly ask.
