# Known issues

## P1 — Spotify's quota for development apps runs out

- **Description:** since July 2026 Spotify gives development-mode apps one quota per
  developer account, and answers 429 with `QUOTA_EXCEEDED` when it is used up. It
  doesn't say how large it is or when it resets. On 1 November 2026 a day of
  simulator and subagent tests used it up, and the library stayed empty.
- **Impact:** the library, search, podcasts and the heart stop working until the
  quota resets. Sonos playback keeps working.
- **Affected code:** `App/Spotify/SpotifyWebAPI.swift`, `App/Spotify/SpotifyCatalog.swift`.
- **Direction:** playlists, Liked Songs, albums, search and playlist songs now come
  through Sonos's Spotify service, which has no such quota. Podcasts, recently
  played and the heart still need the Web API; the link has no podcasts.

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
