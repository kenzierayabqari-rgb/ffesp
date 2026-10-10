ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = FFESP
FFESP_FILES = Tweak.xm Menu.mm ESP.mm AntiBypass.mm il2cpp.mm KittyMemory.cpp
FFESP_CFLAGS  = -fobjc-arc -I. -Wno-everything
FFESP_CCFLAGS = -std=c++17 -I. -Wno-everything
FFESP_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore
FFESP_LDFLAGS = -undefined dynamic_lookup -Wl,-not_for_dyld_shared_cache

include $(THEOS_MAKE_PATH)/library.mk
