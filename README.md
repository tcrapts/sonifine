# Sonifine

Sonifine is een iOS-app om Sonos te bedienen vanaf de iPhone, naar het voorbeeld
van Sonify. Het verschil: de volumeknoppen van de iPhone veranderen het Sonos-volume
in kleine stappen, standaard 1 op een schaal van 100. De stapgrootte stel je in
onder **System → ⚙️**.

## Wat de app doet

- **Home** toont je Spotify-startpagina: Jump back in, Daily Mix, Release Radar,
  Your top mixes, radiozenders en meer. De ▶ op een hoes speelt meteen af.
- **Library** toont je playlists, al je Liked Songs en albums. Met ↑↓ rechtsboven
  sorteer je Liked Songs en playlists op titel, artiest, album of **Recently added**;
  kies dezelfde nog eens voor de andere richting. Play en Shuffle volgen die volgorde.
- **Search** zoekt in heel Spotify naar nummers, artiesten, albums en playlists.
- Swipe naar rechts op een nummer, album of playlist voor **Play Next**, naar links
  voor **Add to Queue**. Op een hoes: lang indrukken.
- **System** toont elke kamer met wat er speelt, play/pause en volume.
- De schuifknop op een kamer (of **System → ⚙️ → Rooms**) toont het geluid van
  die kamer: bass, treble, loudness, Trueplay en **Reset to default**. Daaronder
  staan de speakers met model, ID, serienummer, versies en IP-adres.
- **Now Playing** heeft voortgang, shuffle, herhalen, de wachtrij, een hartje voor
  Liked Songs en "Go to album/artist".
- De volumeknoppen werken als de app open is, en ook op het vergrendelscherm en in
  andere apps zolang de Sonos speelt of tot tien minuten na een pauze. Een balk
  bovenin de app toont het nieuwe volume.
- Het vergrendelscherm en het bedieningspaneel tonen wat de Sonos speelt, met
  play/pause, volgende, vorige en spoelen.

## Projectindeling

- `App/`: de Swift-code en de assets. Xcode neemt elk bestand in deze map
  automatisch op.
- `Info.plist`: de rechten voor het lokale netwerk, Bonjour en de Spotify-login.
- `Sonifine.xcodeproj/`: het Xcode-project.
- `scripts/`: hulpscripts, zoals het tekenen van het icoon.
- `docs/`: architectuur, ontwikkeling, testen en beslissingen (`docs/adr/`).

## Benodigde software

- Xcode 27 met de iOS 26 SDK.
- Een Apple-account in Xcode (Settings → Accounts) om op een iPhone te installeren.
- `uv` voor de scripts in `scripts/`.

## Snel starten

```bash
make build    # bouwt voor de simulator
make device   # bouwt en installeert op de iPhone
make help     # toont alle targets
```

## Op je iPhone zetten

Na een wijziging zet je de app zo op je iPhone:

1. Ontgrendel je iPhone en zorg dat hij op dezelfde wifi zit als de Mac (of aan de kabel).
2. Draai `make device`. Je logins blijven bewaard.

De eerste keer op een nieuwe Mac of iPhone zijn er een paar stappen meer: je
Apple-account in Xcode, de iPhone één keer koppelen via de kabel met
Developer Mode aan, en de ontwikkelaar vertrouwen op de iPhone. Die staan, met
oplossingen voor de bekende foutmeldingen, in
[docs/development.md](docs/development.md#install-on-the-iphone).

Met een gratis Apple-account start de app na zeven dagen niet meer; draai dan
opnieuw `make device`.
