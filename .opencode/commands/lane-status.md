---
description: Show the current lane, branch, changes, and build state
---

Show the current lane status.

!`pwd; git branch --show-current; git status -sb; git worktree list; git log --oneline -3`

Then:

1. If this is not inside `.slim/worktrees/`, say so and list the available lanes.
2. Summarize the uncommitted changes, the last three commits, and whether the branch is behind `origin/alpha-4.5`.
3. Do not edit, commit, deploy, or remove anything.
