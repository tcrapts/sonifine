import Foundation
import Testing
@testable import Sonifine

/// Sonos answers decode into groups, a status and a queue without a speaker.
struct SonosDecodingTests {
    private let player = URL(string: "http://192.168.1.147:1400")!

    @Test func groupsNameTheCoordinatorAndCountTheOtherRooms() {
        // Kitchen leads Living Room; Bedroom is a stereo pair (one invisible
        // player); a Boost leads nothing visible and is no room.
        let state = """
        <ZoneGroupState><ZoneGroups>\
        <ZoneGroup Coordinator="RINCON_K" ID="RINCON_K:1">\
        <ZoneGroupMember UUID="RINCON_K" Location="http://10.0.0.2:1400/xml/device_description.xml" ZoneName="Kitchen"/>\
        <ZoneGroupMember UUID="RINCON_L" Location="http://10.0.0.3:1400/xml/device_description.xml" ZoneName="Living Room">\
        <Satellite UUID="RINCON_SUB" ZoneName="Living Room" Invisible="1"/></ZoneGroupMember>\
        </ZoneGroup>\
        <ZoneGroup Coordinator="RINCON_B1" ID="RINCON_B1:2">\
        <ZoneGroupMember UUID="RINCON_B1" Location="http://10.0.0.4:1400/xml/device_description.xml" ZoneName="Bedroom"/>\
        <ZoneGroupMember UUID="RINCON_B2" Location="http://10.0.0.5:1400/xml/device_description.xml" ZoneName="Bedroom" Invisible="1"/>\
        </ZoneGroup>\
        <ZoneGroup Coordinator="RINCON_BOOST" ID="RINCON_BOOST:3">\
        <ZoneGroupMember UUID="RINCON_BOOST" Location="http://10.0.0.6:1400/xml/device_description.xml" ZoneName="BOOST" Invisible="1"/>\
        </ZoneGroup></ZoneGroups></ZoneGroupState>
        """
        let groups = SonosGroup.groups(fromZoneGroupState: state)

        #expect(groups.map(\.name) == ["Bedroom", "Kitchen + 1"])
        #expect(groups[1].coordinator == URL(string: "http://10.0.0.2:1400"))
        #expect(groups[1].roomIDs == ["RINCON_K", "RINCON_L"])
    }

    @Test func spotifySongStatusShowsTheSongAndItsAccount() {
        let metadata = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="-1" parentID="-1"><dc:title>Don't Panic &amp; Breathe</dc:title><dc:creator>Coldplay</dc:creator>\
        <upnp:album>Parachutes</upnp:album><upnp:albumArtURI>/getaa?s=1&amp;u=x</upnp:albumArtURI></item></DIDL-Lite>
        """
        let status = GroupStatus(
            volume: xml(soapAnswer("GetGroupVolume", "<CurrentVolume>14</CurrentVolume>")),
            transport: xml(soapAnswer("GetTransportInfo", "<CurrentTransportState>TRANSITIONING</CurrentTransportState>")),
            position: xml(soapAnswer("GetPositionInfo", """
                <Track>3</Track><TrackDuration>0:02:17</TrackDuration>\
                <TrackMetaData>\(xmlEscaped(metadata))</TrackMetaData>\
                <TrackURI>x-sonos-spotify:spotify%3atrack%3a2QhURnm7mQDxBb5jWkbDug?sid=9&amp;flags=8224&amp;sn=1</TrackURI>\
                <RelTime>0:01:03</RelTime>
                """)),
            settings: xml(soapAnswer("GetTransportSettings", "<PlayMode>SHUFFLE</PlayMode>")),
            player: player)

        #expect(status.title == "Don't Panic & Breathe")
        #expect(status.artist == "Coldplay")
        #expect(status.album == "Parachutes")
        #expect(status.artworkURL?.absoluteString == "http://192.168.1.147:1400/getaa?s=1&u=x")
        #expect(status.spotifyTrack == SpotifyURI("spotify:track:2QhURnm7mQDxBb5jWkbDug"))
        #expect(status.spotifyAccount == SpotifyAccount(serviceID: "9", accountNumber: "1"))
        #expect(status.isPlaying, "Sonos reports TRANSITIONING right after Play")
        #expect(status.volume == 14 && status.queuePosition == 3)
        #expect(status.position == 63 && status.duration == 137)
        #expect(status.playMode == PlayMode(shuffle: true, repeatMode: .all))
    }

    @Test func radioShowsTheSongFromTheStreamAndTheStationBelowIt() {
        let metadata = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" \
        xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="-1" parentID="-1">\
        <dc:title>Radio 2</dc:title><r:streamContent>Coldplay - Yellow</r:streamContent></item></DIDL-Lite>
        """
        let status = GroupStatus(
            volume: xml(soapAnswer("GetGroupVolume", "<CurrentVolume>5</CurrentVolume>")),
            transport: xml(soapAnswer("GetTransportInfo", "<CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState>")),
            position: xml(soapAnswer("GetPositionInfo", """
                <TrackDuration>NOT_IMPLEMENTED</TrackDuration><TrackMetaData>\(xmlEscaped(metadata))</TrackMetaData>\
                <TrackURI>x-sonosapi-stream:s9483?sid=254</TrackURI>
                """)),
            settings: nil, player: player)

        #expect(status.title == "Coldplay - Yellow")
        #expect(status.artist == "Radio 2")
        #expect(status.duration == 0 && !status.isPlaying && status.spotifyTrack == nil)
    }

    @Test(arguments: ["NORMAL", "REPEAT_ALL", "REPEAT_ONE", "SHUFFLE_NOREPEAT", "SHUFFLE", "SHUFFLE_REPEAT_ONE"])
    func everyPlayModeSurvivesTheRoundTrip(value: String) {
        #expect(PlayMode(sonos: value).sonosValue == value)
    }

    @Test func timesConvertBothWays() {
        #expect(SonosTime.string(225) == "0:03:45")
        #expect(SonosTime.seconds("1:00:05") == 3605)
        #expect(SonosTime.seconds("NOT_IMPLEMENTED") == 0)
    }

    @Test func queueEntriesKnowTheirSpotifySong() {
        let didl = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="Q:0/1"><res>x-sonos-spotify:spotify%3atrack%3aAAA?sid=9&amp;sn=1</res><dc:title>One</dc:title></item>\
        <item id="Q:0/2"><res>x-file-cifs://nas/two.mp3</res><dc:title>Two</dc:title></item></DIDL-Lite>
        """
        let entries = QueueEntry.entries(fromDIDL: didl, player: player)

        #expect(entries.map(\.title) == ["One", "Two"])
        #expect(entries.map(\.id) == [0, 1])
        #expect(entries[0].spotifyTrack?.id == "AAA" && entries[1].spotifyTrack == nil)
    }
}
