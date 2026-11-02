# ADR 0006: Play podcast episodes one by one, listed by the Web API

## Context

The owner wanted their Spotify podcasts in the app: the shows they follow, their
episodes, podcasts in Search, and an episode on the Sonos from where they stopped.

Since February 2026 the Web API keeps, for apps in development mode,
`GET /me/shows` (scope `user-library-read`), `GET /shows/{id}/episodes`,
`GET /episodes/{id}` and search with `type=show,episode`. It drops the show and
episode library writes and the batch reads. An episode carries `resume_point`
(`resume_position_ms`, `fully_played`) only for a sign-in with
`user-read-playback-position`.

On Sonos an episode is a track of the Spotify account, as SoCo's share-link
plugin queues it (pull request 902):

| Spotify URI | Sonos URI | DIDL item ID | Class |
| --- | --- | --- | --- |
| `spotify:episode:<id>` | `x-sonos-spotify:spotify%3aepisode%3a<id>?sid=9&flags=8224&sn=1` | `00032020spotify%3aepisode%3a<id>` | `object.item.audioItem.musicTrack` |

A Symfonisk speaker resolves that URI through the household's Spotify account:
its cover-art lookup `GET /getaa?s=1&u=<URI>` answered 200 with the cover of
`spotify:episode:0FuKEjteM0cGzy7pznCkAj`, and 404 for a made-up ID. A show as a
container (`x-rincon-cpcontainer:1006206cspotify%3ashow%3a<id>`) has no such
check; the lookup answers 404 for every container, playlists included.

## Decision

- The library sign-in lists podcasts: followed shows in the library, a show's
  newest hundred episodes on its page, shows and episodes in Search. The sign-in
  asks for `user-read-playback-position` as well.
- A tap on an episode replaces the queue with that episode alone, seeks to
  where the user stopped (`Seek REL_TIME`), and plays. When Sonos refuses the
  seek before playing, the app seeks again once it plays. An episode played to
  the end, or to its last 30 seconds, starts at the beginning.
- Play on a show plays its newest episode.
- Song lists keep songs only: an episode never joins the songs of a playlist,
  Liked Songs or a search.

## Consequences

- Podcasts need the library sign-in; the Sonos link gives no podcasts in the app.
- A sign-in from before this change lists podcasts but no progress. The show
  page then offers to sign in again.
- Sonos plays the episode with the Spotify account in the Sonos app. Whether
  Spotify then saves the new position for that account is Spotify's matter.
- Now Playing knows an episode from its track URI: it shows it in green in the
  show's list and offers "Go to podcast" instead of album, artist and the heart.
