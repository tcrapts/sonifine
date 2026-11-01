# Development

## Build

`make build` builds for the simulator into `build/`. Xcode picks up every file in
`App/` by itself (a folder-synchronized group), so a new Swift file needs no
project change.

## Install on the iPhone

`make device` builds a signed app and installs it on the owner's iPhone 15 Pro
(`DEVICE` in the `Makefile`). It is the only step after a change.

### Once per Mac and iPhone

1. **Xcode.** Install Xcode 27 with the iOS 26 SDK, open it once, and accept
   the licence.
2. **Apple account.** In Xcode, Settings → Accounts, add the owner's Apple account.
   Signing uses its team `TEAMID1234`; `make device` creates the certificate and
   profile itself (`-allowProvisioningUpdates`).
3. **Pair the iPhone.** Connect it with a cable, unlock it and tap **Trust This
   Computer**. Then turn on Settings → Privacy & Security → **Developer Mode** on
   the iPhone; it restarts. After that, Wi-Fi is enough.
4. **First install.** Run `make device`. iOS asks to trust the developer once:
   Settings → General → VPN & Device Management → the Apple account → **Trust**.

### Each time

1. Unlock the iPhone and keep it on the same Wi-Fi as the Mac, or on the cable.
2. Run `make device`. The app opens with the logins it had: the bundle ID
   `com.example.sonifine` stays the same.

### Another iPhone

`xcrun devicectl list devices` lists the iPhones with their UDID. Install on one
with `make device DEVICE=<udid>`, after the steps above for that iPhone.

### When it fails

| Message | Fix |
| --- | --- |
| `unavailable` in `xcrun devicectl list devices` | Unlock the iPhone and turn on Wi-Fi, or use the cable. |
| error 4016, or "device was not, or could not be, unlocked" | Unlock the iPhone and run it again. |
| No signing certificate, or no account for team | Add the Apple account in Xcode, Settings → Accounts. |
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
screens work there. It has no volume buttons. In T3 Code, open it with the
device tools and drive it with the `agent-device` command they return.
