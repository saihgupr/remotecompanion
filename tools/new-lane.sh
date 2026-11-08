#!/bin/bash
# Create an isolated worktree lane for one OpenCode session.
# Usage: tools/new-lane.sh <slug> [base-ref]

set -euo pipefail

usage() {
    cat <<'USAGE'
Create an isolated lane for RemoteCompanion.

Usage:
  tools/new-lane.sh <slug> [base-ref]

Examples:
  tools/new-lane.sh trigger-onboarding alpha-4.5
  tools/new-lane.sh picker-polish origin/alpha-4.5

Creates:
  branch: feature/<slug>
  path:   .slim/worktrees/<slug>
USAGE
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

SLUG="${1:-}"
BASE="${2:-alpha-4.5}"

if [ -z "$SLUG" ]; then
    usage
    exit 1
fi

case "$SLUG" in
    *[!a-z0-9-]*)
        echo "Slug must use lowercase letters, numbers and dashes only."
        exit 1
        ;;
esac

BRANCH="feature/$SLUG"
LANE="$REPO_ROOT/.slim/worktrees/$SLUG"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Not inside a git repository."
    exit 1
fi

if [ -e "$LANE" ]; then
    echo "Lane already exists: $LANE"
    exit 1
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Branch already exists: $BRANCH"
    exit 1
fi

if ! git rev-parse --verify --quiet "$BASE" >/dev/null; then
    echo "Base ref not found: $BASE"
    exit 1
fi

# Keep lane metadata local, never committed.
GITIGNORE_BLOCK='# BEGIN parallel OpenCode lanes
.slim/worktrees/
.slim/worktrees.json
# END parallel OpenCode lanes'
if ! grep -qF '.slim/worktrees/' .gitignore 2>/dev/null; then
    printf '\n%s\n' "$GITIGNORE_BLOCK" >> .gitignore
    echo "Added .slim/worktrees/ to .gitignore."
fi

IGNORE_BLOCK='# BEGIN parallel OpenCode lanes
!.slim/
!.slim/worktrees.json
!.slim/worktrees/
!.slim/worktrees/**
# END parallel OpenCode lanes'
if ! grep -qF '.slim/worktrees/' .ignore 2>/dev/null; then
    printf '%s\n' "$IGNORE_BLOCK" >> .ignore
    echo "Updated .ignore so OpenCode can see the lane files."
fi

mkdir -p "$(dirname "$LANE")"
git worktree add -b "$BRANCH" "$LANE" "$BASE"

echo
echo "Lane ready."
echo "  branch: $BRANCH"
echo "  path:   $LANE"
echo
echo "Next:"
echo "  1. Open a new OpenCode session in: $LANE"
echo "  2. Or move the current session there."
echo "  3. Build without touching the phone: ./deploy.sh --no-install"
echo
echo "See docs/PARALLEL_SESSIONS.md for the daily loop and cleanup."
