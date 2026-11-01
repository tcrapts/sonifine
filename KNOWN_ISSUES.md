# Known issues

## P2 — Volume buttons work only while the app is open

- **Description:** iOS reports volume presses to an app only while it is in the
  foreground with an active audio session.
- **Impact:** On the lock screen or in another app, the buttons change the
  iPhone volume instead of the Sonos volume.
- **Affected code:** `App/VolumeButtonWatcher.swift`.
- **Direction:** a silent audio session in the background could keep the app
  listening. That needs the audio background mode and more battery.

## P2 — Two Spotify connections

- **Description:** the Spotify home comes through the Sonos link, the library,
  search and Liked Songs through the Web API sign-in. The user connects twice.
- **Impact:** one more sign-in, and one more connection that can lapse.
- **Affected code:** `App/SpotifyHome.swift`, `App/Spotify.swift`.
- **Direction:** Sonos's Spotify service also offers the library and search,
  so the Web API sign-in could go.

## P3 — iOS keeps setting the iPhone volume to 10%

- **Description:** on the owner's iPhone, iOS moves the output volume back to 0.1
  after the app moves it to the middle. At the bottom of the scale a press down
  then changes nothing that the app can see.
- **Impact:** an occasional press down that does nothing.
- **Affected code:** `App/VolumeButtonWatcher.swift`, `moveAwayFromEdge`.

## P3 — The heart needs an extra Spotify permission

- **Description:** sign-ins made before the heart existed lack
  `user-library-modify`. The first tap on the heart asks to sign in again.
- **Affected code:** `App/Spotify.swift`, `setLiked`.

## P3 — Artist Play queues few songs

- **Description:** artist Play queues the artist's songs from a Web API search,
  which returns five to ten songs.
- **Affected code:** `App/Spotify.swift`, `tracks(of:)` for `.artist`.

## P3 — Free signing expires after seven days

- **Description:** with a free Apple account the installed app stops starting
  after seven days.
- **Impact:** reinstall with `make device`. A paid developer account lasts a year.
