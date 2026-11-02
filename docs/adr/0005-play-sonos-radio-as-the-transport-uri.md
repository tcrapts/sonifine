# ADR 0005: Play Sonos Radio as the transport URI, with the household's account

## Context

The owner wanted Sonos Radio (service 303, Sonos's own free radio) next to Spotify.
`MusicServices#ListAvailableServices` lists it with SMAPI endpoint
`https://sali.sonos.superhi.fi/smapi` and `Auth="DeviceLink"`. Its manifest
names a JSON home at `https://sali.sonos.superhi.fi/browse/v1`.

Browsing and searching answer without a sign-in: `GET /browse/v1` gives the
home rows, and SOAP `getMetadata` and `search` give categories and stations
with an empty credentials header. `getMediaURI`, which gives the audio, answers
empty without the household's DeviceLink token; only the speaker holds that.

A radio station is a stream, so it has no place in the queue. The URI format
comes from favourites the Sonos app made (node-red-contrib-sonos-plus discussion
245, Sonos Community "Sonos radio playback jittery"):

| Station | URI | DIDL item ID |
| --- | --- | --- |
| Sonos Radio program `sonos:154250` | `x-sonosapi-radio:154250?sid=303&flags=0&sn=<n>` | `000c0000154250` |
| live station `tunein:4381` | `x-sonosapi-stream:tunein%3a4381?sid=303&flags=8232&sn=<n>` | `10092028tunein%3a4381` |

Both use class `object.item.audioItem.audioBroadcast` and the service token
`SA_RINCON77575_X_#Svc77575-0-Token` (303 × 256 + 7). The account number `sn` is
the household's own index of its Sonos Radio account (seen elsewhere as 7 and
20); the test speaker keeps no favourite, alarm or status page that shows it.

## Decision

- The app browses and searches Sonos Radio anonymously through
  `SonosRadioService`, with the same SMAPI request and browse JSON as the
  Spotify link.
- A station plays on the coordinator with `SetAVTransportURI` (URI and DIDL as
  above) and `Play`. The queue stays as it was.
- The app learns `sn` the way it learns the Spotify account: from any URI with
  `sid=303` that a group plays (`GetMediaInfo` `CurrentURI` or the track URI),
  stored in `UserDefaults` under `sonosRadioSerialNumber`. Until then a tap on
  a station asks the user to play one Sonos Radio station in the Sonos app once.

## Consequences

- No sign-in or link for radio; browsing works on every installation.
- Playing needs one station played from the Sonos app first, once per installation.
- After radio, the queue still holds the last Spotify music; Now Playing shows
  the station, hides the progress and turns off shuffle and repeat while radio plays.
- The endpoints and the URI format are Sonos's own, undocumented for third
  parties, and can change.
