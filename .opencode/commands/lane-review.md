---
description: Run the verifier subagent over the current lane changes
agent: verifier
subagent: true
---

Review the changes in this lane.

1. Confirm the current path is inside `.slim/worktrees/`. If not, stop and say so.
2. Read AGENTS.md and docs/PARALLEL_SESSIONS.md.
3. Review `git diff origin/alpha-4.5...HEAD` and the changed files.
4. Report correctness, regressions, missing tests, and device/config risks, in severity order with file and line references.
5. Do not edit, commit, deploy, or remove anything.
