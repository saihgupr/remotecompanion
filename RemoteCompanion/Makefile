FINALPACKAGE=1
THEOS ?= /opt/theos
ARCHS = arm64
TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = RemoteCompanion

RemoteCompanion_FILES = main.m RCAppDelegate.m RCConfigManager.m RCTriggersViewController.m RCActionsViewController.m RCActionPickerViewController.m RCSettingsViewController.m RCBannersViewController.m RCIntegrationsViewController.m RCHASettingsViewController.m RCKMSettingsViewController.m RCMQTTSettingsViewController.m RCMQTTClient.m RCMQTTTriggerViewController.m RCNFCTriggerViewController.m RCShortcutPickerViewController.m RCTextInputViewController.m RCAppPickerViewController.m RCServerClient.m RCWiFiTriggerViewController.m RCBluetoothTriggerViewController.m RCUITweaker.m RCNotificationTriggerViewController.m RCScheduledTriggerViewController.m RCHAEntityPickerViewController.m RCKMMacroPickerViewController.m
RemoteCompanion_FRAMEWORKS = UIKit Foundation UserNotifications CoreNFC MobileCoreServices LocalAuthentication
RemoteCompanion_CFLAGS = -fobjc-arc
RemoteCompanion_FILES += RCNewTriggerViewController.m
RemoteCompanion_LDFLAGS = -lc++
RemoteCompanion_CODESIGN_FLAGS = -SEntitlements.plist
RemoteCompanion_FILES += RCConditionPickerViewController.m
RemoteCompanion_RESOURCE_FILES = Info.plist Icon.png AppIcon60x60@2x.png AppIcon60x60@3x.png Entitlements.plist
RemoteCompanion_INSTALL_PATH = /Applications
RemoteCompanion_FILES += RCDevicePickerViewController.m

# Shared UI components
RemoteCompanion_FILES += RCCategoryBar.m

include $(THEOS_MAKE_PATH)/application.mk
