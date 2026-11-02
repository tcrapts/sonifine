# Development

## Build

`make build` builds for the simulator into `build/`. Xcode picks up every file in
`App/` by itself (a folder-synchronized group), so a new Swift file needs no
project change.

## Local settings

The Xcode project holds neutral values: no team, bundle ID
`com.example.sonifine`, no Spotify client ID. The Makefile includes `.env`
(git-ignored; copy `.env.example`) and passes its values to `xcodebuild` as
build settings:

| `.env` | Build setting | Used for |
| --- | --- | --- |
| `APPLE_TEAM_ID` | `DEVELOPMENT_TEAM` | Signing for the iPhone. |
| `BUNDLE_ID` | `APP_BUNDLE_IDENTIFIER` | The app's `PRODUCT_BUNDLE_IDENTIFIER`; the tests get `$(APP_BUNDLE_IDENTIFIER).tests`. `make logs` starts the app by it. |
| `SPOTIFY_CLIENT_ID` | `SPOTIFY_CLIENT_ID` | `SpotifyClientID` in Info.plist, which `SpotifyWebAPI` reads. Without it the library sign-in says so. |
| `IPHONE_UDID` | — | The iPhone for `devicectl` in `make device` and `make logs`. |

A value left empty keeps the project's own. One run can override a value, as in
`make device IPHONE_UDID=<udid>`.

## Install on the iPhone

`make device` builds a signed app and installs it on the iPhone in `IPHONE_UDID`
(`.env`). It is the only step after a change.

### Once per Mac and iPhone

1. **Xcode.** Install Xcode 27 with the iOS 26 SDK, open it once, and accept
   the licence.
2. **Apple account.** In Xcode, Settings → Accounts, add your Apple account, and
   put its Team ID in `APPLE_TEAM_ID` in `.env`. `make device` creates the
   certificate and profile itself (`-allowProvisioningUpdates`).
3. **Pair the iPhone.** Connect it with a cable, unlock it and tap **Trust This
   Computer**. Then turn on Settings → Privacy & Security → **Developer Mode** on
   the iPhone; it restarts. After that, Wi-Fi is enough.
4. **First install.** Run `make device`. iOS asks to trust the developer once:
   Settings → General → VPN & Device Management → the Apple account → **Trust**.

### Each time

1. Unlock the iPhone and keep it on the same Wi-Fi as the Mac, or on the cable.
2. Run `make device`. The app opens with the sign-ins it had, as long as
   `BUNDLE_ID` in `.env` stays the same.

### Another iPhone

`xcrun devicectl list devices` lists the iPhones with their UDID. Install on one
with `make device IPHONE_UDID=<udid>`, after the steps above for that iPhone, or put
its UDID in `IPHONE_UDID` in `.env`.

### When it fails

| Message | Fix |
| --- | --- |
| `unavailable` in `xcrun devicectl list devices` | Unlock the iPhone and turn on Wi-Fi, or use the cable. |
| error 4016, or "device was not, or could not be, unlocked" | Unlock the iPhone and run it again. |
| No signing certificate, or no account for team | Add the Apple account in Xcode, Settings → Accounts, and check `APPLE_TEAM_ID` in `.env`. |
| "Failed to register bundle identifier" | Another developer has that bundle ID; choose another `BUNDLE_ID` in `.env`. |
| The app stops opening after seven days | Free signing expires; run `make device` again. A paid developer account lasts a year. |

In a sandboxed agent shell, `xcodebuild` signing and `devicectl` need the
sandbox off: they read the Xcode account and the device tunnel.

## Logs from the iPhone

`make logs` restarts the app on the iPhone and streams the `VolumeButtons` log
(`OS_ACTIVITY_DT_MODE` sends `os.Logger` output to the console). Each line shows
the iPhone volume before and after, and whether the app counted it as a press.
`NowPlaying` lines show when the silent audio starts and stops.

## Icon

`make icon` redraws `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with
`scripts/make_icon.py`: the scale of a volume knob on near black, its lit marks
running from teal through green to lime.

## Simulator

The simulator reaches the Sonos on the LAN, so discovery, playback and the Spotify
screens work there. It has no volume buttons.
