# Your own values for building Sonifine. Copy this file to local.mk and fill it
# in; git ignores local.mk. The Makefile passes these to xcodebuild; a value
# left empty keeps the one in the Xcode project.

# Your Apple developer team: Xcode → Settings → Accounts → your account → Team ID.
# The simulator builds without it; an iPhone install needs it.
TEAM :=

# The bundle ID of your app, unique to you, such as com.yourname.sonifine. The
# tests get the same ID with `.tests` after it. Keep it once installed: the
# app's sign-ins live under it. Empty means com.example.sonifine, which the
# simulator accepts and Apple's signing refuses.
BUNDLE_ID :=

# The client ID of your app on developer.spotify.com, for the library sign-in.
# The README explains how to create that app.
SPOTIFY_CLIENT_ID :=

# The UDID of your iPhone for `make device` and `make logs`;
# `xcrun devicectl list devices` lists it.
DEVICE :=
