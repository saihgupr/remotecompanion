# Control Center button module provider (needs CCSupport, iOS 14 - 17).
# Exposes one Control Center module per trigger_cc_button_* entry in rc_triggers.plist,
# using each button's RemoteCompanion name in Settings > Control Center.
TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RCCCButtonProvider
RCCCButtonProvider_BUNDLE_EXTENSION = bundle
RCCCButtonProvider_FILES = RCCCButton.m
RCCCButtonProvider_CFLAGS = -fobjc-arc
RCCCButtonProvider_FRAMEWORKS = UIKit
RCCCButtonProvider_PRIVATE_FRAMEWORKS = ControlCenterUIKit
RCCCButtonProvider_LDFLAGS += -F/opt/theos/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks
RCCCButtonProvider_INSTALL_PATH = /Library/ControlCenter/CCSupport_Providers

include $(THEOS_MAKE_PATH)/bundle.mk
