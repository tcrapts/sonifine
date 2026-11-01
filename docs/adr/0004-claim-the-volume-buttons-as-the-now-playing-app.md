# ADR 0004: Claim the volume buttons as the Now Playing app

## Context

ADR 0003 reads presses from the iPhone output volume. On 1 November 2026 one
press moved the Sonos by 6 to 11 points. Another app, most likely Spotify with
the Sonos as its Connect device, held the volume buttons: iOS sent each press to
the Sonos itself in steps of 5%, and kept the iPhone volume at the Sonos volume.
Sonifine's ambient, mixable audio session left that app in charge. iOS gives
the buttons to the app it considers to be playing.

## Decision

`NowPlayingSession` makes Sonifine that app. It plays a looping buffer of
silence through `AVAudioEngine` in a non-mixable `.playback` session, with the
`audio` background mode. It fills `MPNowPlayingInfoCenter` with the song of the
selected group after every poll, and answers the lock-screen commands play,
pause, next, previous and seek with `SonosController`.

The silence starts when the app comes to the foreground; iOS allows starting
audio only there. In the background it stops once the Sonos has been paused for
ten minutes (`KeepAwake`), and iOS then suspends the app. After an interruption,
such as a call, it starts again.

## Consequences

- The volume buttons keep their small steps while another app steers the Sonos.
- The buttons also work on the lock screen and in other apps, while the Sonos
  plays and for ten minutes after it pauses.
- The lock screen and Control Center show the Sonos song with its controls.
- Opening Sonifine stops other audio on the iPhone, such as a podcast.
- Running silent audio costs some battery while the app stays awake.
