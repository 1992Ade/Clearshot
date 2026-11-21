TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = FloatBar

ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = FloatBar

FloatBar_FILES = $(wildcard FloatBar/*.m)
FloatBar_FRAMEWORKS = UIKit CoreGraphics QuartzCore Photos AVFoundation AVKit CoreMedia CoreVideo AudioToolbox
FloatBar_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
FloatBar_CODESIGN_FLAGS = -Sentitlements.plist
FloatBar_INSTALL_PATH = /Applications
FloatBar_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	@# Icons must live at the top of the .app for CFBundleIconFiles to find them.
	@if [ -d $(THEOS_STAGING_DIR)/Applications/FloatBar.app/Resources ]; then \
		mv $(THEOS_STAGING_DIR)/Applications/FloatBar.app/Resources/icon-*.png $(THEOS_STAGING_DIR)/Applications/FloatBar.app/ 2>/dev/null || true; \
		rm -f $(THEOS_STAGING_DIR)/Applications/FloatBar.app/Resources/icon.svg; \
		rmdir $(THEOS_STAGING_DIR)/Applications/FloatBar.app/Resources 2>/dev/null || true; \
	fi
	@mkdir -p $(THEOS_STAGING_DIR)/Payload
	@mv $(THEOS_STAGING_DIR)/Applications/FloatBar.app $(THEOS_STAGING_DIR)/Payload/
	@rm -rf $(THEOS_STAGING_DIR)/Applications
