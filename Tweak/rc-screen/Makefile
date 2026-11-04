TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = rc-screen

rc-screen_FILES = rc-screen.m
rc-screen_CFLAGS = -fobjc-arc
rc-screen_FRAMEWORKS = Foundation CoreGraphics
rc-screen_CODESIGN_FLAGS = -Sentitlements.plist
rc-screen_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
