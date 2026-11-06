"""Source-wiring checks, not a substitute for model execution or device tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ExclusionWiring(unittest.TestCase):
    def test_settings_available_without_web_ui(self):
        settings = source("RemoteCompanion/RCSettingsViewController.m")
        self.assertIn("webUIEnabled ? 4 : 2", settings)
        self.assertNotIn("RCExcludedAppsViewController", settings)
        advanced = source("RemoteCompanion/RCAdvancedSettingsViewController.m")
        self.assertIn('cell.textLabel.text = @"Excluded Apps"', advanced)
        self.assertIn("[[RCExcludedAppsViewController alloc] init]", advanced)
        self.assertNotIn("RCExcludedAppsViewController", source("RemoteCompanion/RCTriggersViewController.m"))

    def test_per_trigger_storage_preserves_other_fields(self):
        config = source("RemoteCompanion/RCConfigManager+AppExclusions.m")
        self.assertIn("[existing mutableCopy]", config)
        self.assertIn('trigger[@"excludedApps"] = ids', config)
        self.assertIn('[trigger removeObjectForKey:@"excludedApps"]', config)
        self.assertIn("[self updateTrigger:triggerKey withData:trigger]", config)
        self.assertNotIn("statusBarExcludedApps", config)
        self.assertNotIn("blacklist.plist", config)

    def test_picker_has_no_clear_all_and_mixed_case_ids(self):
        picker = source("RemoteCompanion/RCAppPickerViewController.m")
        self.assertEqual(picker.count("self.allowsEmptySelection || self.chosen.count > 0"), 2)
        self.assertNotIn("Clear All", picker)
        self.assertNotIn("clearAllApps", picker)
        self.assertIn("[chosenID caseInsensitiveCompare:bundleID]", picker)
        ui = source("RemoteCompanion/RCExcludedAppsViewController.m")
        self.assertIn("picker.allowsEmptySelection = YES", ui)
        self.assertIn("[cm nameForCommand:action truncate:YES]", ui)

    def test_excluded_rows_wrap_actions_only_when_enabled(self):
        ui = source("RemoteCompanion/RCExcludedAppsViewController.m")
        self.assertIn("cell.nameLabel.numberOfLines = wrapLongNames ? 0 : 1;", ui)
        self.assertIn("cell.actionsLabel.numberOfLines = wrapLongNames ? 0 : 1;", ui)
        self.assertIn("cell.excludedLabel.text", ui)
        self.assertNotIn("systemRedColor", ui)

    def test_dispatch_guard_before_action_execution(self):
        tweak = source("Tweak/Tweak.x")
        dispatch = tweak.split("void RCExecuteTrigger(NSString *triggerKey) {", 1)[1].split("// Execute on background queue", 1)[0]
        self.assertIn("RC_IsForegroundAppExcluded()", dispatch)
        self.assertIn("RC_IsTriggerExcludedForForegroundApp(triggerKey)", dispatch)
        self.assertLess(dispatch.index("RC_IsTriggerExcludedForForegroundApp(triggerKey)"), dispatch.index('SRLogMin(@"TRIGGER FIRED:'))
        actionable = tweak.split("static BOOL RC_TriggerIsActionable(NSString *key) {", 1)[1].split("\n}", 1)[0]
        self.assertIn("RC_IsTriggerExcludedForForegroundApp(key)", actionable)

    def test_statusbar_recognition_and_foreground_bound(self):
        tweak = source("Tweak/Tweak.x")
        self.assertIn('!RC_IsTriggerExcludedForForegroundApp(@"trigger_statusbar_double_tap")', tweak)
        self.assertIn("!RC_IsTriggerExcludedForForegroundApp(g_pendingStatusBarTrigger)", tweak)
        statusbar = tweak.split("// --- Status Bar Moves ---", 1)[1].split("// --- Bottom Bar Moves ---", 1)[0]
        self.assertIn("!RC_IsTriggerExcludedForForegroundApp(trigger)", statusbar)
        guard = tweak.split("static BOOL RC_IsTriggerExcludedForForegroundApp(NSString *key) {", 1)[1].split("static NSString *get_human_name_for_trigger", 1)[0]
        self.assertIn("25 * NSEC_PER_MSEC", guard)
        self.assertIn("respondsToSelector:@selector(_accessibilityFrontMostApplication)", guard)
        self.assertNotIn("cachedResult", guard)
        self.assertNotIn("dispatch_sync", guard)

    def test_app_sources_in_build(self):
        makefile = source("RemoteCompanion/Makefile")
        self.assertIn("RCConfigManager+AppExclusions.m RCExcludedAppsViewController.m", makefile)


if __name__ == "__main__":
    unittest.main()
