ARCHS = arm64
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = rc-party
rc-party_FILES = rc-party.m
rc-party_CFLAGS = -fobjc-arc
rc-party_LDFLAGS = -Wl,-sectcreate,__TEXT,__info_plist,Info.plist
rc-party_INSTALL_PATH = /usr/bin
rc-party_CODESIGN_FLAGS = -Sentitlements.plist
rc-party_FRAMEWORKS = Foundation AVFoundation

include $(THEOS_MAKE_PATH)/tool.mk
