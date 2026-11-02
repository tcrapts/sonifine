import Foundation
import Testing
@testable import Sonifine

// Answers recorded from Sonos Radio (sali.sonos.superhi.fi) on 1 November 2026, shortened.

private let recordedHome = """
{"id": {"objectId": "Sonos Radio"}, "content": {"container": {"name": "Sonos Radio", "type": "container"}}, "total": 27, \
"views": [{"displayType": "swimlane", "id": {"objectId": "/stations/en-US/NL/c2Q6Tkw6dHJlbmRpbmctbm93"}, \
"content": {"container": {"name": "Trending Now", "type": "container"}}, "items": [\
{"id": {"objectId": "sonos:2997"}, "displayType": "swimlane-genre", "content": {"container": {"name": "Hit List", \
"type": "trackList.program", "id": {"serviceId": "a78b8e1eb3318dd09f0bb529deed153d-NL-DZR", "objectId": "sonos:2997"}, \
"service": {"id": "a78b8e1eb3318dd09f0bb529deed153d-NL-DZR", "name": "Hit List"}, "artist": {"name": "Today’s Hottest Hits"}, \
"imageUrl": "https://sonosradio.imgix.net/station-images/9fbaf609-52d5-439d-8faf-1e5fccf7be2a.png?w=200&auto=format,compress", \
"summary": "Today’s Hottest Hits"}}, "browsePolicies": {"canPlay": true, "canEnumerate": false}}, \
{"id": {"objectId": "sonos:153184"}, "displayType": "swimlane-genre", "content": {"container": {"name": "Nashville Now", \
"type": "trackList.program", "id": {"serviceId": "d0d8cf7aff8437c87a9347614f7f91ff-NL-DZR", "objectId": "sonos:153184"}, \
"service": {"id": "d0d8cf7aff8437c87a9347614f7f91ff-NL-DZR", "name": "Nashville Now"}, "artist": {"name": "Now & Next in Country"}, \
"imageUrl": "https://sonosradio.imgix.net/station-images/34015396-a2e6-4330-9c53-6361b9472167.png?w=200&auto=format,compress", \
"summary": "Now & Next in Country"}}, "browsePolicies": {"canPlay": true, "canEnumerate": false}}], "total": 10, \
"browsePolicies": {"canAddToFavorites": false, "isFavorite": false, "isEphemeral": false}}, \
{"displayType": "list", "id": {"objectId": "/others/en-US/NL"}, "content": {"container": {"name": "Browse Radio", "type": "container"}}, \
"items": [{"id": {"objectId": "/genres/en-US/NL"}, "displayType": "list", "content": {"container": {"name": "Music", \
"type": "container", "id": {"objectId": "/genres/en-US/NL"}, "service": {"name": "Music"}, \
"imageUrl": "https://sonosradio.imgix.net/icons/Music_active_80_04.png?auto=format,compress", "summary": ""}}, \
"browsePolicies": {"canPlay": false, "canEnumerate": true}}, {"id": {"objectId": "/stations/en-US/NL/EgdOTDpHOjIy"}, \
"displayType": "list", "content": {"container": {"name": "News & Talk", "type": "container", \
"id": {"objectId": "/stations/en-US/NL/EgdOTDpHOjIy"}, "service": {"name": "News & Talk"}, \
"imageUrl": "https://sonosradio.imgix.net/icons/NewsTalk_active_80_04.png?auto=format,compress", "summary": ""}}, \
"browsePolicies": {"canPlay": false, "canEnumerate": true}}], "total": 4, \
"browsePolicies": {"canAddToFavorites": false, "isFavorite": false, "isEphemeral": false}}]}
"""

/// `search` for stations: a Sonos Radio program and a live station, from two recorded answers.
private let recordedSearch = """
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"  \
xmlns:tns="http://www.sonos.com/Services/1.1"><soap:Body><searchResponse xmlns="http://www.sonos.com/Services/1.1">\
<searchResult><index>0</index><count>2</count><total>55690</total>\
<mediaMetadata><title>Hit List</title><itemType>program</itemType><id>sonos:2997</id><streamMetadata>\
<logo>https://sali.sonos.superhi.fi/image?w=60&amp;image=https%3A%2F%2Fsonosradio.imgix.net%2Fstation-images%2F9fbaf609-52d5-439d-8faf-1e5fccf7be2a.png%3Fw%3D200%26auto%3Dformat%2Ccompress&amp;partnerId=sonos</logo>\
</streamMetadata><artist>Today’s Hottest Hits</artist><summary>Today’s Hottest Hits</summary></mediaMetadata>\
<mediaMetadata><title>NPO Radio 2</title><itemType>stream</itemType><id>tunein:5668</id><streamMetadata>\
<logo>https://sali.sonos.superhi.fi/image?w=60&amp;image=https%3A%2F%2Fcdn-radiotime-logos.tunein.com%2Fs9483g.png&amp;partnerId=tunein</logo>\
<callsign>NPO RAD2</callsign><channel>92.6 FM</channel></streamMetadata><artist>Er is maar één NPO Radio 2</artist>\
<summary>Er is maar één NPO Radio 2</summary></mediaMetadata></searchResult></searchResponse></soap:Body></soap:Envelope>
"""

