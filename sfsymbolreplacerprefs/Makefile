include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SFSymbolReplacerPrefs

SFSymbolReplacerPrefs_FILES = SFSymbolRootListController.m SFSymbolBrowserController.m SFSymbolDetailController.m SFImageImporter.m SFStyle.m SFLocalize.m ../SFSymbolStore.m ../SFPlace.c
SFSymbolReplacerPrefs_FRAMEWORKS = UIKit Foundation CoreGraphics CoreFoundation ImageIO QuartzCore PhotosUI UniformTypeIdentifiers
SFSymbolReplacerPrefs_PRIVATE_FRAMEWORKS = Preferences
SFSymbolReplacerPrefs_INSTALL_PATH = /Library/PreferenceBundles
SFSymbolReplacerPrefs_CFLAGS = -DSFSymbolStore=SFSymbolStorePrefs -fobjc-arc -Wno-deprecated-declarations -I..
SFSymbolReplacerPrefs_RESOURCE_DIRS = Resources

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
SFSymbolReplacerPrefs_LDFLAGS += -lroothide
endif

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/SFSymbolReplacer.plist$(ECHO_END)
