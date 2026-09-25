DEBUG = 0
FINALPACKAGE = 1
PACKAGE_VERSION = 1.0.9

TARGET := iphone:clang:14.5:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SFSymbolReplacer

SFSymbolReplacer_FILES = Tweak.x SFHooks.m SFStore.c SFPlace.c
SFSymbolReplacer_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I.
SFSymbolReplacer_FRAMEWORKS = CoreGraphics CoreFoundation ImageIO
SFSymbolReplacer_LIBRARIES = substrate

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
SFSymbolReplacer_LDFLAGS += -lroothide
endif

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += sfsymbolreplacerprefs

include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/DEBIAN$(ECHO_END)
	$(ECHO_NOTHING)sed 's|@PREFIX@|$(THEOS_PACKAGE_INSTALL_PREFIX)|g' postinst.in > $(THEOS_STAGING_DIR)/DEBIAN/postinst$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 $(THEOS_STAGING_DIR)/DEBIAN/postinst$(ECHO_END)
