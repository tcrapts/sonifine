import Foundation
import Testing
@testable import Sonifine

private let household = Household(id: "Sonos_H", deviceID: "RINCON_K")

private func smapiFault(_ code: String, newToken: String? = nil) -> String {
    let detail = newToken.map {
        "<detail><refreshAuthTokenResult><authToken>\($0)</authToken><privateKey>key-\($0)</privateKey></refreshAuthTokenResult></detail>"
    } ?? ""
    return """
    <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><soap:Fault>\
    <faultcode>soap:\(code)</faultcode><faultstring>\(code)</faultstring>\(detail)</soap:Fault></soap:Body></soap:Envelope>
    """
}

private let twoSongs = """
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>\
<ns2:getMetadataResponse xmlns:ns2="http://www.sonos.com/Services/1.1"><ns2:getMetadataResult>\
<ns2:mediaMetadata><ns2:id>spotify:track:AAA</ns2:id><ns2:title>Another Year Will Pass</ns2:title>\
<ns2:trackMetadata><ns2:artist>néomí</ns2:artist><ns2:albumArtURI>https://i.scdn.co/image/a</ns2:albumArtURI></ns2:trackMetadata>\
</ns2:mediaMetadata><ns2:mediaMetadata><ns2:id>spotify:episode:EEE</ns2:id><ns2:title>A podcast</ns2:title></ns2:mediaMetadata>\
</ns2:getMetadataResult></ns2:getMetadataResponse></s:Body></s:Envelope>
"""

/// The link to Sonos's Spotify service keeps working when its key expires.
@MainActor
struct SonosSpotifyServiceTests {
    private let recorded = RecordedTransport()
    private let secrets = MemorySecrets()

    private func linkedService() -> SonosSpotifyService {
        secrets.values = ["sonosSpotifyToken": "old", "sonosSpotifyKey": "key-old"]
        return SonosSpotifyService(transport: recorded.transport, secrets: secrets)
    }

    @Test func anExpiredKeyIsRenewedFromTheFaultAndTheRequestRepeated() async throws {
        let service = linkedService()
        recorded.answer(soapAction: "getMetadata", (500, smapiFault("Client.TokenRefreshRequired", newToken: "new")))
        recorded.answer(soapAction: "getMetadata", (200, twoSongs))

        let songs = try await service.songs(of: SpotifyURI("spotify:playlist:37i9dQZF1E39TLZoPLbkd3")!, household: household)

        #expect(songs.map(\.name) == ["Another Year Will Pass"], "the podcast is left out")
        #expect(secrets.values["sonosSpotifyToken"] == "new")
        #expect(service.isLinked)
        #expect(recorded.requests.last?.bodyText.contains("<token>new</token>") == true)
    }

    @Test func theHomeRenewsItsKeyThroughASmallCallAfterA401() async throws {
        let service = linkedService()
        recorded.answer((401, "")) { $0.url?.path() == "/v1/browse" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer old" }
        recorded.answer(soapAction: "getMetadata", (500, smapiFault("Client.TokenRefreshRequired", newToken: "new")))
        recorded.answer((200, """
            {"views":[{"id":{"objectId":"spotify:view:shortcuts"},"content":{"container":{"name":"Good morning"}},\
            "items":[{"id":{"objectId":"spotify:playlist:37i9dQZF1E39TLZoPLbkd3"},\
            "content":{"container":{"name":"Daily Mix 3","type":"playlist","artist":{"name":"Spotify"}}}}]},\
            {"id":{"objectId":"yourmusic_root"},"content":{"container":{"name":"Your Library"}},"items":[]}]}
            """)) { $0.value(forHTTPHeaderField: "Authorization") == "Bearer new" }

        let shelves = try await service.home(household: household)

        #expect(shelves.map(\.title) == ["Jump back in"], "Spotify's greeting runs on its own clock")
        #expect(shelves.first?.items.first?.name == "Daily Mix 3")
    }

    @Test func aLinkSonosRejectsIsRemoved() async {
        let service = linkedService()
        recorded.answer(soapAction: "getMetadata", (500, smapiFault("Client.LoginUnauthorized")))

        await #expect(throws: AppError("Connect Spotify again.")) {
            try await service.songs(of: SpotifyURI("spotify:album:A")!, household: household)
        }
        #expect(!service.isLinked)
    }

    @Test func linkingWaitsForTheSignInThenKeepsTheKey() async throws {
        let service = SonosSpotifyService(transport: recorded.transport, secrets: secrets)
        recorded.answer(soapAction: "getDeviceAuthToken", (500, smapiFault("Client.NOT_LINKED_RETRY")))
        recorded.answer(soapAction: "getDeviceAuthToken", (200, """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><ns2:getDeviceAuthTokenResponse \
            xmlns:ns2="http://www.sonos.com/Services/1.1"><ns2:getDeviceAuthTokenResult><ns2:authToken>T</ns2:authToken>\
            <ns2:privateKey>K</ns2:privateKey></ns2:getDeviceAuthTokenResult></ns2:getDeviceAuthTokenResponse></s:Body></s:Envelope>
            """))

        #expect(try await service.finishLink(code: "ABC", household: household) == false)
        #expect(try await service.finishLink(code: "ABC", household: household) == true)
        #expect(secrets.values["sonosSpotifyToken"] == "T" && secrets.values["sonosSpotifyDevice"] == "RINCON_K")
    }
}

