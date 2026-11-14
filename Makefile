# Moonkey — keyboard backlight control for T2 MacBooks.
#
#   make                 build build/moonkey and build/Moonkey.app
#   sudo make install    install system-wide and start it for all users
#   sudo make uninstall  remove everything

BUILD   := build
APP     := $(BUILD)/Moonkey.app
CFLAGS  := -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=12.0
APP_SRC := $(wildcard src/app/*.m)
APP_HDR := $(wildcard src/app/*.h) src/backlight.h

.PHONY: all clean install uninstall

all: $(BUILD)/moonkey $(APP)

$(BUILD)/moonkey: src/moonkey.c src/backlight.h
	@mkdir -p $(BUILD)
	clang $(CFLAGS) -framework IOKit -framework CoreFoundation src/moonkey.c -o $@
	codesign --force --sign - $@

$(APP): $(APP_SRC) $(APP_HDR) resources/Info.plist
	@mkdir -p $(APP)/Contents/MacOS
	clang $(CFLAGS) -fobjc-arc -Isrc -framework AppKit -framework IOKit $(APP_SRC) -o $(APP)/Contents/MacOS/Moonkey
	cp resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)

install: all
	scripts/install.sh

uninstall:
	scripts/uninstall.sh

clean:
	rm -rf $(BUILD)
