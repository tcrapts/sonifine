# ADR 0007: Favourites with two sources, Sonos Radio stations and custom streams

## Context

Sonos Radio's home started with a hard-coded "Dutch radio" row: thirteen
Sonos Radio IDs (`tunein:4345` and so on), looked up by name at every launch
for their logos. the owner wanted to manage that row himself: which stations, in
which order, and stations that Sonos Radio doesn't carry.

On 2 November 2026 BNR through Sonos Radio took 11 to 16 seconds to start,
sometimes longer than the app waited. A TuneIn station first asks TuneIn's ad
network AdsWizz for a preroll; the owner's DNS filter (AdGuard) answers
`tunein.adswizz.com` and `delivery-cdn-cf.adswizz.com` with `0.0.0.0`, so the
speaker reports `ZPSTR_CONNECTING` and `ZPSTR_BUFFERING` in `r:streamContent`
until the ad request gives up.

The station's own stream skips TuneIn. `SetAVTransportURI` with
`x-rincon-mp3radio://https://stream.bnr.nl/bnr_mp3_128_20` and this item, then
`Play`, played BNR on the Symfonisk after 4.8 seconds:

```xml
<item id="R:0/0/0" parentID="R:0/0" restricted="true">
  <dc:title>BNR Nieuwsradio</dc:title>
  <upnp:class>object.item.audioItem.audioBroadcast</upnp:class>
  <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON65031_</desc>
</item>
```

The speaker then reports the stream's file name (`BNR_NIEUWSRADIO.mp3?dist=other`)
as the title and no artwork, and gives the item back unchanged in
`GetMediaInfo` `CurrentURIMetaData`.

## Decision

- A **favourite** has a name, an optional logo and one of two sources: a Sonos
  Radio station by its ID, or a **custom stream** by its address. `Favourites`
  keeps them in the user's order as JSON in `UserDefaults` under
  `radioFavourites`; the first launch fills in thirteen Dutch stations as
  custom streams, with the logos Sonos Radio's search gives them.
- A Sonos Radio favourite plays as a Sonos Radio station does, see
  [ADR 0005](0005-play-sonos-radio-as-the-transport-uri.md).
- A custom stream plays as the transport URI `x-rincon-mp3radio://<address>`
  with the item above, without an account number. The item also carries the
  logo as `upnp:albumArtURI`, so the status has a cover when the speaker gives none.
- Before a custom stream is kept, the app asks its https address for the first
  bytes and accepts an audio content type; a web page, a playlist or an error
  gets a message. iOS lets the app ask https addresses only, so an http address
  is kept unchecked.
- Starting a Sonos Radio station, the app waits 15 seconds, and up to 30 while
  the speaker reports connecting or buffering, before it tries another account
  number. The mini-player shows "Connecting…" or "Buffering…" meanwhile.

## Consequences

- The Dutch stations start in seconds, without ads, whatever the DNS filter blocks.
- The home no longer searches Sonos Radio for thirteen logos at every launch.
- A custom stream address is the station's own and can change; the user edits it.
  Sonos Radio follows such changes for its stations.
- A custom stream gives no song information unless the station sends it in its
  stream; Now Playing then shows the favourite's name and logo.
