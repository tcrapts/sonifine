# Known issues

## P2 — Two Spotify connections

- **Description:** the Spotify home comes through the Sonos link, the library,
  search and Liked Songs through the Web API sign-in. The user connects twice.
- **Impact:** one more sign-in, and one more connection that can lapse.
- **Affected code:** `App/Spotify/SonosSpotifyService.swift`, `App/Spotify/SpotifyWebAPI.swift`.
- **Direction:** Sonos's Spotify service also offers the library and search,
  so the Web API sign-in could go.

## P1 — The fix for big volume steps is untested on the iPhone

- **Description:** at times another app, most likely Spotify, held the volume
  buttons: iOS sent each press straight to the Sonos in steps of 5%, and the app
  added its own step on top. On 1 November 2026 four presses moved the Sonos
  8 → 16 → 23 → 12 → 8. ADR 0004 makes Sonifine the Now Playing app to take the
  buttons back. The simulator shows the app as Now Playing and awake in the
  background; it has no volume buttons and no Spotify app.
- **Impact:** until a test on the iPhone, a press may still move the Sonos by 6
  to 11.
- **Affected code:** `App/Volume/NowPlayingSession.swift`, `App/Volume/VolumeButtonWatcher.swift`.
- **Direction:** with Spotify showing the Sonos as its device, press with
  Sonifine open, then on the lock screen, while `make logs` runs and the Sonos
  volume is logged.

## P3 — Artist Play queues few songs

- **Description:** artist Play queues the artist's songs from a Web API search,
  which returns five to ten songs.
- **Affected code:** `App/Spotify/SpotifyWebAPI.swift`, `songs(of:)` for `.artist`.

## P3 — Free signing expires after seven days

- **Description:** with a free Apple account the installed app stops starting
  after seven days.
- **Impact:** reinstall with `make device`. A paid developer account lasts a year.