private let recordedGenres = """
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"  \
xmlns:tns="http://www.sonos.com/Services/1.1"><soap:Body><getMetadataResponse xmlns="http://www.sonos.com/Services/1.1">\
<getMetadataResult><index>0</index><count>2</count><total>17</total><mediaCollection><itemType>container</itemType>\
<displayType>list-genre</displayType><id>/stations/en-US/NL/EgdOTDpHOjE0</id><title>Alternative</title><artist></artist>\
<summary></summary><canPlay>false</canPlay><canEnumerate>true</canEnumerate>\
<albumArtURI>https://sonosradio.imgix.net/icons/Alternative_active_80_04.png?auto=format,compress</albumArtURI></mediaCollection>\
<mediaCollection><itemType>container</itemType><displayType>list-genre</displayType><id>/stations/en-US/NL/EgdOTDpHOjE1</id>\
<title>Classical</title><artist></artist><summary></summary><canPlay>false</canPlay><canEnumerate>true</canEnumerate>\
<albumArtURI>https://sonosradio.imgix.net/icons/Classical_active_80_04.png?auto=format,compress</albumArtURI></mediaCollection>\
</getMetadataResult></getMetadataResponse></soap:Body></soap:Envelope>
"""

/// What `getMetadata` of `root` answers without a sign-in: nothing, with an undeclared `xsi` prefix.
private let recordedEmptyRoot = """
<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"  \
xmlns:tns="http://www.sonos.com/Services/1.1"><soap:Body><getMetadataResponse xmlns="http://www.sonos.com/Services/1.1" \
xsi:nil="true"></getMetadataResponse></soap:Body></soap:Envelope>
"""

private func station(_ id: String, _ name: String) -> RadioItem {
    RadioItem(id: id, itemType: nil, name: name, imageURL: nil)!
}

private func category(_ id: String, _ name: String) -> RadioItem {
    RadioItem(id: id, itemType: "container", name: name, imageURL: nil)!
}

/// Browsing and searching Sonos Radio, against its recorded answers.
@MainActor
struct SonosRadioServiceTests {
    private let recorded = RecordedTransport()

    @Test func theHomeHasRowsOfStationsAndTheCategoriesToBrowse() async throws {
        recorded.answer((200, recordedHome)) { $0.url?.path() == "/browse/v1" }
        let shelves = try await SonosRadioService(transport: recorded.transport).home()

        #expect(shelves.map(\.title) == ["Trending Now", "Browse Radio"])
        let hitList = try #require(shelves.first?.items.first)
        #expect(hitList.id == "sonos:2997" && hitList.kind == .program)
        #expect(hitList.subtitle == "Today’s Hottest Hits")
        #expect(hitList.imageURL?.host() == "sonosradio.imgix.net")
        #expect(shelves[1].items.map(\.name) == ["Music", "News & Talk"])
        #expect(shelves[1].items.allSatisfy { $0.kind == .category })
    }

    @Test func searchFindsProgramsAndLiveStationsWithTheirFullSizeLogos() async throws {
        recorded.answer(soapAction: "search", (200, recordedSearch))
        let found = try await SonosRadioService(transport: recorded.transport).search("R&B")

        #expect(found.map(\.id) == ["sonos:2997", "tunein:5668"])
        #expect(found.map(\.kind) == [.program, .stream])
        #expect(found[1].subtitle == "Er is maar één NPO Radio 2")
        #expect(found[1].imageURL?.absoluteString == "https://cdn-radiotime-logos.tunein.com/s9483g.png")
        let body = try #require(recorded.requests.first?.bodyText)
        #expect(body.contains("<id>stations</id><term>R&amp;B</term>"))
        #expect(!body.contains("credentials"), "Sonos Radio answers without a sign-in")
    }

