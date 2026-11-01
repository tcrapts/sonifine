# Architecture

Sonifine is a SwiftUI app without third-party packages. Two observable modules
hold the state; the views read them from the environment and start music
through one `\.play` action.

| Module | Folder | Behind its seam |
| --- | --- | --- |
| `SonosController` | `App/Sonos/` | `SonosPlayer`: `SOAPSonosPlayer` talks UPnP to a player |
| `SpotifyCatalog` | `App/Spotify/` | `SpotifyWebAPI` (library sign-in), `SonosSpotifyService` (link) |

`App/Support/` holds the seams every adapter shares: `HTTPTransport`,
`SecretStore` (the Keychain) and `XMLNode`, the one XML reader. `ImageCache`
keeps covers in memory, decoded; after each song change the app loads the covers
of the next three songs in the queue (`SonosController.upcomingArtwork`).
`App/Volume/VolumeButtonWatcher` turns presses into
`SonosController.nudgeVolume`; `VolumePress` holds its rules.
`App/Volume/NowPlayingSession` keeps the buttons and the lock screen for the app.
`PlayRequest` decides what a tap queues; `SpotifyURI` parses every Spotify URI
and encodes it for the Sonos queue.

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
  and after each action: volume, transport state, position, play mode and the
  track metadata.
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

The metadata names the service as `SA_RINCON<sid × 256 + 7>_X_#Svc…-0-Token`.

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
  recently played, search, artists and changes Liked Songs. The Web API hides
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
through a value (`SpotifyItem`, `LibraryPage`) and `spotifyDestinations()`;
mixing in destination links breaks value navigation in pushed screens.
The room settings open the same way, through a `SonosRoom`: the slider button on
a room card on the System tab, or **Rooms** in the ⚙️ sheet.
