ARCHS = arm64
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = rc-dictate
rc-dictate_FILES = rc-dictate.m
rc-dictate_CFLAGS = -fobjc-arc
rc-dictate_LDFLAGS = -Wl,-sectcreate,__TEXT,__info_plist,Info.plist
rc-dictate_INSTALL_PATH = /usr/bin
rc-dictate_CODESIGN_FLAGS = -Sentitlements.plist
rc-dictate_FRAMEWORKS = Foundation AVFoundation Speech

include $(THEOS_MAKE_PATH)/tool.mk
