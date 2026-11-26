TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = ClearShot

ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = ClearShot
BUNDLE_NAME      = ClearShotModule

# ============================================================================
# 1) The wrapper app — ClearShot.app (displayed as TrollBox). Root-UID via
# TrollStore's platform-application so it can copy the Control Center bundle
# into /Library/ControlCenter/Bundles/, install LaunchDaemons, write mobile-
# configs, etc. Private frameworks (StoreKitUI for AppRepack, Preferences for
# shared cells on AppRepack's Settings-style UI) are linked here.
# ============================================================================
ClearShot_FILES = $(wildcard ClearShot/*.m)
ClearShot_FRAMEWORKS = UIKit CoreGraphics QuartzCore Photos CoreLocation IOKit SystemConfiguration CoreServices
ClearShot_PRIVATE_FRAMEWORKS = StoreKitUI Preferences
ClearShot_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
ClearShot_CODESIGN_FLAGS = -Sentitlements.plist
ClearShot_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk

# ============================================================================
# 2) The Control Center module bundle — ClearShotModule.bundle. Runs inside
# SpringBoard, which already has every entitlement we need for CARenderServer.
# No custom entitlements on the bundle itself.
# ============================================================================
ClearShotModule_FILES = $(wildcard ClearShotModule/*.m)
ClearShotModule_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics ImageIO Photos
ClearShotModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
ClearShotModule_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unguarded-availability-new
ClearShotModule_INSTALL_PATH = /Library/ControlCenter/Bundles

include $(THEOS_MAKE_PATH)/bundle.mk

# ============================================================================
# Packaging. Theos stages:
#   $(THEOS_STAGING_DIR)/Applications/ClearShot.app
#   $(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles/ClearShotModule.bundle
#
# We want the final .tipa to carry ONLY Payload/ClearShot.app, with the
# CC bundle and Ad Blocking assets embedded inside the .app — so first-launch
# install code can copy them where they need to go.
# ============================================================================
APP_BUNDLE = $(THEOS_STAGING_DIR)/Applications/ClearShot.app
CC_BUNDLE  = $(THEOS_STAGING_DIR)/Library/ControlCenter/Bundles/ClearShotModule.bundle

after-stage::
	@echo "========== after-stage =========="
	@echo "Staged tree:"
	@find $(THEOS_STAGING_DIR) -maxdepth 4 -type d
	@# --- 1) Make sure the CC bundle carries its Info.plist.
	@if [ -f ClearShotModule/Info.plist ]; then \
	  cp -f ClearShotModule/Info.plist $(CC_BUNDLE)/Info.plist; \
	  echo "Copied ClearShotModule/Info.plist into the bundle."; \
	fi
	@# --- 2) Embed the CC bundle inside the .app so the app can install it
	@# at runtime (needs TrollStore root perms to write /Library/...).
	@if [ -d "$(CC_BUNDLE)" ]; then \
	  cp -R "$(CC_BUNDLE)" "$(APP_BUNDLE)/"; \
	  echo "Embedded ClearShotModule.bundle inside ClearShot.app."; \
	else \
	  echo "ERROR: CC bundle not built at $(CC_BUNDLE)"; \
	  find $(THEOS_STAGING_DIR) -name 'ClearShotModule*'; \
	  exit 1; \
	fi
	@# --- 3) App-level Info.plist and icons at the root of the .app bundle.
	@cp -f Info.plist $(APP_BUNDLE)/Info.plist
	@find Resources -maxdepth 1 -name 'icon-*.png' -exec cp -f {} $(APP_BUNDLE)/ \; 2>/dev/null || true
	@# --- 4) Embed the Ad Blocking assets (4 PACs + 2 mobileconfig templates).
	@# These are read at runtime by ABMainViewController to build the user's
	@# chosen mobileconfig on-device.
	@mkdir -p $(APP_BUNDLE)/AdBlock/PAC
	@mkdir -p $(APP_BUNDLE)/AdBlock/Templates
	@cp -f MYbloXX/PAC/*.pac           $(APP_BUNDLE)/AdBlock/PAC/   2>/dev/null || echo "WARN: MYbloXX/PAC/ missing"
	@cp -f MYbloXX/Templates/*.plist   $(APP_BUNDLE)/AdBlock/Templates/ 2>/dev/null || echo "WARN: MYbloXX/Templates/ missing"
	@echo "== Final .app bundle contents =="
	@ls -la $(APP_BUNDLE)
	@echo "== CC bundle inside .app =="
	@ls -la $(APP_BUNDLE)/ClearShotModule.bundle
	@echo "== AdBlock assets =="
	@ls -la $(APP_BUNDLE)/AdBlock/PAC/ $(APP_BUNDLE)/AdBlock/Templates/ 2>/dev/null
	@# --- 5) Convert to Payload/ layout for the .tipa.
	@mkdir -p $(THEOS_STAGING_DIR)/Payload
	@mv $(APP_BUNDLE) $(THEOS_STAGING_DIR)/Payload/
	@rm -rf $(THEOS_STAGING_DIR)/Applications
	@rm -rf $(THEOS_STAGING_DIR)/Library
	@echo "========== end after-stage =========="
