# Sonifine — build, install and inspect the iOS app.
# Run `make help` for the targets.

PROJECT  := Sonifine.xcodeproj
SCHEME   := Sonifine
BUNDLE   := com.example.sonifine
DERIVED  := build
# The simulator for the tests.
SIMULATOR ?= iPhone 17 Pro
# the owner's iPhone 15 Pro. Override with `make device DEVICE=<udid>`; `xcrun devicectl list devices` lists them.
DEVICE   ?= 00000000-0000000000000000

.PHONY: help build test device-build device logs icon clean

help: ## Show the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-13s %s\n", $$1, $$2}'

build: ## Build for the iOS Simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) build -quiet

test: ## Run the unit tests in the simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath $(DERIVED) test -quiet

device-build: ## Build a signed app for a physical iPhone
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) -allowProvisioningUpdates build -quiet

device: device-build ## Build and install on the iPhone (unlocked, same Wi-Fi or cable)
	xcrun devicectl device install app --device $(DEVICE) $(DERIVED)/Build/Products/Debug-iphoneos/$(SCHEME).app

logs: ## Start the app on the iPhone and stream its volume-button and Now Playing log
	xcrun devicectl device process launch --device $(DEVICE) --terminate-existing --console \
		--environment-variables '{"OS_ACTIVITY_DT_MODE": "YES"}' $(BUNDLE) 2>&1 | grep --line-buffered -E "VolumeButtons|NowPlaying"

icon: ## Redraw the app icon
	uv run scripts/make_icon.py

clean: ## Remove build output
	rm -rf $(DERIVED)
