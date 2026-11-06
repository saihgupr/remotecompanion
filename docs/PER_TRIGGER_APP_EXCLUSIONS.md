# Per-trigger app exclusions (4.1 source work)

## User flow

Settings → Advanced Settings → Options → **Excluded Apps** → an assigned trigger → app multi-picker.
Each trigger shows its name, assigned action labels and excluded-app count.
Disabled triggers with assigned actions remain editable. A trigger without assigned
actions is not listed. Done saves the selection; Back leaves it unchanged. Untick every
app or use Clear All, then Done, to remove that trigger's exclusions. Clear All also
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

- Supported: any trigger with a non-empty actions array. Triggers with no actions are not
  listed; disabled-but-assigned triggers remain editable.
- All actions belonging to that trigger are skipped in its selected foreground apps.
  Other triggers still work there. The same trigger still works in other apps.
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
- `excludedApps` applies to every assigned trigger. Enforcement is generic in the central
  dispatch and actionable/freeze checks, so button, gesture, device-state, app, scheduled,
  NFC, Wi-Fi, Bluetooth and MQTT triggers all honor their own list. Status bar haptic
  guards check the list as well.
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

1. Assign two different triggers and leave one unassigned; only assigned ones appear,
   with readable action labels (including App Quick Action).
2. Exclude a game for only one trigger: that trigger must not fire/haptic/freeze there;
   the other trigger must still work. Native scrolling/touch delivery remains.
3. Switch immediately to an unrestricted app and Home Screen: no stale exclusion.
4. Exercise several triggers across families independently, both master toggle states,
   disabled assigned triggers, empty picker/clear, and a previously uninstalled selected app.
5. Save, quit/reopen the app, respring, and export/import; confirm per-trigger IDs and
   behavior persist. Back without Done must not change the prior selection.
6. Confirm command-line blacklist behavior is unchanged and Web UI Access/Open Web UI
   still navigate correctly.
