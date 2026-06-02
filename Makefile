# Friday — Makefile
# Targets: build, test, run, release, clean
#
# `build`/`test` use SwiftPM directly (fast, CLI-verifiable).
# `release` assembles a real Friday.app bundle with Info.plist so macOS
# treats it as an app (needed for LSUIElement + permission prompts).

APP_NAME    := Friday
BUILD_DIR   := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(APP_NAME)
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
INFO_PLIST  := Resources/Info.plist

.PHONY: build test run release clean xcode

build:
	swift build

test:
	swift test

# Run the raw executable (menu-bar app; no Dock icon due to LSUIElement).
run: build
	swift run $(APP_NAME)

# Assemble a proper .app bundle and codesign ad-hoc so permission
# dialogs (mic / screen recording) attribute to "Friday".
release:
	swift build -c release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(RELEASE_BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --deep --sign - \
		--entitlements Resources/Friday.entitlements \
		$(APP_BUNDLE) || codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) — open with: open $(APP_BUNDLE)"

# Generate Friday.xcodeproj (requires `brew install xcodegen`).
xcode:
	xcodegen generate

clean:
	rm -rf $(BUILD_DIR)
