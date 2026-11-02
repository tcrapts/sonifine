# Architecture

Sonifine is a SwiftUI app without third-party packages. Two observable modules
hold the state; the views read them from the environment and start music
through one `\.play` action.

| Module | Folder | Behind its seam |
| --- | --- | --- |
| `SonosController` | `App/Sonos/` | `SonosPlayer`: `SOAPSonosPlayer` talks UPnP to a player |
| `SpotifyCatalog` | `App/Spotify/` | `SpotifyWebAPI` (library sign-in), `SonosSpotifyService` (link) |
| `RadioCatalog` | `App/Radio/` | `SonosRadioService`: Sonos Radio, without sign-in |
| `Favourites` | `App/Radio/` | `UserDefaults`: the favourite stations, in the user's order |

`App/Support/` holds the seams every adapter shares: `HTTPTransport`,
`SecretStore` (the Keychain), `XMLNode`, the one XML reader, and `SMAPI`, the
SOAP request and browse JSON of Sonos music services. `ImageCache`
keeps covers in memory, decoded; after each song change the app loads the covers
of the next three songs in the queue (`SonosController.upcomingArtwork`).
`App/Volume/VolumeButtonWatcher` turns presses into
`SonosController.nudgeVolume`; `VolumePress` holds its rules.
`App/Volume/NowPlayingSession` keeps the buttons and the lock screen for the app.
`PlayRequest` decides what a tap plays; `SpotifyURI` parses every Spotify URI
and encodes it for the Sonos queue; `RadioItem` encodes a station for the
transport URI, and `SonosQueueItem(directStream:)` a custom stream.

## Sonos

- **Discovery.** `NWBrowser` browses Bonjour `_sonos._tcp`. Each TXT record holds
  `location=http://<ip>:1400/xml/device_description.xml`; the first player found
  answers `GetZoneGroupState`, which lists every group, its coordinator and rooms
  (`SonosGroup.groups(fromZoneGroupState:)`).
- **Control.** `SOAPSonosPlayer` posts SOAP actions to port 1400 of a coordinator:
  `AVTransport` (play, pause, seek, queue, play mode), `GroupRenderingControl`
  (group volume), `ContentDirectory` (`Browse Q:0` for the queue),
  `DeviceProperties` (household ID) and `ZoneGroupTopology`.
- **Status.** `refresh()` reads the status of every group every three seconds
  and after each action: volume, transport state, position, play mode, the
  track metadata and, from `GetMediaInfo`, the source. A `CurrentURI` such as
  `x-sonosapi-radio:`, `x-sonosapi-stream:` or `x-rincon-mp3radio:` means radio:
  `GroupStatus.station` holds the station from `CurrentURIMetaData`, and its
  `albumArtURI` is the cover when the track has none. A title that is a file
  name, such as `BNR_NIEUWSRADIO.mp3?dist=other`, is left out. While a stream
  starts, `r:streamContent` says `ZPSTR_CONNECTING` or `ZPSTR_BUFFERING`
  (`GroupStatus.streamProgress`).
- **Room sound and devices.** Bass, treble, loudness and Trueplay belong to a
  room, so they go to the room's own player:
  `RenderingControl` `GetBass`/`SetBass`, `GetTreble`/`SetTreble`,
  `GetLoudness`/`SetLoudness` (channel `Master`) and `GetRoomCalibrationStatus`
  (`RoomCalibrationEnabled` is Trueplay). Each `SonosRoom` in `SonosGroup.rooms`
  keeps its player address and the players in it (a stereo partner, a Sub,
  surrounds); `/xml/device_description.xml` of each describes the device.
  `RoomSettingsView` shows them; a slider sends its value when released.
- **Volume.** Presses add up in `pendingAdjustment`; one
  `SnapshotGroupVolume` + `SetRelativeGroupVolume` request carries them, so a
  held button sends few requests.

## Playing Spotify

Playback goes through the Spotify account on Sonos, as
[ADR 0001](adr/0001-play-spotify-through-the-sonos-queue.md) explains.
`SonosController.play` hands `SOAPSonosPlayer.replaceQueue` the items: it clears the queue, adds the items with
`AddMultipleURIsToQueue` (16 per call), sets the play mode, seeks to the chosen
song, and plays. `SpotifyURI.queueItem` builds each URI and its DIDL metadata:

| Spotify URI | Sonos URI |
| --- | --- |
| `spotify:playlist:<id>` | `x-rincon-cpcontainer:1006206cspotify%3aplaylist%3a<id>` |
| `spotify:album:<id>` | `x-rincon-cpcontainer:1004206cspotify%3aalbum%3a<id>` |
| `spotify:track:<id>` | `x-sonos-spotify:spotify%3atrack%3a<id>?sid=9&flags=8224&sn=1` |
| `spotify:episode:<id>` | `x-sonos-spotify:spotify%3aepisode%3a<id>?sid=9&flags=8224&sn=1` |

The metadata names the service as `SA_RINCON<sid × 256 + 7>_X_#Svc…-0-Token`.

A podcast episode plays on its own, from where the user stopped, as
[ADR 0006](adr/0006-play-podcast-episodes-one-by-one-from-the-web-api.md)
explains: `PlayRequest.episode` queues it, seeks with `Seek REL_TIME` and plays.
A show has no Sonos URI; Play on a show plays its newest episode.

## Playing Sonos Radio

Sonos Radio (service 303) plays as the transport URI instead of the queue, as
[ADR 0005](adr/0005-play-sonos-radio-as-the-transport-uri.md) explains.
`SonosController.play(.station)` hands `SOAPSonosPlayer.playStream` the URI and
DIDL from `RadioItem.stream(account:)`; it sends `SetAVTransportURI` and `Play`.

