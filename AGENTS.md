# Agent instructions

Sonifine is the owner's personal iOS app for his Sonos system: the iPhone volume
buttons change the Sonos volume in small, configurable steps, and Spotify plays
on Sonos with as little effort as possible. It is modelled on the App Store app
Sonify. One owner, one iPhone, no App Store release.

Read [README](README.md) for the layout and [CONTEXT](CONTEXT.md) for the
vocabulary before exploring the code.

## Task references

- For building, installing on the iPhone, or reading its logs, follow
  [development](docs/development.md).
- For Sonos control, the Spotify connections, or the volume buttons, read
  [architecture](docs/architecture.md) and the relevant `docs/adr/`.
- For verifying a change, follow [testing](docs/testing.md). Every visible change
  is checked in the simulator, and every Sonos action against the speaker itself.
- For a defect you find and leave, add it to [KNOWN_ISSUES](KNOWN_ISSUES.md).
- For documentation, follow [documentation](docs/README.md#writing).

## House rules

- The speakers are in the owner's home. Tests that play music or change the volume
  are audible there: keep the volume as the owner left it and say what you played.
- The bundle ID `com.example.sonifine` and the URL scheme `finevolume`
  stay as they are. They keep the owner's logins on the installed app and match the
  redirect URI in the Spotify dashboard.
- the owner tests on his iPhone himself. After a change he can see, install it with
  `make device` and tell him what to try.
