# Sonifine

Sonifine is an open source iPhone app to control your Sonos, inspired by the
Sonos app and Sonify. The iPhone volume buttons change the Sonos volume in small
steps (1 on a scale of 100 by default), and Spotify and radio play on your
speakers in a tap.

## Features

- **Fine volume:** the volume buttons step the Sonos volume, also on the lock
  screen and in other apps while music plays. Set the step under **System → ⚙️**.
- **Spotify:** your Spotify home, playlists, Liked Songs, albums, podcasts and
  search. Songs play through the Sonos queue; swipe a song for Play Next or Add
  to Queue.
- **Radio:** Sonos Radio, plus favourites you manage: Sonos Radio stations or
  stream addresses of your own, which start fast and without ads.
- **Lists:** every list has search, sorting and filters.
- **Now Playing:** cover, progress, shuffle, repeat and the queue; swipe the
  cover to skip. The lock screen shows what plays.
- **Rooms:** volume per room, and each room's bass, treble, loudness and
  Trueplay.

## Getting started

You need a Mac with Xcode 27, an Apple account in Xcode (Settings → Accounts)
and an iPhone on the same Wi-Fi as your Sonos.

1. **Your settings.** Copy `.env.example` to `.env` and fill it in: your Apple
   Team ID, a bundle ID of your own, your iPhone's UDID and, optionally, a
   Spotify client ID.
2. **Spotify (optional).** The Spotify home, playlists, search and playback work
   through your Sonos without any setup. For podcasts, recently played and the
   heart, create an app at
   [developer.spotify.com](https://developer.spotify.com/dashboard) with the
   redirect URI `finevolume://spotify-callback`, add your Spotify account under
   **User Management**, and put its client ID in `.env`.
3. **Install.** Connect your iPhone once over the cable with Developer Mode on,
   then run `make device`. After that, Wi-Fi is enough.

`make help` lists the other targets, such as `make build` for the simulator and
`make test`. [docs/development.md](docs/development.md) has the details and
fixes for common install errors.

## More

- [Architecture](docs/architecture.md) and the decisions in [docs/adr](docs/adr)
- [Known issues](KNOWN_ISSUES.md)
- [Glossary](CONTEXT.md)
