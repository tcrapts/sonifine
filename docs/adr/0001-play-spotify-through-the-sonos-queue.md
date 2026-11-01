# ADR 0001: Play Spotify through the Sonos queue

## Context

The first version played music with the Spotify Web API on a Spotify Connect
device. Spotify's device list left out the owner's Symfonisk, even while it played
Spotify, so nothing played.

## Decision

The app asks the Sonos coordinator to play: it fills the group's queue with
Spotify URIs (`AddMultipleURIsToQueue`) and plays it. Sonos streams them with the
Spotify account added in the Sonos app. The app reads that account's service ID
and account number from the track URIs Sonos plays.

## Consequences

- Playback needs no Spotify device list and works for every group.
- Playing replaces the queue of the group.
- Playback uses the Spotify account in the Sonos app, whatever account the app
  signed in with.
- A playlist or album in the queue counts as one added item; starting at a song
  uses `Seek TRACK_NR` afterwards.
