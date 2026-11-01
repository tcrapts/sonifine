# Sonifine — Context

The vocabulary of the app. Code, docs and reviews use these words.

## Sonos

**Room**:
One Sonos speaker, or a set that plays as one (a stereo pair, a home cinema).
Sonos calls it a zone. Its name, such as `Symfonisk`, comes from the Sonos app.

**Group**:
Rooms that play the same music together. A room on its own is a group of one.
The app shows and controls groups; `SonosGroup.name` is the coordinator's room
plus the count of the others, such as `Kitchen + 2`.

**Coordinator**:
The player that leads a group. Playback, the queue and the group volume go to
the coordinator. `SonosGroup.coordinator` is its address, such as
`http://192.168.1.147:1400`.

**Selected group**:
The group that the volume buttons, the mini-player and Now Playing control.
The user picks it in the room menu or on the System tab.

**Queue**:
The list of songs a group plays, `Q:0` on the coordinator. Playing something
from Spotify replaces the queue.

**Group volume**:
The volume of a whole group, 0–100. A relative change keeps the ratios between
the rooms.

**Household**:
All Sonos players of one home, with an ID such as `Sonos_Ab12Cd34…`. The Sonos
Spotify service needs it.

## Volume buttons

**Press**:
One press of an iPhone volume button. iOS reports it as a change of the iPhone
output volume of one step of 1/16.

**Step size**:
How many points of the Sonos group volume one press changes, 1–10. Stored per
installation in `UserDefaults` under `stepSize`.

**Volume overlay**:
The bar at the top that shows the group volume after each press. It replaces the
iOS volume overlay, which the app hides because that one shows the iPhone volume.

## Spotify

**Spotify home**:
Spotify's personal start page: Good morning, Daily Mix, Release Radar, top mixes,
stations. It comes from Sonos's Spotify service, through the **link**.

**Link** (Sonos link):
The connection between the app and Sonos's Spotify service. The user makes it
once on a Sonos sign-in page ("Connect Spotify"). It gives a token and key,
stored in the Keychain.

**Library sign-in** (Web API sign-in):
The connection between the app and the Spotify Web API, through the owner's app on
developer.spotify.com. It gives the library, search, artists and Liked Songs.

**Show** (podcast):
A Spotify podcast, `spotify:show:<id>`. The library lists the shows the user
follows. A show has no place in the Sonos queue; its episodes do.

**Episode**:
One part of a show, `spotify:episode:<id>`. It plays on its own, from its
**resume position**: where the user stopped, as Spotify reports it.

**Spotify account on Sonos**:
The Spotify account that is added in the Sonos app. Playback always uses it, as
service `sid=9` with account `sn=1`, read from the track URIs Sonos plays.

## Sonos Radio

**Sonos Radio**:
Sonos's own free radio, service `sid=303`. Browsing and searching need no
sign-in.

**Station**:
Something Sonos Radio plays without end: a program of its own (`sonos:2997`)
or a live station (`tunein:5668`). A station plays instead of the queue and
leaves the queue as it was.

**Sonos Radio account**:
The household's account for Sonos Radio, account number `sn`, which differs per
household. The app reads it from a Sonos Radio station a group plays.
