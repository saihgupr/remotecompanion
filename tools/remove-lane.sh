#!/bin/bash
# Remove a worktree lane created by tools/new-lane.sh.
# Usage: tools/remove-lane.sh <slug> [--delete-branch]

set -euo pipefail

usage() {
    cat <<'USAGE'
Remove a RemoteCompanion lane.

Usage:
  tools/remove-lane.sh <slug> [--delete-branch]

The lane must have no uncommitted changes. The branch is only deleted when
--delete-branch is passed, and git will refuse if it is not fully merged.
USAGE
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SLUG="${1:-}"
DELETE_BRANCH=false

if [ "${2:-}" = "--delete-branch" ]; then
    DELETE_BRANCH=true
fi

if [ -z "$SLUG" ]; then
    usage
    exit 1
fi

BRANCH="feature/$SLUG"
LANE="$REPO_ROOT/.slim/worktrees/$SLUG"

if [ ! -d "$LANE" ]; then
    echo "Lane not found: $LANE"
    exit 1
fi

if [ -n "$(git -C "$LANE" status --porcelain)" ]; then
    echo "Lane has uncommitted changes. Commit or stash them inside the lane first."
    exit 1
fi

git worktree remove "$LANE"

if [ "$DELETE_BRANCH" = true ]; then
    git branch -d "$BRANCH"
fi

echo "Removed lane: $SLUG"
if [ "$DELETE_BRANCH" = false ]; then
    echo "Branch kept: $BRANCH"
fi