    @Test func aCategoryListsWhatIsInIt() async throws {
        recorded.answer(soapAction: "getMetadata", (200, recordedGenres))
        let music = category("/genres/en-US/NL", "Music")
        let genres = try await SonosRadioService(transport: recorded.transport).items(in: music)

        #expect(genres.map(\.name) == ["Alternative", "Classical"])
        #expect(genres.map(\.kind) == [.category, .category])
        #expect(recorded.requests.first?.bodyText.contains("<id>/genres/en-US/NL</id>") == true)
    }

    @Test func anEmptyAnswerGivesNoStations() async throws {
        recorded.answer(soapAction: "getMetadata", (200, recordedEmptyRoot))
        let items = try await SonosRadioService(transport: recorded.transport).items(in: category("root", "Root"))

        #expect(items.isEmpty)
    }
}

/// A station plays as the Sonos app stores it in a Sonos favourite, with the
/// household's own account number (see docs/adr/0005).
struct RadioStreamTests {
    private let account = RadioAccount(accountNumber: "7")

    @Test func aSonosRadioProgramPlaysAsARadioURI() throws {
        let stream = try #require(station("sonos:154250", "Smooth Jazz").stream(account: account))
        let item = try #require(XMLNode.parse(stream.metadata)?.first("item"))

        #expect(stream.uri == "x-sonosapi-radio:154250?sid=303&flags=0&sn=7")
        #expect(item.attributes["id"] == "000c0000154250")
        #expect(item.value("title") == "Smooth Jazz")
        #expect(item.value("class") == "object.item.audioItem.audioBroadcast")
        #expect(item.value("desc") == "SA_RINCON77575_X_#Svc77575-0-Token")
    }

    @Test func aLiveStationPlaysAsAStreamURI() throws {
        let stream = try #require(station("tunein:4381", "NDR 90,3").stream(account: account))

        #expect(stream.uri == "x-sonosapi-stream:tunein%3a4381?sid=303&flags=8232&sn=7")
        #expect(XMLNode.parse(stream.metadata)?.first("item")?.attributes["id"] == "10092028tunein%3a4381")
    }

    @Test func aNameWithAnAmpersandKeepsTheMetadataValid() throws {
        let stream = try #require(station("sonos:163110", "R&B Now").stream(account: account))
        #expect(XMLNode.parse(stream.metadata)?.value("title") == "R&B Now")
    }

    @Test func aCategoryDoesNotPlay() {
        #expect(category("/genres/en-US/NL", "Music").stream(account: account) == nil)
    }

    @Test func theAccountComesOnlyFromASonosRadioURI() {
        #expect(RadioAccount(sonosURI: "x-sonosapi-stream:tunein%3a9767?sid=303&flags=8224&sn=20") == RadioAccount(accountNumber: "20"))
        #expect(RadioAccount(sonosURI: "x-sonosapi-stream:s25681?sid=254&flags=8224&sn=0") == nil)
        #expect(RadioAccount(sonosURI: "x-rincon-queue:RINCON_000E58A0B1C201400#0") == nil)
    }
}

/// Playing a station, against the fake player.
@MainActor
struct RadioPlaybackTests {
    private let speaker = URL(string: "http://10.0.0.2:1400")!
    private let fake = FakeSonosPlayer()

    private func controller() async -> SonosController {
        fake.groups = [SonosGroup(id: "RINCON_K", name: "Kitchen", coordinator: speaker, roomIDs: ["RINCON_K"])]
        let controller = SonosController(makePlayer: { _ in fake },
                                         defaults: UserDefaults(suiteName: "RadioPlaybackTests-\(UUID())")!)
        controller.found([speaker])
        await controller.loadGroups()
        return controller
    }

    @Test func aStationPlaysWithTheAccountSonosUsedBeforeAndLeavesTheQueue() async {
        let controller = await controller()
        // the owner once played a Sonos Radio station in the Sonos app.
        fake.status.radioAccount = RadioAccount(accountNumber: "7")
        fake.status.isPlaying = true
        await controller.refresh()

        await controller.play(.station(station("sonos:154250", "Smooth Jazz")))

        #expect(fake.streams.map(\.uri) == ["x-sonosapi-radio:154250?sid=303&flags=0&sn=7"])
        #expect(fake.queuedItems.isEmpty)
        #expect(controller.errorMessage == nil)
    }

