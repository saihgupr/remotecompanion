# Running several sessions on this repo

Use one worktree per session. Two sessions in the same checkout will keep
committing into each other's branch and overwriting each other's uncommitted
work.

## OpenCode commands

Invoke these from the OpenCode composer:

| Command | What it does |
| --- | --- |
| `/lane <slug> <task>` | Creates the lane, moves this session into it, then starts the task |
| `/lane-status` | Shows the current lane, branch, changes, and build state |
| `/lane-worker <task>` | Runs the task in a background `lane-worker` subagent inside the current lane |
| `/lane-review` | Runs the `verifier` subagent over the current lane changes |
| `/lane-done` | Verifies the lane, commits, rebases onto `alpha-4.5`, and prepares integration |

## Ground rules

1. One session, one worktree, one branch.
2. Never run two sessions in the same directory.
3. Only one lane may deploy or respring the phone at a time.
4. Only one lane may swap the phone's `rc_triggers.plist` for a preview at a time.
5. Commit small. Rebase early onto `alpha-4.5`.
6. Use subagents for read-only review inside a lane. Do not let two agents edit
   the same files.

## Start a lane

From the main checkout:

```bash
git fetch origin
./tools/new-lane.sh trigger-onboarding alpha-4.5
```

Or from OpenCode:

```text
/lane trigger-onboarding build the onboarding empty state
```

The script creates:

- branch `feature/trigger-onboarding`
- worktree `.slim/worktrees/trigger-onboarding`

The `/lane` command then moves this session into that folder.

## Daily loop

Run these inside the lane:

```bash
git fetch origin
git rebase origin/alpha-4.5

# edit, build
cd RemoteCompanion
make stage -j1

# build packages without touching the phone
cd ..
./deploy.sh --no-install

# or, only when this lane owns the phone right now
./deploy.sh

git add -A
git commit
```

Do not run `git checkout` in the main checkout while another session is using
it. Do not copy `.theos` or `packages` between lanes; each lane builds its own.

## Integration

1. Rebase the lane onto `origin/alpha-4.5`.
2. Build and run the lane's checks.
3. Push the branch and open a PR into `alpha-4.5`, or merge locally if that is
   the chosen release flow.
4. If another lane changed the same file first, rebase the second lane after
   the first lands and resolve the conflict there.

Suggested file ownership when two features are in flight:

| Lane | Owns |
| --- | --- |
| Triggers / onboarding | `RCTriggersViewController.m`, `RCConfigManager.m`, `rc_webui.html` trigger list |
| Action picker / integrations | `RCActionPickerViewController.m`, action picker Web UI |
| Variable / terminal work | `RCVariableIcon.*`, `RCTerminalCommandEditor*`, `RCActionsViewController.m` |

If two lanes must touch the same file, serialize them. One lands, the other
rebases.

## Device and config safety

`./deploy.sh` installs the package, resprings the phone, and reopens the app.
`./deploy.sh --no-install` only builds the packages.

Before any preview that swaps `rc_triggers.plist`:

```bash
CFG=/var/mobile/Documents/rc_triggers.plist
cp -p "$CFG" "$CFG.preview-backup"
cmp "$CFG" "$CFG.preview-backup"
rc list-triggers | sort | cksum
```

After the screenshot:

```bash
cp -p "$CFG.preview-backup" "$CFG"
cmp "$CFG.preview-backup" "$CFG"
rc list-triggers | sort | cksum
```

The two checksums must match. Never leave the phone on the preview config.

## Clean up

```bash
./tools/remove-lane.sh trigger-onboarding --delete-branch
```

The script refuses to remove a lane with uncommitted changes. Commit or stash
inside the lane first.

## Subagents

Subagents run inside the current session's directory. The `/lane-worker` and
`/lane-review` commands use the current lane as their working directory. They
cannot talk to another top-level session. Coordination between sessions goes
through git, not through the agents.
