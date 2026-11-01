# Known issues

## P2 — Two Spotify connections

- **Description:** the Spotify home comes through the Sonos link, the library,
  search and Liked Songs through the Web API sign-in. The user connects twice.
- **Impact:** one more sign-in, and one more connection that can lapse.
- **Affected code:** `App/Spotify/SonosSpotifyService.swift`, `App/Spotify/SpotifyWebAPI.swift`.
- **Direction:** Sonos's Spotify service also offers the library and search,
  so the Web API sign-in could go.

## P3 — Artist Play queues few songs

- **Description:** artist Play queues the artist's songs from a Web API search,
  which returns five to ten songs.
- **Affected code:** `App/Spotify/SpotifyWebAPI.swift`, `songs(of:)` for `.artist`.

## P3 — Free signing expires after seven days

- **Description:** with a free Apple account the installed app stops starting
  after seven days.
- **Impact:** reinstall with `make device`. A paid developer account lasts a year.
