# Sonifine

Sonifine is an iOS app that controls Sonos from the iPhone, modelled on Sonify.
What sets it apart: the iPhone volume buttons change the Sonos volume in small
steps, 1 on a scale of 100 by default. Set the step size under **System → ⚙️**.

## What the app does

- **Home** shows your Spotify home page: Jump back in, Daily Mix, Release Radar,
  Your top mixes, radio stations and more. The ▶ on a cover plays it at once.
- **Library** shows your playlists, all your Liked Songs and your albums. With ↑↓
  at the top right you sort Liked Songs and playlists by title, artist, album or
  **Recently added**; choose the same key again for the other direction. Play and
  Shuffle follow that order.
- **Search** searches all of Spotify for songs, artists, albums and playlists.
- Each song has a ⋯ menu with **Play Next** and **Add to Queue**. Swipe right on a
  song, album or playlist for Play Next, left for Add to Queue; on a cover, touch
  and hold. The song that plays shows in green.
- **System** shows every room with what it plays, play/pause and volume.
- The slider icon on a room (or **System → ⚙️ → Rooms**) shows the sound of that
  room: bass, treble, loudness, Trueplay and **Reset to default**. Below it are
  its speakers with model, ID, serial number, versions and IP address.
- **Now Playing** has the progress, shuffle, repeat, the queue, a heart for Liked
  Songs, and "Go to album/artist" in the ⋯ menu. A long title scrolls. Swipe the
  cover left for the next song, right for the previous one.
- The volume buttons work while the app is open, and also on the lock screen and
  in other apps while the Sonos plays and up to ten minutes after a pause. A bar
  at the top of the app shows the new volume.
- The lock screen and Control Center show what the Sonos plays, with play/pause,
  next, previous and seeking.
- Covers stay in memory, and those of the next three songs load ahead, so a new
  song shows its cover at once.

## Layout

- `App/`: the Swift code and the assets. Xcode picks up every file in this
  folder by itself.
- `Info.plist`: the permissions for the local network, Bonjour, background audio
  and the Spotify sign-in.
- `Sonifine.xcodeproj/`: the Xcode project.
- `SonifineTests/`: the unit tests.
- `scripts/`: helper scripts, such as the one that draws the icon.
- `docs/`: architecture, development, testing and decisions (`docs/adr/`).

## Requirements

- Xcode 27 with the iOS 26 SDK.
- An Apple account in Xcode (Settings → Accounts) to install on an iPhone.
- `uv` for the scripts in `scripts/`.

## Quick start

```bash
make build    # builds for the simulator
make test     # runs the unit tests in the simulator
make device   # builds and installs on the iPhone
make help     # lists all targets
```

## Install on your iPhone

After a change, put the app on your iPhone like this:

1. Unlock the iPhone and keep it on the same Wi-Fi as the Mac, or on the cable.
2. Run `make device`. Your sign-ins stay.

The first time on a new Mac or iPhone takes a few more steps: your Apple account
in Xcode, pairing the iPhone once over the cable with Developer Mode on, and
trusting the developer on the iPhone.
[docs/development.md](docs/development.md#install-on-the-iphone) lists them,
with fixes for the known error messages.

With a free Apple account the app stops opening after seven days; run
`make device` again.