/// The library sign-in refreshes its token once, and lets go when Spotify refuses.
@MainActor
struct SpotifyWebAPITests {
    private let recorded = RecordedTransport()
    private let secrets = MemorySecrets()
    private let token = #"{"access_token":"A","expires_in":3600,"refresh_token":"R2"}"#

    private func api() -> SpotifyWebAPI {
        secrets.values["spotifyRefreshToken"] = "R1"
        return SpotifyWebAPI(transport: recorded.transport, secrets: secrets)
    }

    private func isTokenRequest(_ request: URLRequest) -> Bool { request.url?.path() == "/api/token" }

    @Test func requestsAtTheSameTimeShareOneRefresh() async throws {
        let api = api()
        recorded.answer((200, token), when: isTokenRequest)
        recorded.answer((200, #"{"items":[]}"#)) { $0.url?.path() == "/v1/me/tracks" }
        recorded.answer((200, #"{"tracks":{"items":[]}}"#)) { $0.url?.path() == "/v1/search" }

        async let liked = api.likedSongs()
        async let found = api.search("Coldplay")
        _ = try await (liked, found)

        #expect(recorded.requests.filter(isTokenRequest).count == 1)
        #expect(secrets.values["spotifyRefreshToken"] == "R2", "Spotify rotates the refresh token")
    }

    @Test func aRefusedRefreshSignsOut() async {
        let api = api()
        var signedOut = false
        api.onSignedOut = { signedOut = true }
        recorded.answer((400, #"{"error":"invalid_grant"}"#), when: isTokenRequest)

        await #expect(throws: AppError("Sign in to Spotify again.")) { try await api.likedSongs() }
        #expect(signedOut && !api.isSignedIn)
    }

    @Test func aPlaylistGivesItsSongsWithoutPodcastsOrGaps() async throws {
        let api = api()
        recorded.answer((200, token), when: isTokenRequest)
        recorded.answer((200, """
            {"items":[{"item":{"uri":"spotify:track:A","name":"Yellow","artists":[{"name":"Coldplay"}]}},\
            {"item":{"uri":"spotify:episode:E","name":"A podcast","artists":[]}},null,\
            {"track":{"uri":"spotify:track:B","name":"Shiver","artists":[{"name":"Coldplay"}]}}]}
            """)) { $0.url?.path() == "/v1/playlists/P/items" }
        let playlist = SpotifyItem(uri: SpotifyURI("spotify:playlist:P")!, name: "Mix", subtitle: "", imageURL: nil)

        let songs = try await api.songs(of: playlist)

        #expect(songs.map(\.name) == ["Yellow", "Shiver"])
    }

    @Test func aLongPlaylistComesWholeAndSortsByDateAdded() async throws {
        let api = api()
        recorded.answer((200, token), when: isTokenRequest)
        recorded.answer((200, """
            {"items":[{"added_at":"2024-05-01T10:00:00Z","item":{"uri":"spotify:track:A","name":"Yellow","artists":[]}}],            "next":"https://api.spotify.com/v1/playlists/P/items?offset=100&limit=100"}
            """)) { $0.url?.path() == "/v1/playlists/P/items" && $0.url?.query()?.contains("offset") != true }
        recorded.answer((200, """
            {"items":[{"added_at":"2026-10-30T08:00:00Z","item":{"uri":"spotify:track:B","name":"Shiver","artists":[]}},            {"item":{"uri":"spotify:track:C","name":"Clocks","artists":[]}}],"next":null}
            """)) { $0.url?.query()?.contains("offset=100") == true }
        let playlist = SpotifyItem(uri: SpotifyURI("spotify:playlist:P")!, name: "Mix", subtitle: "", imageURL: nil)

        let songs = try await api.songs(of: playlist)

        #expect(songs.map(\.name) == ["Yellow", "Shiver", "Clocks"])
        let newestFirst = SongOrder.newestFirst
        #expect(newestFirst.apply(to: songs).map(\.name) == ["Shiver", "Yellow", "Clocks"],
                "a song without a date goes last")
        #expect(newestFirst.choosing(.added).apply(to: songs).map(\.name) == ["Yellow", "Shiver", "Clocks"],
                "choosing it again puts the oldest first")
        #expect(newestFirst.choosing(.title).apply(to: songs).map(\.name) == ["Clocks", "Shiver", "Yellow"])
    }
}
