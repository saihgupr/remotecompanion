ARCHS = arm64
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

# rc-ocr IMAGE [fast]: reads the text in an image with Vision. SpringBoard uses it where its own
# careful read fails (iOS 15), since a separate process may use the Neural Engine
TOOL_NAME = rc-ocr
rc-ocr_FILES = rc-ocr.m
rc-ocr_CFLAGS = -fobjc-arc
rc-ocr_INSTALL_PATH = /usr/bin
rc-ocr_CODESIGN_FLAGS = -Sentitlements.plist
rc-ocr_FRAMEWORKS = Foundation Vision CoreGraphics ImageIO CoreVideo

include $(THEOS_MAKE_PATH)/tool.mk
