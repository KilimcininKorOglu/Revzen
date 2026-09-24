APP_NAME      := Revzen
BUILD_DIR     := build
APP_BUNDLE    := $(BUILD_DIR)/$(APP_NAME).app
CONFIGURATION ?= release
# A stable identity keeps the Accessibility and Screen Recording grants across
# rebuilds. Use SIGN_IDENTITY=- for an ad-hoc signature (CI).
SIGN_IDENTITY ?= Developer ID Application: ABDULLAH GOK (5U4P8ULV68)

BIN_DIR = $(shell swift build -c $(CONFIGURATION) --show-bin-path)

.PHONY: build test lint app sign run clean

build:
	swift build -c $(CONFIGURATION)

test:
	swift test

lint:
	swiftlint lint --strict --quiet

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
	cp $(BIN_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	$(MAKE) sign

sign:
	codesign --force --options runtime --timestamp=none --sign "$(SIGN_IDENTITY)" $(APP_BUNDLE)
	codesign --verify --strict $(APP_BUNDLE)

run: app
	-pkill -x $(APP_NAME)
	open $(APP_BUNDLE)

clean:
	rm -rf .build $(BUILD_DIR)
