# Per-behavior app exclusions (4.1 source work)

## User flow

Settings → General → **Excluded Apps** → an assigned status bar behavior → app multi-picker.
Each behavior shows its trigger name, assigned action labels and excluded-app count.
Disabled behaviors with assigned actions remain editable. A behavior without assigned
actions is not listed. Done saves the selection; Back leaves it unchanged. Untick every
app or use Clear All, then Done, to remove that behavior's exclusions. Clear All also
removes saved IDs for apps that are no longer installed.

This is not an entry in the Triggers screen and not a new global blacklist.

## Storage and runtime contract

The optional `excludedApps` array lives inside the individual trigger dictionary:

```json
{
  "triggers": {
    "trigger_statusbar_swipe_left": {
      "enabled": true,
      "actions": ["home"],
      "excludedApps": ["com.example.game"]
    }
  }
}
```

- Supported: status bar left/center/right hold, swipe left/right and double tap.
- All actions belonging to that trigger are skipped in its selected foreground apps.
  Other behaviors still work there. The same behavior still works in other apps.
- Comparisons are exact and case-insensitive, not prefixes or wildcards. Invalid types,
  empty IDs and duplicate IDs are discarded. Missing/empty arrays mean unrestricted.
- Storage uses the existing config save/notification/export/import paths. Editing the
  list preserves the trigger's actions, enabled state, mode and other fields. A stale
  picker does not recreate a deleted trigger.
- SpringBoard reads its foreground application's bundle ID at recognition/dispatch.
  The existing foreground selector is guarded; no app-identity cache is added. Missing
  identity or an off-main lookup that takes more than 25 ms fails open.
- Guards cover dispatch, status bar haptics and actionable/freeze checks. A denied
  gesture does not freeze scrolling on behalf of that trigger. Existing touch tracking
  and pass-through event delivery are retained.
- The existing `rc blacklist` file and all-trigger safety policy are unchanged. An app
  on that legacy blacklist still suppresses triggers according to the old policy.
- No migration from the old experimental global `statusBarExcludedApps` key is done.
- Other trigger families deliberately ignore `excludedApps` in this first version.
  Central dispatch could be extended, but button/native-default suppression and each
  family's haptic/gesture paths must be audited before exposing a broader picker.
- Exclusions are evaluated when a trigger fires; they do not cancel an action sequence
  already running when the foreground app changes.

## Validation

Run source-wiring regression checks on any host:

```sh
python tools/testkit/check_app_exclusions.py
```

Run the actual Foundation model assertions on macOS (no jailbreak/device required):

```sh
clang -fobjc-arc -framework Foundation tools/testkit/app_exclusions_model.m -o /tmp/rc-exclusions
/tmp/rc-exclusions
```

Validation completed on the 4.1-based test build: six Python source-wiring tests,
the Foundation exclusion model and Quick Shortcut native-API-double tests on macOS,
and a complete rootless package build. The packaged tweak dylibs contain arm64 and
arm64e slices. The owner reported that the test build works; a detailed cross-version
device test matrix, particularly iOS 15, has not been recorded.

Quick Shortcut model test:

```sh
clang -fobjc-arc -framework Foundation tools/testkit/quickactions_model.m -o /tmp/rc-quickactions
/tmp/rc-quickactions
```

Required device matrix before claiming the feature works:

1. Assign two different status bar behaviors and leave one unassigned; only assigned
   ones appear, with readable action labels (including App Quick Action).
2. Exclude a game for only one behavior: that behavior must not fire/haptic/freeze
   there; the other behavior must still work. Native scrolling/touch delivery remains.
3. Switch immediately to an unrestricted app and Home Screen: no stale exclusion.
4. Exercise all six behaviors independently, both master toggle states, disabled
   assigned triggers, empty picker/clear, and a previously uninstalled selected app.
5. Save, quit/reopen the app, respring, and export/import; confirm per-trigger IDs and
   behavior persist. Back without Done must not change the prior selection.
6. Confirm command-line blacklist behavior and unrelated bottom/edge/button triggers
   are unchanged. Confirm Web UI Access/Open Web UI still navigate correctly.