    @Test func anAccountIsLearnedOnlyFromAStationThatPlays() async {
        let controller = await controller()
        controller.streamStartChecks = 2
        // A station that hangs while starting, as with a wrong number.
        fake.status.radioAccount = RadioAccount(accountNumber: "3")
        (fake.status.isPlaying, fake.status.isStarting) = (true, true)
        await controller.refresh()
        fake.playsStream = { $0.uri.hasSuffix("sn=2") }

        await controller.play(.station(station("tunein:4345", "BNR Nieuwsradio")))

        #expect(fake.streams.first?.uri.hasSuffix("sn=2") == true, "the hanging number 3 wasn't learned")
    }

    @Test func aRememberedNumberThatHangsGivesWayToOneThatPlays() async {
        let controller = await controller()
        controller.streamStartChecks = 2
        // SLAM played with number 3, so the app learned 3; BNR only plays with 2.
        fake.status.radioAccount = RadioAccount(accountNumber: "3")
        fake.status.isPlaying = true
        await controller.refresh()
        fake.playsStream = { $0.uri.hasSuffix("sn=2") }

        await controller.play(.station(station("tunein:4345", "BNR Nieuwsradio")))
        await controller.play(.station(station("tunein:4345", "BNR Nieuwsradio")))

        #expect(fake.streams.map { $0.uri.components(separatedBy: "sn=").last } == ["3", "2", "2"])
    }

    @Test func anUnknownAccountIsFoundByTryingAndThenRemembered() async {
        let controller = await controller()
        controller.streamStartChecks = 2
        fake.playsStream = { $0.uri.hasSuffix("sn=4") }

        await controller.play(.station(station("sonos:154250", "Smooth Jazz")))
        #expect(fake.streams.map(\.uri).map { $0.components(separatedBy: "sn=").last } == ["2", "3", "4"])
        #expect(controller.errorMessage == nil)

        await controller.play(.station(station("sonos:2997", "Hit List")))
        #expect(fake.streams.last?.uri == "x-sonosapi-radio:2997?sid=303&flags=0&sn=4", "straight away the second time")
        #expect(fake.streams.count == 4)
    }

    @Test func radioTakesNoCoversFromTheQueue() async {
        let controller = await controller()
        fake.queueEntries = (0..<4).map {
            QueueEntry(id: $0, title: "\($0)", artist: "", artworkURL: URL(string: "http://10.0.0.2:1400/getaa?\($0)"),
                       spotifyTrack: nil)
        }
        fake.status.queuePosition = 2
        fake.status.station = "Smooth Jazz"
        await controller.refresh()

        #expect(await controller.upcomingArtwork().isEmpty)
        #expect(await controller.neighbourArtwork() == (nil, nil))
    }
}

/// The status of a group that plays radio.
struct RadioStatusTests {
    private let player = URL(string: "http://192.168.1.147:1400")!

    private func status(media: String, trackMetadata: String = "") -> GroupStatus {
        GroupStatus(
            volume: xml(soapAnswer("GetGroupVolume", "<CurrentVolume>12</CurrentVolume>")),
            transport: xml(soapAnswer("GetTransportInfo", "<CurrentTransportState>PLAYING</CurrentTransportState>")),
            position: xml(soapAnswer("GetPositionInfo", """
                <Track>1</Track><TrackDuration>0:03:20</TrackDuration>\
                <TrackMetaData>\(xmlEscaped(trackMetadata))</TrackMetaData><RelTime>0:00:40</RelTime>
                """)),
            settings: nil, media: xml(media), player: player)
    }

