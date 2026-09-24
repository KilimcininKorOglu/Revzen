APP_NAME      := Revzen
BUILD_DIR     := build
DIST_DIR      := dist
APP_BUNDLE    := $(BUILD_DIR)/$(APP_NAME).app
DMG           := $(DIST_DIR)/$(APP_NAME).dmg
CONFIGURATION ?= release
# One universal binary for Apple silicon and Intel Macs.
ARCH_FLAGS    ?= --arch arm64 --arch x86_64
ENTITLEMENTS  := Resources/Revzen.entitlements
VERSION       := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
# A stable identity keeps the Accessibility and Screen Recording grants across
# rebuilds. Use SIGN_IDENTITY=- for an ad-hoc signature (CI).
SIGN_IDENTITY ?= Developer ID Application: ABDULLAH GOK (5U4P8ULV68)
# Notarization needs a secure timestamp. Local builds skip the network call.
TIMESTAMP     ?= --timestamp=none
NOTARY_PROFILE ?= revzen-notary
MINISIGN_KEY  ?= $(HOME)/.minisign/splitwg.key

BIN_DIR = $(shell swift build -c $(CONFIGURATION) $(ARCH_FLAGS) --show-bin-path)

.PHONY: build test lint icon app sign run dmg notarize-app notarize-dmg sign-minisign release clean

build:
	swift build -c $(CONFIGURATION) $(ARCH_FLAGS)

test:
	swift test

lint:
	swiftlint lint --strict --quiet

# Regenerates Resources/AppIcon.icns. The result is committed, so builds do
# not depend on this step.
icon:
	rm -rf $(BUILD_DIR)/AppIcon.iconset && mkdir -p $(BUILD_DIR)/AppIcon.iconset
	swift scripts/make-icon.swift $(BUILD_DIR)/icon-1024.png
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size $(BUILD_DIR)/icon-1024.png --out $(BUILD_DIR)/AppIcon.iconset/icon_$${size}x$${size}.png >/dev/null; \
		double=$$((size * 2)); \
		sips -z $$double $$double $(BUILD_DIR)/icon-1024.png --out $(BUILD_DIR)/AppIcon.iconset/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns $(BUILD_DIR)/AppIcon.iconset -o Resources/AppIcon.icns

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(BIN_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	$(MAKE) sign

sign:
	codesign --force --options runtime $(TIMESTAMP) --entitlements $(ENTITLEMENTS) \
		--sign "$(SIGN_IDENTITY)" $(APP_BUNDLE)
	codesign --verify --strict $(APP_BUNDLE)

run: app
	@# open sends a reopen event to a process that is still exiting, and the
	@# launch fails with procNotFound. Wait for the old instance to go first.
	-pkill -x $(APP_NAME)
	@while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.1; done
	open $(APP_BUNDLE)

dmg:
	rm -rf $(DIST_DIR) $(BUILD_DIR)/dmg-staging
	mkdir -p $(DIST_DIR) $(BUILD_DIR)/dmg-staging
	ditto $(APP_BUNDLE) $(BUILD_DIR)/dmg-staging/$(APP_NAME).app
	create-dmg --volname $(APP_NAME) --window-size 540 380 --icon-size 128 \
		--icon $(APP_NAME).app 130 170 --app-drop-link 400 170 \
		--hide-extension $(APP_NAME).app $(DMG) $(BUILD_DIR)/dmg-staging
	codesign --force $(TIMESTAMP) --sign "$(SIGN_IDENTITY)" $(DMG)

notarize-app:
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(BUILD_DIR)/$(APP_NAME).zip
	xcrun notarytool submit $(BUILD_DIR)/$(APP_NAME).zip --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(APP_BUNDLE)
	xcrun stapler validate $(APP_BUNDLE)

notarize-dmg:
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)
	xcrun stapler validate $(DMG)

# minisign does not read the passphrase from the environment, so CI pipes it.
sign-minisign:
	@if [ -n "$${MINISIGN_PASSWORD:-}" ]; then \
		printf '%s\n' "$$MINISIGN_PASSWORD" | minisign -S -s $(MINISIGN_KEY) -m $(DMG) -t "$(APP_NAME) $(VERSION)"; \
	else \
		minisign -S -s $(MINISIGN_KEY) -m $(DMG) -t "$(APP_NAME) $(VERSION)"; \
	fi

release:
	$(MAKE) app TIMESTAMP=--timestamp
	$(MAKE) notarize-app
	$(MAKE) dmg TIMESTAMP=--timestamp
	$(MAKE) notarize-dmg
	$(MAKE) sign-minisign

clean:
	rm -rf .build $(BUILD_DIR) $(DIST_DIR)
