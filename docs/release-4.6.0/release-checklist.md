# RemoteCompanion 4.6.0 release, Sunday 29 Nov 2026

Repo: `/Users/chrislapointe/Projects/CurrentProjects/RemoteCompanion-4.6` (worktree, branch `alpha-4.6`)
Main checkout: `/Users/chrislapointe/Projects/CurrentProjects/RemoteCompanion` (branch `alpha-4.7`)
Public latest right now: v4.5.0 (GitHub release, Sileo repo, Havoc), published 22 Nov 2026.

## Done in this prep (Tue 24 Nov)

- [x] Changelog: `[Unreleased]` renamed to `[4.6.0] - 2026-11-29`
- [x] README What's New block replaced with the 4.6.0 block
- [x] `docs/index.html`: badge and Latest Version say 4.6.0, What's New section rewritten for 4.6, 4.5 and 4.4 moved into Version History
- [x] `docs/depiction.json`: new Version 4.6.0 changelog block above 4.5.0
- [x] `docs/release-4.6.0/`: GitHub notes, README block, Reddit post, this checklist
- [x] Rootless and rootful debs built from this branch

## Before Sunday

1. Rebuild if anything changes after this prep. Two separate commands, because `--rootless --rootful` in one line only builds the last flag:
   `./build.sh --rootless`
   `./build.sh --rootful`
2. Confirm `Tweak/packages/` has fresh `*_4.6.0_iphoneos-arm.deb` and `*_4.6.0_iphoneos-arm64.deb`, both stamped that day.
3. Install on the iPhone under the device lock and check that dpkg says 4.6.0, the Web UI answers, and state reads back.
4. Copy both debs into the repo:
   `cp Tweak/packages/com.saihgupr.remotecompanion_4.6.0_iphoneos-arm.deb docs/`
   `cp Tweak/packages/com.saihgupr.remotecompanion_4.6.0_iphoneos-arm64.deb docs/`
5. `./repo_utils/update_repo.sh`
   Verify `grep "^Version: 4.6.0" docs/Packages | wc -l` returns 2.
6. Commit the release prep on `alpha-4.6`, then merge into main:
   `git checkout main && git merge alpha-4.6`
   Expect conflicts in `CHANGELOG.md`, `README.md`, `docs/index.html`, `docs/depiction.json`, `docs/Packages`, `docs/Release`. For the docs, take the `alpha-4.6` side and regenerate the repo index after copying the debs. Do not drop main's 4.5.0 release commits.
7. Commit the merge as `Build the 4.6 release packages`, push main.
8. `git tag v4.6.0 && git push origin v4.6.0`
9. `gh release create v4.6.0 --title "v4.6.0" --notes-file docs/release-4.6.0/github-release-notes.md`
10. `gh release upload v4.6.0 docs/com.saihgupr.remotecompanion_4.6.0_iphoneos-arm.deb docs/com.saihgupr.remotecompanion_4.6.0_iphoneos-arm64.deb`
11. Verify before posting:
    - `gh release view v4.6.0` shows both assets
    - https://saihgupr.github.io/remotecompanion/ says v4.6.0 Latest
    - `curl -s https://saihgupr.github.io/remotecompanion/Packages | grep -c "Version: 4.6.0"` returns 2
    - the depiction in Sileo shows the update and the 4.6.0 changelog

## After 4.6 is public

4.7's changelog currently still lists the 4.6 features, because the 4.6 Unreleased section was folded into the 4.7.0 section. Trim 4.7.0 to its own items (Tweaks, swipe zones, Swipe Triggers settings, Developer Mode, Watch actions and triggers, Control Center and Notification Center conditions, Open Notification Center, AssistiveTouch, Dance Party, flashlight levels, plus its own changed and fixed lists) before 4.7 is prepped.

## 9:00am Sunday

- Post to r/jailbreak with title option 1 and flair `Update`. House format is `[Update] RemoteCompanion v4.6.0 - ...`.
- Text post is fine if there are no screenshots; the Reddit draft lists five shots to capture if there is time.
- Reply to comments early, and pin the post if the sub allows it.

## Known gaps

- No 4.6 screenshots. Reuse `docs/images/4.7.0/reddit-04-timer-editor.png` and `reddit-05-screen-text.png` from the 4.7 branch if needed, since both features ship in 4.6.
- The 4.7 branch has uncommitted changelog edits in the main checkout. Leave them until 4.6 is out, then redo the 4.7 section without the 4.6 items.
