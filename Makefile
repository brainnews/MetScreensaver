BUILD_DIR    = build
SAVER_NAME   = MetSaver.saver
SAVER_PATH   = $(BUILD_DIR)/Release/$(SAVER_NAME)
INSTALL_DIR  = $(HOME)/Library/Screen Savers
INSTALL_PATH = $(INSTALL_DIR)/$(SAVER_NAME)

ZIP_NAME     = MetSaver.zip
ZIP_PATH     = $(BUILD_DIR)/$(ZIP_NAME)

.PHONY: build install zip open clean

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

zip: build
	cd "$(BUILD_DIR)/Release" && zip -r "../$(ZIP_NAME)" "$(SAVER_NAME)"
	@echo "Created $(ZIP_PATH)"

open:
	open "x-apple.systempreferences:com.apple.preference.desktopscreensaver"

clean:
	rm -rf $(BUILD_DIR)
