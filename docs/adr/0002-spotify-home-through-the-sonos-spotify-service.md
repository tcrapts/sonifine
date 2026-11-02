# ADR 0002: Read the Spotify home through Sonos's Spotify service

## Context

The owner wanted Spotify's personal start page in the app, as Sonify shows it: Good
morning with Daily Mix and Release Radar, top mixes, stations. Since November 2024
the Spotify Web API keeps Spotify's own and algorithmic playlists from new apps.

## Decision

The app links to Sonos's Spotify service, the way Sonos apps do (AppLink):

- `getAppLink` gives a Sonos sign-in page; after sign-in, `getDeviceAuthToken`
  gives a token and private key, stored in the Keychain.
- `GET /v1/browse` on `spotify-v5.ws.sonos.com` with the token returns the
  Spotify home as views of playlists, albums and artists.
- `getMetadata` with a Spotify URI returns the songs of any playlist or album.

## Consequences

- Home shows the same rows as Sonify and the Spotify app.
- The user links once; the key renews itself from the service's faults.
- The library sign-in stays for the library, search and Liked Songs, so there
  are two connections (see KNOWN_ISSUES).
- The interface is Sonos's, undocumented for third parties, and can change.
