FINALPACKAGE=1
THEOS_PACKAGE_COMPRESSION = gzip
THEOS ?= /opt/theos
THEOS_DEVICE_IP = iphone.local
INSTALL_TARGET_USER = mobile
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

# Support for both rootless and roothide
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ARCHS = arm64 arm64e
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
ARCHS = arm64 arm64e
else
ARCHS = arm64 arm64e
endif

THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RemoteCommand RCShortcutsHelper RCNFCReader RCWatchPing

# Lua source files
LUA_FILES = $(wildcard lua/*.c)

RemoteCommand_FILES = Tweak.x RCNFCManager.x $(LUA_FILES)
RemoteCommand_FILES += RCTestKit.x
# Shared with the app: the one toast pill (editor preview uses the same file)
RemoteCommand_FILES += ../RemoteCompanion/RCToastPill.m
RemoteCommand_CFLAGS = -fobjc-arc -Ilua -I../RemoteCompanion -DLUA_USE_IOS -Wno-unused-function -Wno-unused-variable
RemoteCommand_FRAMEWORKS = UIKit CoreNFC IOKit QuartzCore CoreLocation
RemoteCommand_PRIVATE_FRAMEWORKS = AppSupport MediaRemote MobileCoreServices FrontBoardServices BackBoardServices MediaPlayer DoNotDisturb BiometricKit AccessibilityUtilities
RemoteCommand_LDFLAGS += -F/opt/theos/sdks/iPhoneOS16.5.sdk/System/Library/PrivateFrameworks

# Loaded into siriactionsd, where it runs shortcuts (see RCShortcutsHelper.m)
RCShortcutsHelper_FILES = RCShortcutsHelper.m
RCShortcutsHelper_CFLAGS = -fno-objc-arc

# Loaded into nfcd, where it passes tags iOS's own reader detects to SpringBoard (Experimental NFC,
# see RCNFCReader.m)
RCNFCReader_FILES = RCNFCReader.m
RCNFCReader_CFLAGS = -fobjc-arc

# Loaded into companionfindlocallyd, where it passes Ping iPhone from an Apple Watch to SpringBoard
# (Watch Ping triggers, see RCWatchPing.m)
RCWatchPing_FILES = RCWatchPing.m
RCWatchPing_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += rc-root
SUBPROJECTS += rc-client
include $(THEOS_MAKE_PATH)/aggregate.mk
