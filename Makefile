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

# Code-signing identity. Default is ad-hoc ("-"), which makes macOS re-prompt for
# permissions on every rebuild (the signature changes each time). To make
# Microphone/Screen-Recording permission STICK across rebuilds, create a stable
# self-signed identity once (see `make cert`) and it will be picked up here.
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Friday Self-Signed" | sed -E 's/.*"(.*)"/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: build test run release clean xcode cert

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
	codesign --force --deep --sign "$(SIGN_ID)" \
		--entitlements Resources/Friday.entitlements \
		$(APP_BUNDLE) || codesign --force --deep --sign "$(SIGN_ID)" $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE) (signed: $(SIGN_ID)) — open with: open $(APP_BUNDLE)"
	@if [ "$(SIGN_ID)" = "-" ]; then echo "NOTE: ad-hoc signed — macOS will re-ask for permissions after each rebuild. Run 'make cert' once to make them stick."; fi

# Create a stable self-signed code-signing certificate named "Friday Self-Signed"
# in the login keychain. With it, macOS keys permissions on the identity (stable)
# instead of the per-build hash, so Mic/Screen-Recording grants persist across
# rebuilds. One-time setup.
cert:
	@if security find-identity -v -p codesigning | grep -q "Friday Self-Signed"; then \
		echo "Identity 'Friday Self-Signed' already exists."; \
	else \
		echo "Creating self-signed code-signing certificate 'Friday Self-Signed'…"; \
		printf '[req]\ndistinguished_name=dn\n[dn]\n[v3]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' > /tmp/friday_cert.cnf; \
		openssl req -x509 -newkey rsa:2048 -keyout /tmp/friday.key -out /tmp/friday.crt \
			-days 3650 -nodes -subj "/CN=Friday Self-Signed" -extensions v3 -config /tmp/friday_cert.cnf 2>/dev/null; \
		openssl pkcs12 -export -inkey /tmp/friday.key -in /tmp/friday.crt -out /tmp/friday.p12 -passout pass: 2>/dev/null; \
		security import /tmp/friday.p12 -k ~/Library/Keychains/login.keychain-db -P "" -T /usr/bin/codesign; \
		rm -f /tmp/friday.key /tmp/friday.crt /tmp/friday.p12 /tmp/friday_cert.cnf; \
		echo "Done. Now run 'make release' — permissions will persist across rebuilds."; \
		echo "(You may be asked once to 'Always Allow' codesign to use the key.)"; \
	fi

# Generate Friday.xcodeproj (requires `brew install xcodegen`).
xcode:
	xcodegen generate

clean:
	rm -rf $(BUILD_DIR)
