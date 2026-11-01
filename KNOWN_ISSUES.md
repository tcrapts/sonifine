# Known issues

## P2 — Volume buttons work only while the app is open

- **Description:** iOS reports volume presses to an app only while it is in the
  foreground with an active audio session.
- **Impact:** On the lock screen or in another app, the buttons change the
  iPhone volume instead of the Sonos volume.
- **Affected code:** `App/Volume/VolumeButtonWatcher.swift`.
- **Direction:** a silent audio session in the background could keep the app
  listening. That needs the audio background mode and more battery.

## P2 — Two Spotify connections

- **Description:** the Spotify home comes through the Sonos link, the library,
  search and Liked Songs through the Web API sign-in. The user connects twice.
- **Impact:** one more sign-in, and one more connection that can lapse.
- **Affected code:** `App/Spotify/SonosSpotifyService.swift`, `App/Spotify/SpotifyWebAPI.swift`.
- **Direction:** Sonos's Spotify service also offers the library and search,
  so the Web API sign-in could go.

## P1 — Another app turns the buttons into big Sonos steps

- **Description:** at times the iPhone volume mirrors the Sonos volume: iOS
  sends each press straight to the Sonos, in steps of 5% of the iPhone scale,
  and keeps the iPhone volume at the Sonos volume. The app still counts the
  press and adds its own step on top. On 1 November 2026 the Sonos went
  8 → 16 → 23 → 12 → 8 for four presses, while it played its own queue
  (`x-rincon-queue`, no AirPlay and no Spotify Connect session).
- **Impact:** one press changes the Sonos volume by 6 to 11 instead of the step
  size. iOS also moves the iPhone volume back to the Sonos volume after the app
  moves it to the middle.
- **Affected code:** `App/Volume/VolumeButtonWatcher.swift`.
- **Direction:** the likely owner is the Spotify app, which shows Sonos playback
  as a Connect device and claims the volume buttons for it. Sonifine can claim
  them back by becoming the Now Playing app (silent audio, Now Playing info and
  remote commands), as Sonify does for its lock-screen controls.

## P3 — Artist Play queues few songs

- **Description:** artist Play queues the artist's songs from a Web API search,
  which returns five to ten songs.
- **Affected code:** `App/Spotify/SpotifyWebAPI.swift`, `songs(of:)` for `.artist`.

## P3 — Free signing expires after seven days

- **Description:** with a free Apple account the installed app stops starting
  after seven days.
- **Impact:** reinstall with `make device`. A paid developer account lasts a year.
