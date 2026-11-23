# RemoteCompanion 4.7.0 release, Sunday 22 Nov 2026, 9:00am ET

Repo: /Users/chrislapointe/Projects/CurrentProjects/RemoteCompanion
Public latest right now: v4.4.0 (GitHub release and Sileo repo). 4.5.0 notes were written but never shipped, so 4.7.0 carries both changelog sections.

## Already done tonight
- [x] 4.7.0 changelog entry, plus three new Fixed bullets for the security and backup work
- [x] Info.plist and Tweak/control at 4.7.0
- [x] PR #201 content applied to the working tree (cherry-picked, uncommitted, no conflicts). This is the API token and backup fix, +46/-24 in Tweak/Tweak.x, tested on alpha-4.7
- [x] Rootless and rootful builds pass with that fix, both debs contain the fix and both carry arm64 and arm64e slices
- [x] Python tests pass: 14 in test_dev_annotate, 12 in test_rc_mcp, addon-builtins and dev-presets checks
- [x] Installed on the iPhone under the device lock and verified: dpkg says 4.7.0, the Web UI answers, state reads back
- [x] README What's New box replaced with the 4.7.0 block
- [x] docs/index.html and docs/depiction.json say 4.7.0
- [x] Reddit post draft, GitHub release notes, README block all in docs/release-4.7.0/

## Branch audit (what the user asked about)
- Touch ID quiet-during-auth fix: already in alpha-4.7 as 6c6c626, in the 4.7.0 Fixed list. Nothing to do.
- Home Assistant "Trigger ..." naming: alpha-4.7 already has it in both the app and the Web UI. The copy on test/latest is the same work.
- main has zero commits that alpha-4.7 lacks.
- Only real gap was PR #201, now applied.
- Left out on purpose: the closed PRs #138 (Triggers Enabled category) and #200 (Settings pages). Not release material for tomorrow.
- feature/if-indent-rails was merged into alpha-4.7 by another session at 10:06 after this audit (copy, cut, paste, indented nested cards, undo and redo, SSH connection test). The changelog covers all of it, and the Reddit and GitHub copy were updated to match.

## Before 9am (start at ~8:00)
1. PR #201 is closed as shipped. Its content is in commit 8e459e5 on alpha-4.7. Nothing left to do here.
2. `git checkout main && git merge alpha-4.7`. Expect 303 commits. Watch CHANGELOG.md and README.md for conflicts.
3. Build both packages as two separate commands. `--rootless --rootful` in one line only builds the last flag, which bit us once:
   `./build.sh --rootless`
   `./build.sh --rootful`
4. Confirm `Tweak/packages/` has fresh `*_4.7.0_iphoneos-arm.deb` and `*_4.7.0_iphoneos-arm64.deb`, both stamped today.
5. Copy both debs into the repo:
   `cp Tweak/packages/com.saihgupr.remotecompanion_4.7.0_iphoneos-arm.deb docs/`
   `cp Tweak/packages/com.saihgupr.remotecompanion_4.7.0_iphoneos-arm64.deb docs/`
6. `./repo_utils/update_repo.sh`
   Verify `grep "^Version: 4.7.0" docs/Packages | wc -l` returns 2.
7. Commit: `Build the 4.7 release packages`
8. Push main.
9. `git tag v4.7.0 && git push origin v4.7.0`
10. `gh release create v4.7.0 --title "v4.7.0" --notes-file docs/release-4.7.0/github-release-notes.md`
11. Attach both debs to the release, like v4.4.0 has them:
    `gh release upload v4.7.0 docs/com.saihgupr.remotecompanion_4.7.0_iphoneos-arm.deb docs/com.saihgupr.remotecompanion_4.7.0_iphoneos-arm64.deb`
12. Verify before posting:
    - `gh release view v4.7.0` shows both assets
    - https://saihgupr.github.io/remotecompanion/ says v4.7.0 Latest
    - `curl -s https://saihgupr.github.io/remotecompanion/Packages | grep -c "Version: 4.7.0"` returns 2
    - open the depiction in Sileo on the phone and confirm the update shows

## 9:00am
13. Post to r/jailbreak with title option 1 and flair `Update`. House format is `[Update] RemoteCompanion v4.7.0 - ...`.
14. Gallery post if there are images, text post is fine if not. Last three releases used both.
15. Reply to comments early. Top questions last time were iOS 18 support and an iOS 15.8 SE (2016) regression, both already addressed in the draft's compatibility and known limitations sections.
16. Pin the post if the sub allows it.

## Known gap
- No fresh screenshots for 4.7.0. The two most postable visuals are Developer Mode annotate-and-send and the Apple Watch rows. Capturing means using `screen capture` on the deployed 4.7.0 build. Do it after step 6 if there is time, never during the 9am window.
