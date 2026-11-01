import Foundation
import Testing
@testable import Sonifine

/// One URI type covers Spotify's URIs, Sonos track URIs and the Sonos queue encoding.
struct SpotifyURITests {
    @Test func parsesKindsAndIDs() {
        #expect(SpotifyURI("spotify:album:6ZG5lRT77aJ3btmArcykra")?.kind == .album)
        #expect(SpotifyURI("spotify:album:6ZG5lRT77aJ3btmArcykra")?.id == "6ZG5lRT77aJ3btmArcykra")
        #expect(SpotifyURI("spotify:station:artist:123")?.kind == .other)
        #expect(SpotifyURI("spotify:user:alice:playlist:abc")?.kind == .other)
        #expect(SpotifyURI("x-sonos-spotify:abc") == nil)
        #expect(SpotifyURI("spotify:track:") == nil)
    }

    @Test func readsTheSongFromASonosTrackURI() {
        let uri = SpotifyURI(sonosTrackURI: "x-sonos-spotify:spotify%3atrack%3a3AJwUDP919kvQ9QcozQPxg?sid=9&flags=0&sn=1")
        #expect(uri?.description == "spotify:track:3AJwUDP919kvQ9QcozQPxg")
        #expect(SpotifyURI(sonosTrackURI: "x-sonosapi-stream:s9483?sid=254") == nil)
    }

    /// The encodings in docs/architecture.md, which Sonos accepted in a live test.
    @Test func encodesForTheSonosQueue() throws {
        let account = SpotifyAccount.default
        let playlist = try #require(SpotifyURI("spotify:playlist:37i9dQZF1E39TLZoPLbkd3")?.queueItem(account: account))
        let album = try #require(SpotifyURI("spotify:album:6ZG5lRT77aJ3btmArcykra")?.queueItem(account: account))
        let track = try #require(SpotifyURI("spotify:track:2QhURnm7mQDxBb5jWkbDug")?.queueItem(account: account))

        #expect(playlist.uri == "x-rincon-cpcontainer:1006206cspotify%3aplaylist%3a37i9dQZF1E39TLZoPLbkd3")
        #expect(album.uri == "x-rincon-cpcontainer:1004206cspotify%3aalbum%3a6ZG5lRT77aJ3btmArcykra")
        #expect(track.uri == "x-sonos-spotify:spotify%3atrack%3a2QhURnm7mQDxBb5jWkbDug?sid=9&flags=8224&sn=1")
        #expect(track.metadata.contains("SA_RINCON2311_X_#Svc2311-0-Token"))
        #expect(XMLNode.parse(playlist.metadata)?.value("class") == "object.container.playlistContainer")
    }

    @Test func leavesWhatSonosCantQueue() {
        #expect(SpotifyURI("spotify:artist:4gzpq5DPGxSnKTe4SA8HAU")?.queueItem(account: .default) == nil)
        #expect(SpotifyURI("spotify:show:abc")?.queueItem(account: .default) == nil)
    }

    @Test func readsTheAccountSonosPlaysWith() {
        let account = SpotifyAccount(sonosTrackURI: "x-sonos-spotify:spotify%3atrack%3aX?sid=12&flags=0&sn=3")
        #expect(account == SpotifyAccount(serviceID: "12", accountNumber: "3"))
        #expect(account?.serviceType == 3079)
    }
}

/// A tap turns into the right request for Sonos.
struct PlayRequestTests {
    private let playlist = SpotifyItem(uri: SpotifyURI("spotify:playlist:P")!, name: "Mix", subtitle: "", imageURL: nil)

    @Test func aSongInAPlaylistPlaysInsideThePlaylist() {
        let songs = [song("A"), song("B")]
        #expect(PlayRequest.tap(songs[1], in: songs, collection: playlist)
            == .collection(playlist.uri, start: songs[1].uri, shuffle: false))
    }

    @Test func aSongInAListPlaysWithTheSongsOfTheList() {
        let list = [song("A"), playlist, song("B"), song("C")]
        #expect(PlayRequest.tap(list[2], in: list)
            == .songs([list[0].uri, list[2].uri, list[3].uri], start: 1, shuffle: false))
    }

    @Test func aLoneSongPlaysAlone() {
        let lone = song("A")
        #expect(PlayRequest.tap(lone) == .songs([lone.uri], start: 0, shuffle: false))
    }

    @Test func aStationIsNothingSonosCanPlay() {
        let station = SpotifyItem(uri: SpotifyURI("spotify:station:artist:1")!, name: "Radio", subtitle: "", imageURL: nil)
        #expect(PlayRequest.tap(station) == nil)
    }
}

/// The rules of ADR 0003 for reading a press of a volume button.
struct VolumePressTests {
    @Test func oneStepIsAPress() {
        #expect(VolumePress.direction(from: 0.5, to: 0.5625) == 1)
        #expect(VolumePress.direction(from: 0.5, to: 0.4375) == -1)
    }

    @Test func jumpsAndTinyChangesAreNoPress() {
        #expect(VolumePress.direction(from: 0.1, to: 0.5) == nil, "the app moving the volume to the middle")
        #expect(VolumePress.direction(from: 0.5, to: 0.1) == nil, "iOS moving the volume back")
        #expect(VolumePress.direction(from: 0.5, to: 0.51) == nil, "a route change")
    }

    @Test func onlyTheEndsNeedTheMiddle() {
        #expect(VolumePress.needsMiddle(0.0625) && VolumePress.needsMiddle(0.9375))
        #expect(!VolumePress.needsMiddle(0.5) && !VolumePress.needsMiddle(0.25))
    }
}
