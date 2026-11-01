# Development

## Build

`make build` builds for the simulator into `build/`. Xcode picks up every file in
`App/` by itself (a folder-synchronized group), so a new Swift file needs no
project change.

## Install on the iPhone

`make device` builds a signed app and installs it on the owner's iPhone 15 Pro.

- Xcode needs the owner's Apple account under Settings → Accounts; signing uses team
  `TEAMID1234`.
- The iPhone is unlocked and on the same Wi-Fi as the Mac, or on the cable.
  `xcrun devicectl list devices` shows it as `connected` or `available`.
  `unavailable` means Wi-Fi off or a locked phone; error 4016 means locked.
- On the first install of a new certificate, iOS asks the owner to trust it under
  Settings → General → VPN & Device Management.
- In a sandboxed agent shell, `xcodebuild` signing and `devicectl` need the
  sandbox off: they read the Xcode account and the device tunnel.

## Logs from the iPhone

`make logs` restarts the app on the iPhone and streams the `VolumeButtons` log
(`OS_ACTIVITY_DT_MODE` sends `os.Logger` output to the console). Each line shows
the iPhone volume before and after, and whether the app counted it as a press.
`NowPlaying` lines show when the silent audio starts and stops.

## Icon

`make icon` redraws `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with
`scripts/make_icon.py`: a flat volume dial with a few bold steps, more than half lit.

## Simulator

The simulator reaches the Sonos on the LAN, so discovery, playback and the Spotify
screens work there. It has no volume buttons. In T3 Code, open it with the
device tools and drive it with the `agent-device` command they return.
