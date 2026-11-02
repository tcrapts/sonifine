# Sonifine

Sonifine is an iOS app that controls Sonos from the iPhone, modelled on Sonify.
What sets it apart: the iPhone volume buttons change the Sonos volume in small
steps, 1 on a scale of 100 by default. Set the step size under **System → ⚙️**.

## What the app does

- **Home** shows your Spotify home page: Jump back in, Daily Mix, Release Radar,
  Your top mixes, radio stations and more. The ▶ on a cover plays it at once.
- **Library** shows your playlists, all your Liked Songs, your albums and the
  podcasts you follow.
- Every list works the same way: the library pages, a playlist, album or artist,
  a podcast's episodes and the Sonos Radio categories. Pull down for a search
  field that filters as you type, on title, artist and album, whatever the case
  or accents. With ↑↓ at the top right you sort by title, artist, album,
  **Recently added** or **Release date**, as far as the list has them; choose
  the same key again for the other direction. Each kind of list remembers its
  sort. A list that mixes kinds, such as stations and categories, has filter
  chips. Play, Shuffle and a tapped song play the songs as the list shows them.
- At the top of Home you choose **Spotify** or **Sonos Radio**. Sonos Radio shows
  your **Favourites** first, then its rows of stations, then Music, News & Talk,
  Sports and Locations to browse. The ▶ on a station plays it on the selected
  room instead of the queue.
- **Favourites** starts with thirteen Dutch stations (NPO, BNR, Qmusic, 538, Sky
  Radio and more) as their own streams, which start in seconds and without ads.
  Tap the **Favourites** title to manage them: **Edit** to drag them in order or
  remove them, tap one to change its name, logo or address, and **+** to add a
  Sonos Radio station or a custom stream. The ⋯ of a Sonos Radio station, or
  touch and hold on its cover, adds it to your favourites.
- **Search** searches all of Spotify for songs, artists, albums, playlists and
  podcasts (the **Podcasts** filter shows shows and episodes), and Sonos Radio
  for stations (the **Radio** filter).
- A podcast shows its episodes, newest first, with date, length and how far you
  listened. Tap an episode to play it on the Sonos from where you stopped.
- Each song has a ⋯ menu with **Play Next** and **Add to Queue**. Swipe right on a
  song, album or playlist for Play Next, left for Add to Queue; on a cover, touch
  and hold. The song that plays shows in green.
- Scrolling down folds the tab bar, and the mini-player moves into it.
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

## Getting started

### What you need

- A Mac with Xcode 27 and the iOS 26 SDK.
- An Apple account, added in Xcode under Settings → Accounts. A free account
  works; its apps stop opening after seven days until you install again.
- An iPhone on the same Wi-Fi as your Sonos speakers.
- `uv`, for the scripts in `scripts/` only.
- For the library sign-in, a Spotify developer app of your own (below).

### Spotify

The app connects to Spotify in two ways ([architecture](docs/architecture.md#the-two-spotify-connections)):

- **Get your Spotify home** links the app to the Spotify account in your Sonos
  system, through Sonos's own Spotify service. It needs no setup: the Spotify
  home, your playlists on Home, search and playback work with this link alone.
- **Connect your library** signs in to the Spotify Web API with your own
  developer app. It adds the Library tab, podcasts, recently played and the
  heart for Liked Songs.

To create the developer app:

1. Sign in at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
   and create an app with the **Web API**.
2. Add the redirect URI `finevolume://spotify-callback`, exactly like that.
3. Under **User Management**, add the Spotify account you listen with.
4. Copy the **Client ID**; it goes into `local.mk`.

A new app runs in Spotify's development mode: only the accounts under User
Management can sign in, a few at most, and all of them share one request quota
per developer account ([KNOWN_ISSUES](KNOWN_ISSUES.md)). For one household that
is enough.

### Your settings

The Makefile reads your own values from `local.mk`, which git ignores:

```bash
cp local.example.mk local.mk
```

Fill it in; `local.example.mk` explains each value:

| Value | What |
| --- | --- |
| `TEAM` | Your Apple Team ID: Xcode → Settings → Accounts → your account. |
| `BUNDLE_ID` | A bundle ID of your own, such as `com.yourname.sonifine`. Keep it once installed: the sign-ins live under it. |
| `SPOTIFY_CLIENT_ID` | The Client ID of your Spotify developer app. |
| `DEVICE` | Your iPhone's UDID, from `xcrun devicectl list devices`. |

The simulator builds with an empty `local.mk`. In the Xcode app, set the same
values on the project instead: `APP_BUNDLE_IDENTIFIER` and `SPOTIFY_CLIENT_ID`
under Build Settings, and your team under Signing & Capabilities.

### Build and install

```bash
make build    # builds for the simulator
make test     # runs the unit tests in the simulator
make device   # builds and installs on the iPhone
make help     # lists all targets
```

The first install on an iPhone takes a few more steps: pairing it once over the
cable with Developer Mode on, and trusting the developer on the iPhone.
[docs/development.md](docs/development.md#install-on-the-iphone) lists them,
with fixes for the known error messages. After that, unlock the iPhone, keep it
on the same Wi-Fi as the Mac or on the cable, and run `make device`; your
sign-ins stay.

## Layout

- `App/`: the Swift code and the assets. Xcode picks up every file in this
  folder by itself.
- `Info.plist`: the permissions for the local network, Bonjour, background audio
  and the Spotify sign-in.
- `Sonifine.xcodeproj/`: the Xcode project.
- `local.example.mk`: the template for `local.mk`, your own team, bundle ID,
  Spotify client ID and iPhone.
- `SonifineTests/`: the unit tests.
- `scripts/`: helper scripts, such as the one that draws the icon.
- `docs/`: architecture, development, testing and decisions (`docs/adr/`).