| Station | Sonos URI |
| --- | --- |
| `sonos:<n>` (Sonos Radio's own) | `x-sonosapi-radio:<n>?sid=303&flags=0&sn=<account>` |
| `tunein:<n>` (live) | `x-sonosapi-stream:tunein%3a<n>?sid=303&flags=8232&sn=<account>` |

The account number comes from a Sonos Radio URI a group played, stored under
`sonosRadioSerialNumber`. `SonosRadioService` reads, without sign-in:
`GET https://sali.sonos.superhi.fi/browse/v1` for the home rows and SOAP
`getMetadata` (a category) and `search` (`id` `stations`) on
`https://sali.sonos.superhi.fi/smapi`.

A station counts as playing once the speaker reports `PLAYING`: after 15
seconds without, or 30 while it connects or buffers, the app tries the next
account number. A TuneIn station first asks for an ad, which a DNS filter can
hold up for over ten seconds.

## Favourites

The Sonos Radio home starts with the user's favourites, as
[ADR 0007](adr/0007-favourites-with-two-sources.md) explains. `Favourites`
(`App/Radio/Favourites.swift`) keeps them as JSON in `UserDefaults` under
`radioFavourites`; the first launch fills in thirteen Dutch custom streams.
`FavouritesView` puts them in order, removes, edits and adds them; a Sonos
Radio station's ⋯ or touch-and-hold menu adds it.

| Source | Plays as |
| --- | --- |
| Sonos Radio station | `PlayRequest.station`, as above |
| Custom stream `<address>` | `PlayRequest.stream`: `x-rincon-mp3radio://<address>` with item `R:0/0/0`, service `SA_RINCON65031_` and the logo as `upnp:albumArtURI` |

`StreamCheck` checks a new custom stream: an http or https address, which
answers with an audio type. It reads the headers and first bytes of an https
address; iOS keeps the app from http addresses, which it keeps unchecked.

While radio plays, Now Playing hides the progress and turns off shuffle and repeat; the
covers ahead and beside come from no queue.

## The two Spotify connections

- **Link** (`SonosSpotifyService`), see [ADR 0002](adr/0002-spotify-home-through-the-sonos-spotify-service.md).
  SOAP endpoint `https://spotify-v5.ws.sonos.com/smapi` with AppLink: `getAppLink`
  gives a sign-in page, `getDeviceAuthToken` gives a token and key after sign-in.
  `GET https://spotify-v5.ws.sonos.com/v1/browse` with `Authorization: Bearer
  <token>` returns the Spotify home as JSON views. `getMetadata` with a Spotify
  URI as ID returns the songs of any playlist or album, Spotify's own included.
  An expired key comes back renewed in a `Client.TokenRefreshRequired` fault.
- **Library sign-in** (`SpotifyWebAPI`). Authorization code with PKCE for
  the client ID of the owner's app on developer.spotify.com, redirect URI
  `finevolume://spotify-callback`. It reads playlists, Liked Songs, saved albums,
  followed podcasts (`/me/shows`) and their episodes (`/shows/{id}/episodes`,
  with `resume_point` under scope `user-read-playback-position`), recently
  played, search, artists and changes Liked Songs. The Web API hides
  Spotify's own playlists from new apps; `SpotifyCatalog.songs(of:)` then falls back to the link.

Both keep their keys in the Keychain.

## Volume buttons

See [ADR 0003](adr/0003-volume-buttons-through-the-system-volume.md). iOS has no
API for the buttons. `VolumeButtonWatcher` observes
`AVAudioSession.outputVolume`: a change of one step (more than 0.03, less than
0.1) is a press, up or down. Near the top or bottom of the scale it moves the
iPhone volume to the middle once, through the slider of a hidden
`MPVolumeView`, which also keeps the iOS volume overlay away. `VolumeOverlay`
shows the Sonos volume instead.

`NowPlayingSession` holds the buttons for the app, as
[ADR 0004](adr/0004-claim-the-volume-buttons-as-the-now-playing-app.md)
explains: silent audio in a non-mixable `.playback` session, the song of the
selected group in `MPNowPlayingInfoCenter`, and the lock-screen commands. In the
background the silence stops ten minutes after the Sonos pauses (`KeepAwake`).

## Screens

`SonifineApp` holds four tabs (Home, Library, Search, System), each a
`NavigationStack` with the mini-player above the tab bar. Every screen opens
through a value (`SpotifyItem`, `LibraryPage`, `RadioPage`) and `spotifyDestinations()`,
which opens a podcast in `ShowView` and other Spotify items in `DetailView`;
mixing in destination links breaks value navigation in pushed screens.

Every list of items is an `ItemList` (`App/Views/ItemList.swift`): the library
pages, `DetailView`, `ShowView` and the Sonos Radio categories. It holds the
search field, the `SortMenu`, `FilterChips` when the items are of two kinds or
more, and the rows the page gives it, under an optional `ListHeader`.
`ListQuery` (`App/Spotify/ListOrder.swift`) decides what shows: search text,
kind and `ListOrder`, over anything `Listable`. The sort choice is kept in
`UserDefaults`, one key per kind of list. The header and rows get the items as
shown; once a list is searched, filtered or sorted, a song plays with those
songs instead of inside its playlist.
The room settings open the same way, through a `SonosRoom`: the slider button on
a room card on the System tab, or **Rooms** in the ⚙️ sheet.
