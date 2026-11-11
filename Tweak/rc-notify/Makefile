TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = rc-notify

rc-notify_FILES = rc-notify.m
rc-notify_CFLAGS = -fobjc-arc
rc-notify_FRAMEWORKS = Foundation UserNotifications
rc-notify_CODESIGN_FLAGS = -Sentitlements.plist
rc-notify_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
