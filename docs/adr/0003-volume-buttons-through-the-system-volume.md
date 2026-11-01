# ADR 0003: Read the volume buttons through the system volume

## Context

The reason for the app: the iPhone volume buttons should change the Sonos volume
in smaller steps than Sonos apps use. iOS has no API for the hardware buttons.

## Decision

The app keeps an ambient audio session active and observes
`AVAudioSession.outputVolume`. A change of one step of 1/16 is a press; the
direction is the direction of the change. Each press changes the group volume by
the step size. A hidden `MPVolumeView` keeps the iOS volume overlay away and lets
the app move the iPhone volume to the middle once when it nears either end.

## Consequences

- The buttons work while the app is open.
- The app shows its own volume overlay with the Sonos volume.
- Earlier versions reset the iPhone volume to 50% after every press. iOS moved
  it back to 10%, and the app and iOS fought in a loop. Moving it once, only near
  an end, and ignoring jumps larger than one step ended that.
