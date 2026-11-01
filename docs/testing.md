# Testing

`make test` runs the unit tests in `SonifineTests/` (Swift Testing) in the
simulator, without network: recorded Sonos and Spotify answers go through a
`RecordedTransport`, and `FakeSonosPlayer` stands in for a speaker. Test
behaviour through the module interfaces; add a recorded answer for each new
format. Beyond that, a change is verified by using it, and every Sonos action
by asking the speaker what it did.

## Verify a change

1. **Build and install** in the simulator, then open the screen you changed.
2. **Use it** the way the owner would: tap through the path, not only the screen.
   Rows that sit behind the mini-player need a scroll first.
3. **Ask the Sonos.** After an action, read the result from the coordinator
   instead of trusting the screen:

   | What | SOAP action | Field |
   | --- | --- | --- |
   | song and queue place | `AVTransport#GetPositionInfo` | `Track`, `TrackMetaData`, `RelTime` |
   | queue length | `AVTransport#GetMediaInfo` | `NrTracks` |
   | playing or paused | `AVTransport#GetTransportInfo` | `CurrentTransportState` |
   | shuffle and repeat | `AVTransport#GetTransportSettings` | `PlayMode` |
   | volume | `GroupRenderingControl#GetGroupVolume` | `CurrentVolume` |

4. **Check light and dark mode** for visual changes; the app follows the system.
5. **Install on the iPhone** with `make device` and tell the owner what to try.

## What only the iPhone can test

- The volume buttons. Stream `make logs` while the owner presses, and log the Sonos
  volume at the same time to compare press by press.
- The first sign-in on a fresh installation.

## Audible tests

Playback tests replace the queue and play in the owner's home. Leave the volume as
the owner set it, and tell him what you played.
