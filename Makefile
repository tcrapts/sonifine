# Sonifine — build, install and inspect the iOS app.
# Run `make help` for the targets.

PROJECT  := Sonifine.xcodeproj
SCHEME   := Sonifine
DERIVED  := build
# The simulator for the tests.
SIMULATOR ?= iPhone 17 Pro

# Your own values come from .env (copy .env.example). Override one for a single
# run with `make device IPHONE_UDID=<udid>`.
# A value left empty keeps the one in the Xcode project.
-include .env
SETTINGS := $(if $(APPLE_TEAM_ID),DEVELOPMENT_TEAM=$(APPLE_TEAM_ID)) $(if $(BUNDLE_ID),APP_BUNDLE_IDENTIFIER=$(BUNDLE_ID)) \
	$(if $(SPOTIFY_CLIENT_ID),SPOTIFY_CLIENT_ID=$(SPOTIFY_CLIENT_ID))
BUNDLE_ID ?= com.example.sonifine

.PHONY: help build test device-build device logs icon clean

help: ## Show the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-13s %s\n", $$1, $$2}'

build: ## Build for the iOS Simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) $(SETTINGS) build -quiet

test: ## Run the unit tests in the simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath $(DERIVED) $(SETTINGS) test -quiet

device-build: ## Build a signed app for a physical iPhone
	@test -n "$(APPLE_TEAM_ID)" || { echo "Set APPLE_TEAM_ID in .env (see .env.example)."; exit 1; }
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) $(SETTINGS) -allowProvisioningUpdates build -quiet

device: device-build ## Build and install on the iPhone (unlocked, same Wi-Fi or cable)
	@test -n "$(IPHONE_UDID)" || { echo "Set IPHONE_UDID in .env (see .env.example)."; exit 1; }
	xcrun devicectl device install app --device $(IPHONE_UDID) $(DERIVED)/Build/Products/Debug-iphoneos/$(SCHEME).app

logs: ## Start the app on the iPhone and stream its volume-button and Now Playing log
	@test -n "$(IPHONE_UDID)" || { echo "Set IPHONE_UDID in .env (see .env.example)."; exit 1; }
	xcrun devicectl device process launch --device $(IPHONE_UDID) --terminate-existing --console \
		--environment-variables '{"OS_ACTIVITY_DT_MODE": "YES"}' $(BUNDLE_ID) 2>&1 | grep --line-buffered -E "VolumeButtons|NowPlaying|Spotify\]"

icon: ## Redraw the app icon
	uv run scripts/make_icon.py

clean: ## Remove build output
	rm -rf $(DERIVED)
