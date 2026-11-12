# Control Center buttons for Control Center Button triggers (needs CCSupport, iOS 11 - 17).
# One bundle per slot, since each module Control Center loads is its own bundle on disk.
# Slot N runs the trigger "trigger_cc_button_N"; RCCCButton.m has the rest.
TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

RC_CC_SLOTS = 1 2 3 4

BUNDLE_NAME = $(foreach s,$(RC_CC_SLOTS),RCCCButton$(s))

define rc_cc_slot
RCCCButton$(1)_FILES = RCCCButton.m
RCCCButton$(1)_CFLAGS = -fobjc-arc -DRC_CC_SLOT=$(1) -DRC_CC_CLASS=RCCCButton$(1)
RCCCButton$(1)_FRAMEWORKS = UIKit
RCCCButton$(1)_PRIVATE_FRAMEWORKS = ControlCenterUIKit
RCCCButton$(1)_LDFLAGS += -F/opt/theos/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks
RCCCButton$(1)_INSTALL_PATH = /Library/ControlCenter/Bundles
endef
$(foreach s,$(RC_CC_SLOTS),$(eval $(call rc_cc_slot,$(s))))

include $(THEOS_MAKE_PATH)/bundle.mk

# Each bundle's Info.plist comes from the one template, with its slot filled in
internal-stage::
	@for s in $(RC_CC_SLOTS); do \
		dir="$(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles/RCCCButton$$s.bundle"; \
		mkdir -p "$$dir/en.lproj"; \
		sed "s/@SLOT@/$$s/g" Info.plist.in > "$$dir/Info.plist"; \
		cp Resources/*.png "$$dir/" 2>/dev/null || true; \
		printf 'CFBundleName = "RemoteCompanion Button %s";\nCFBundleDisplayName = "RemoteCompanion Button %s";\n' "$$s" "$$s" > "$$dir/en.lproj/InfoPlist.strings"; \
		printf '"RemoteCompanion Button %s" = "RemoteCompanion Button %s";\n"RCCCButton%s" = "RemoteCompanion Button %s";\n' "$$s" "$$s" "$$s" "$$s" > "$$dir/en.lproj/Localizable.strings"; \
	done