    @Test func aStationShowsTheSongWithTheStationAndTeachesTheAccount() throws {
        // GetMediaInfo holds the URI and metadata the app set; the song is in GetPositionInfo.
        let stream = try #require(station("sonos:154250", "Smooth Jazz").stream(account: RadioAccount(accountNumber: "7")))
        let song = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="-1" parentID="-1"><dc:title>Take Five</dc:title><dc:creator>Dave Brubeck</dc:creator></item></DIDL-Lite>
        """
        let status = status(media: soapAnswer("GetMediaInfo", """
            <NrTracks>1</NrTracks><CurrentURI>\(xmlEscaped(stream.uri))</CurrentURI>\
            <CurrentURIMetaData>\(xmlEscaped(stream.metadata))</CurrentURIMetaData>
            """), trackMetadata: song)

        #expect(status.station == "Smooth Jazz" && status.playsRadio)
        #expect(status.displayTitle == "Take Five")
        #expect(status.details == ["Dave Brubeck", "Smooth Jazz"])
        #expect(status.radioAccount == RadioAccount(accountNumber: "7"))
    }

    @Test func aLiveStreamShowsTheStationNotItsFileName() throws {
        let stream = try #require(station("tunein:4345", "BNR Nieuwsradio").stream(account: RadioAccount(accountNumber: "2")))
        // As the Symfonisk reported BNR: the title is the end of the stream's address.
        let track = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"         xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="-1" parentID="-1" restricted="true">        <res protocolInfo="aac:*:application/octet-stream:*">aac://https://27823.live.streamtheworld.com:443/        BNR_NIEUWSRADIOAAC.aac?dist=tunein&amp;DIST=TuneIn&amp;TGT=TuneIn</res><r:streamContent></r:streamContent>        <dc:title>BNR_NIEUWSRADIOAAC.aac?dist=tunein&amp;DIST=TuneIn&amp;TGT=TuneIn</dc:title></item></DIDL-Lite>
        """
        let status = status(media: soapAnswer("GetMediaInfo", """
            <NrTracks>1</NrTracks><CurrentURI>\(xmlEscaped(stream.uri))</CurrentURI>\
            <CurrentURIMetaData>\(xmlEscaped(stream.metadata))</CurrentURIMetaData>
            """), trackMetadata: track)

        #expect(status.displayTitle == "BNR Nieuwsradio")
    }

    @Test func anAdBeforeTheStationShowsTheStation() throws {
        let stream = try #require(station("tunein:17258", "SLAM!").stream(account: RadioAccount(accountNumber: "2")))
        // As the Symfonisk reported the TuneIn ad before SLAM! started.
        let track = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="-1" parentID="-1"><dc:title>bump_sonic_pre_pre.mp3?aw_0_1st.playerid=SonosRadio&amp;aw_0_1st.skey=1793602824\
        </dc:title></item></DIDL-Lite>
        """
        let status = status(media: soapAnswer("GetMediaInfo", """
            <NrTracks>1</NrTracks><CurrentURI>\(xmlEscaped(stream.uri))</CurrentURI>\
            <CurrentURIMetaData>\(xmlEscaped(stream.metadata))</CurrentURIMetaData>
            """), trackMetadata: track)

        #expect(status.displayTitle == "SLAM!")
    }

    @Test func theQueueIsNoRadio() {
        // Recorded from the Symfonisk while it played Spotify.
        let status = status(media: """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
            <s:Body><u:GetMediaInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><NrTracks>50</NrTracks>\
            <MediaDuration>NOT_IMPLEMENTED</MediaDuration><CurrentURI>x-rincon-queue:RINCON_000E58A0B1C201400#0</CurrentURI>\
            <CurrentURIMetaData></CurrentURIMetaData><NextURI></NextURI><NextURIMetaData></NextURIMetaData>\
            <PlayMedium>NETWORK</PlayMedium><RecordMedium>NOT_IMPLEMENTED</RecordMedium><WriteStatus>NOT_IMPLEMENTED</WriteStatus>\
            </u:GetMediaInfoResponse></s:Body></s:Envelope>
            """)

        #expect(!status.playsRadio && status.radioAccount == nil)
        #expect(status.duration == 200)
    }
}

/// The SOAP adapter plays a stream as the transport URI.
@MainActor
struct StreamSOAPTests {
    @Test func aStreamBecomesTheTransportURIAndPlays() async throws {
        let recorded = RecordedTransport()
        recorded.answer(soapAction: "SetAVTransportURI", (200, soapAnswer("SetAVTransportURI", "")))
        recorded.answer(soapAction: "Play", (200, soapAnswer("Play", "")))
        let player = SOAPSonosPlayer(address: URL(string: "http://10.0.0.2:1400")!, transport: recorded.transport)
        let stream = try #require(station("sonos:154250", "Smooth Jazz").stream(account: RadioAccount(accountNumber: "7")))

        try await player.playStream(stream)

        #expect(recorded.requests.map(\.soapAction) == ["SetAVTransportURI", "Play"])
        let body = recorded.requests[0].bodyText
        #expect(body.contains("<CurrentURI>x-sonosapi-radio:154250?sid=303&amp;flags=0&amp;sn=7</CurrentURI>"))
        #expect(body.contains("<CurrentURIMetaData>&lt;DIDL-Lite"))
        #expect(!recorded.requests.contains { $0.soapAction == "RemoveAllTracksFromQueue" })
    }
}
