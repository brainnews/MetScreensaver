BUILD_DIR    = build
SAVER_NAME   = MetSaver.saver
SAVER_PATH   = $(BUILD_DIR)/Release/$(SAVER_NAME)
INSTALL_DIR  = $(HOME)/Library/Screen Savers
INSTALL_PATH = $(INSTALL_DIR)/$(SAVER_NAME)

DMG_NAME     = MetSaver.dmg
DMG_PATH     = $(BUILD_DIR)/$(DMG_NAME)

.PHONY: build install dmg open clean

build:
	xcodebuild \
		-project MetSaver.xcodeproj \
		-target MetSaver \
		-configuration Release \
		SYMROOT=$(PWD)/$(BUILD_DIR) \
		build

install: build
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_PATH)"
	cp -r "$(SAVER_PATH)" "$(INSTALL_PATH)"
	-killall ScreenSaverEngine 2>/dev/null
	-killall legacyScreenSaver 2>/dev/null
	@echo "Installed to $(INSTALL_PATH)"

dmg: build
	hdiutil create -volname "MetSaver" \
		-srcfolder "$(SAVER_PATH)" \
		-ov -format UDZO \
		"$(DMG_PATH)"
	@echo "Created $(DMG_PATH)"

open:
	open "x-apple.systempreferences:com.apple.preference.desktopscreensaver"

clean:
	rm -rf $(BUILD_DIR)
