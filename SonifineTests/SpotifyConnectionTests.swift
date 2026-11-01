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

    @Test func theLibraryComesThroughTheLinkPageByPage() async throws {
        let service = linkedService()
        func page(_ entries: String, total: Int) -> String {
            """
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>\
            <ns0:getMetadataResponse xmlns:ns0="http://www.sonos.com/Services/1.1"><ns0:getMetadataResult>\
            <ns0:index>0</ns0:index><ns0:count>1</ns0:count><ns0:total>\(total)</ns0:total>\(entries)\
            </ns0:getMetadataResult></ns0:getMetadataResponse></s:Body></s:Envelope>
            """
        }
        // As the owner's link answered for `your_songs`, one song per page here.
        let loser = """
            <ns0:mediaMetadata><ns0:id>spotify:track:5Xr20lO3fb2gLtDOKyF0G5</ns0:id><ns0:itemType>track</ns0:itemType>\
            <ns0:title>Loser (Fcukers Remix)</ns0:title><ns0:trackMetadata><ns0:artist>Tame Impala</ns0:artist>\
            <ns0:album>Loser (Fcukers Remix)</ns0:album><ns0:duration>267</ns0:duration>\
            <ns0:albumArtURI>https://i.scdn.co/image/ab67616d0000b273c516efd7fd5ddee1f11cc8ef</ns0:albumArtURI>\
            </ns0:trackMetadata></ns0:mediaMetadata>
            """
        let warrior = loser.replacingOccurrences(of: "5Xr20lO3fb2gLtDOKyF0G5", with: "7vwTsX8UY5QZmPiQUmWkaL")
            .replacingOccurrences(of: "Loser (Fcukers Remix)</ns0:title>", with: "Warrior</ns0:title>")
        recorded.answer((200, page(loser, total: 2))) { $0.bodyText.contains("<index>0</index>") }
        recorded.answer((200, page(warrior, total: 2))) { $0.bodyText.contains("<index>1</index>") }

        let songs = try await service.items(in: "your_songs", household: household)

        #expect(songs.map(\.name) == ["Loser (Fcukers Remix)", "Warrior"])
        #expect(songs.first?.subtitle == "Tame Impala" && songs.first?.album == "Loser (Fcukers Remix)")
        #expect(songs.first?.imageURL?.host() == "i.scdn.co")
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

    @Test func afterTooManyRequestsNothingGoesOutForAWhile() async {
        let api = api()
        recorded.answer((200, token), when: isTokenRequest)
        recorded.answer((429, "")) { $0.url?.path() == "/v1/search" }

        await #expect(throws: AppError.self) { try await api.search("Coldplay") }
        let sent = recorded.requests.count
        await #expect(throws: AppError("Spotify asks Sonifine to slow down. It tries again in 1 min.")) {
            try await api.search("Coldplay")
        }

        #expect(recorded.requests.count == sent, "the pause keeps Spotify's limit from growing")
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
        let newestFirst = ListOrder.newestFirst
        #expect(newestFirst.apply(to: songs).map(\.name) == ["Shiver", "Yellow", "Clocks"],
                "a song without a date goes last")
        #expect(newestFirst.choosing(.added).apply(to: songs).map(\.name) == ["Yellow", "Shiver", "Clocks"],
                "choosing it again puts the oldest first")
        #expect(newestFirst.choosing(.title).apply(to: songs).map(\.name) == ["Clocks", "Shiver", "Yellow"])
    }

    // MARK: Podcasts (shapes from Spotify's Web API reference)

    private let show = SpotifyItem(uri: SpotifyURI("spotify:show:38bS44xjbVVZ3No3ByF1dJ")!, name: "TalkRL",
                                   subtitle: "Podcast", imageURL: URL(string: "https://i.scdn.co/image/show"))

    @Test func aShowGivesItsEpisodesWithWhereTheUserStopped() async throws {
        let api = api()
        recorded.answer((200, token.replacingOccurrences(of: "}", with: #","scope":"user-library-read user-read-playback-position"}"#)),
                        when: isTokenRequest)
        recorded.answer((200, """
            {"items":[{"uri":"spotify:episode:0FuKEjteM0cGzy7pznCkAj","name":"Ian Osband","duration_ms":3600000,            "release_date":"2024-03-11","release_date_precision":"day","images":[],            "resume_point":{"fully_played":false,"resume_position_ms":1200000}},            {"uri":"spotify:episode:B","name":"Older","duration_ms":1686230,"release_date":"2019",            "release_date_precision":"year","images":[{"url":"https://i.scdn.co/image/b"}],            "resume_point":{"fully_played":true,"resume_position_ms":0}},null],"next":null}
            """)) { $0.url?.path() == "/v1/shows/38bS44xjbVVZ3No3ByF1dJ/episodes" }

        let episodes = try await api.episodes(of: show)

        #expect(episodes.map(\.name) == ["Ian Osband", "Older"])
        #expect(episodes[0].episode?.startPosition == 1200)
        #expect(episodes[0].episode?.progress == 1.0 / 3)
        #expect(episodes[0].imageURL == show.imageURL, "an episode without a cover shows the podcast's")
        #expect(episodes[0].subtitle.hasSuffix("40 min left"))
        #expect(episodes[1].episode?.startPosition == 0 && episodes[1].subtitle == "Played")
        #expect(api.canReadPlaybackPosition)
    }

    @Test func anOlderSignInSaysItCantReadWhereEpisodesStopped() async throws {
        let api = api()
        recorded.answer((200, token.replacingOccurrences(of: "}", with: #","scope":"user-library-read"}"#)), when: isTokenRequest)
        recorded.answer((200, #"{"items":[{"uri":"spotify:episode:E","name":"New","duration_ms":60000}]}"#)) {
            $0.url?.path().hasSuffix("/episodes") == true
        }

        let episodes = try await api.episodes(of: show)

        #expect(episodes.first?.episode?.progress == nil)
        #expect(!api.canReadPlaybackPosition)
    }

    @Test func theLibraryHasTheFollowedPodcastsAndLoadsWithoutThem() async throws {
        let api = api()
        recorded.answer((200, token), when: isTokenRequest)
        for path in ["/v1/me/playlists", "/v1/me/tracks", "/v1/me/albums", "/v1/me/player/recently-played"] {
            recorded.answer((200, #"{"items":[]}"#)) { $0.url?.path() == path }
            recorded.answer((200, #"{"items":[]}"#)) { $0.url?.path() == path }
        }
        recorded.answer((200, """
            {"items":[{"added_at":"2026-10-01T08:00:00Z","show":{"uri":"spotify:show:S","name":"TalkRL",            "images":[{"url":"https://i.scdn.co/image/s"}],"total_episodes":12}}],"next":null}
            """)) { $0.url?.path() == "/v1/me/shows" }
        recorded.answer((403, #"{"error":{"message":"Forbidden"}}"#)) { $0.url?.path() == "/v1/me/shows" }

        let library = try await api.library()
        let withoutPodcasts = try await api.library()

        #expect(library.shows.map(\.name) == ["TalkRL"])
        #expect(library.shows.first?.opens == true)
        #expect(withoutPodcasts.shows.isEmpty)
    }

    @Test func searchFindsPodcastsAndEpisodesApartFromSongs() async throws {
        let api = api()
        recorded.answer((200, token), when: isTokenRequest)
        recorded.answer((200, """
            {"tracks":{"items":[{"uri":"spotify:track:A","name":"Yellow","artists":[]}]},            "shows":{"items":[{"uri":"spotify:show:S","name":"TalkRL","publisher":"Robin"}]},            "episodes":{"items":[null,{"uri":"spotify:episode:E","name":"Ian Osband","duration_ms":600000,            "release_date":"2024-03-11"}]}}
            """)) { $0.url?.query()?.contains("type=track,artist,album,playlist,show,episode") == true }

        let results = try await api.search("talkrl")

        #expect(results.tracks.map(\.name) == ["Yellow"])
        #expect(results.shows.map(\.subtitle) == ["Podcast · Robin"])
        #expect(results.episodes.map(\.uri.kind) == [.episode])
    }
}
