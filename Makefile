# Aria — Makefile
# Targets: build, test, run, release, clean
#
# `build`/`test` use SwiftPM directly (fast, CLI-verifiable).
# `release` assembles a real Aria.app bundle with Info.plist so macOS
# treats it as an app (needed for LSUIElement + permission prompts).

APP_NAME    := Aria
BUILD_DIR   := .build
RELEASE_BIN := $(BUILD_DIR)/release/$(APP_NAME)
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
INFO_PLIST  := Resources/Info.plist

# Code-signing identity. Default is ad-hoc ("-"), which makes macOS re-prompt for
# permissions on every rebuild (the signature changes each time). To make
# Microphone/Screen-Recording permission STICK across rebuilds, create a stable
# self-signed identity once (see `make cert`) and it will be picked up here.
# Note: no -v here — a self-signed identity is untrusted (CSSMERR_TP_NOT_TRUSTED)
# but still signs fine and gives TCC a stable designated requirement. We match by
# name and pass the literal name to codesign (avoids parsing the listing).
SIGN_ID ?= $(shell security find-identity -p codesigning 2>/dev/null | grep -q "Aria Self-Signed" && echo "Aria Self-Signed")
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: build test run release dmg notarize clean xcode cert

DMG   := $(BUILD_DIR)/$(APP_NAME).dmg
STAGE := $(BUILD_DIR)/dmg-stage

build:
	swift build

test:
	swift test

# Run the raw executable (menu-bar app; no Dock icon due to LSUIElement).
run: build
	swift run $(APP_NAME)

# Assemble a proper .app bundle and codesign ad-hoc so permission
# dialogs (mic / screen recording) attribute to "Aria".
release:
	swift build -c release
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(RELEASE_BIN) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp $(INFO_PLIST) $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	codesign --force --deep --sign "$(SIGN_ID)" \
		--entitlements Resources/Aria.entitlements \
		$(APP_BUNDLE) || codesign --force --deep --sign "$(SIGN_ID)" $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (signed: $(SIGN_ID)) — open with: open $(APP_BUNDLE)"
	@if [ "$(SIGN_ID)" = "-" ]; then echo "NOTE: ad-hoc signed — macOS will re-ask for permissions after each rebuild. Run 'make cert' once to make them stick."; fi

# Package the signed app into a distributable .dmg (drag-to-Applications layout).
# Works with any identity, but only a notarized build (see `notarize`) opens without
# a Gatekeeper warning on someone else's Mac.
dmg: release
	rm -rf $(STAGE) $(DMG)
	mkdir -p $(STAGE)
	cp -R $(APP_BUNDLE) $(STAGE)/
	ln -s /Applications $(STAGE)/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(STAGE) -ov -format ULFO $(DMG)
	rm -rf $(STAGE)
	@echo "Built $(DMG) — this is the file you upload to Gumroad / Lemon Squeezy."

# Notarize the .dmg for public distribution. Requires a paid Apple Developer ID and a
# one-time stored credential profile:
#   xcrun notarytool store-credentials "aria-notary" \
#       --apple-id YOU@EXAMPLE.COM --team-id YOURTEAMID --password APP_SPECIFIC_PASSWORD
# Also set SIGN_ID to your "Developer ID Application: …" identity before building.
notarize: dmg
	xcrun notarytool submit $(DMG) --keychain-profile "aria-notary" --wait
	xcrun stapler staple $(DMG)
	@echo "Notarized + stapled $(DMG) — opens cleanly on any Mac."

# Create a stable self-signed code-signing certificate named "Aria Self-Signed"
# in the login keychain. With it, macOS keys permissions on the identity (stable)
# instead of the per-build hash, so Mic/Screen-Recording grants persist across
# rebuilds. One-time setup.
cert:
	@if security find-identity -v -p codesigning | grep -q "Aria Self-Signed"; then \
		echo "Identity 'Aria Self-Signed' already exists."; \
	else \
		echo "Creating self-signed code-signing certificate 'Aria Self-Signed'…"; \
		printf '[req]\ndistinguished_name=dn\n[dn]\n[v3]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > /tmp/aria_cert.cnf; \
		openssl req -x509 -newkey rsa:2048 -keyout /tmp/aria.key -out /tmp/aria.crt \
			-days 3650 -nodes -subj "/CN=Aria Self-Signed" -extensions v3 -config /tmp/aria_cert.cnf 2>/dev/null; \
		openssl pkcs12 -export -legacy -inkey /tmp/aria.key -in /tmp/aria.crt -out /tmp/aria.p12 -passout pass:aria 2>/dev/null; \
		security import /tmp/aria.p12 -k ~/Library/Keychains/login.keychain-db -P aria -A -T /usr/bin/codesign; \
		rm -f /tmp/aria.key /tmp/aria.crt /tmp/aria.p12 /tmp/aria_cert.cnf; \
		echo "Done. Now run 'make release' — permissions will persist across rebuilds."; \
		echo "(You may be asked once to 'Always Allow' codesign to use the key.)"; \
	fi

# Generate Aria.xcodeproj (requires `brew install xcodegen`).
xcode:
	xcodegen generate

clean:
	rm -rf $(BUILD_DIR)
