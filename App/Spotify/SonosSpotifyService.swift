import Foundation
import OSLog

/// Spotify as the Sonos system offers it, through the **link**: the Spotify home
/// with Daily Mix, Release Radar and stations, and the songs of any playlist or
/// album, Spotify's own included. See ADR 0002.
///
/// The app links once, the way Sonos apps do (AppLink): `startLink` gives a Sonos
/// sign-in page, and `finishLink` gets a token and private key once the user has
/// signed in. An expired key comes back renewed in the fault of the next call.
@MainActor
final class SonosSpotifyService {
    private static let service = URL(string: "https://spotify-v5.ws.sonos.com/smapi")!
    private static let browse = URL(string: "https://spotify-v5.ws.sonos.com/v1/browse")!
    private enum Keys {
        static let token = "sonosSpotifyToken"
        static let key = "sonosSpotifyKey"
        static let device = "sonosSpotifyDevice"
    }

    /// The service holds a renewed key in its fault; `callRaw` has stored it.
    private struct KeyExpired: Error {}
    /// The user hasn't finished signing in yet.
    private struct NotLinkedYet: Error {}

    private let transport: HTTPTransport
    private let secrets: SecretStore

    init(transport: @escaping HTTPTransport = HTTP.live, secrets: SecretStore) {
        self.transport = transport
        self.secrets = secrets
    }

    var isLinked: Bool { secrets.read(Keys.token) != nil }

    // MARK: Linking

    /// The sign-in page and the code that `finishLink` waits for.
    func startLink(household: Household) async throws -> (page: URL, code: String) {
        let response = try await call("getAppLink", "<householdId>\(household.id)</householdId>",
                                      household: household, signedIn: false)
        guard let page = response.value("regUrl").flatMap(URL.init(string:)),
              let code = response.value("linkCode") else {
            throw AppError("Sonos did not return a sign-in page.")
        }
        return (page, code)
    }

    /// True once the user has signed in and the key is stored; false while
    /// Sonos still waits for the sign-in.
    func finishLink(code: String, household: Household) async throws -> Bool {
        do {
            let response = try await call("getDeviceAuthToken", """
                <householdId>\(household.id)</householdId><linkCode>\(code)</linkCode>\
                <linkDeviceId>\(household.deviceID)</linkDeviceId>
                """, household: household, signedIn: false)
            guard store(response) else { throw AppError("Sonos did not return a key.") }
            secrets.save(household.deviceID, for: Keys.device)
            return true
        } catch is NotLinkedYet {
            return false
        }
    }

    func unlink() {
        secrets.delete(Keys.token)
        secrets.delete(Keys.key)
        secrets.delete(Keys.device)
    }

    /// Keeps a token and key from `getDeviceAuthToken` or a renewal fault.
    private func store(_ response: XMLNode) -> Bool {
        guard let token = response.value("authToken"), let key = response.value("privateKey"),
              secrets.save(token, for: Keys.token), secrets.save(key, for: Keys.key) else { return false }
        return true
    }

    // MARK: Contents

    /// The rows of the Spotify home, without "Your Library".
    func home(household: Household) async throws -> [HomeShelf] {
        let page: SMAPIBrowsePage = try await withFreshKey(household: household) { token in
            var request = URLRequest(url: Self.browse, timeoutInterval: 10)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let reply = try await transport(request)
            if reply.status == 401 { throw KeyExpired() }
            guard reply.status == 200 else { throw AppError("The Spotify home didn't load (\(reply.status)).") }
            return try JSONDecoder().decode(SMAPIBrowsePage.self, from: reply.data)
        }
        return page.views.filter { $0.id.objectId != "yourmusic_root" }.compactMap { view in
            let items = view.items?.compactMap(\.spotifyItem) ?? []
            guard !items.isEmpty else { return nil }
            return HomeShelf(id: view.id.objectId, title: Self.shelfTitle(view.content.details?.name ?? ""),
                             items: items)
        }
    }

    /// Spotify greets in the time of its own clock, which runs hours off the iPhone's.
    /// The screen title greets in local time, so the greeting row is named after its contents.
    private static func shelfTitle(_ name: String) -> String {
        let greetings = ["good morning", "good afternoon", "good evening", "good night",
                         "goedemorgen", "goedemiddag", "goedenavond", "goedenacht"]
        return greetings.contains(name.lowercased()) ? "Jump back in" : name
    }

    /// The songs of a playlist or album, every page.
    func songs(of uri: SpotifyURI, household: Household) async throws -> [SpotifyItem] {
        try await items(in: uri.description, household: household).filter(\.isTrack)
    }

    // MARK: Library

    /// The user's library through the link: playlists, Liked Songs (newest first) and
    /// saved albums. The link counts against Sonos, not the Web API's small quota.
    func library(household: Household) async throws -> (playlists: [SpotifyItem], likedSongs: [SpotifyItem], albums: [SpotifyItem]) {
        async let playlists = items(in: "playlists", household: household)
        async let liked = items(in: "your_songs", household: household)
        async let albums = items(in: "your_albums", household: household)
        // The link gives no dates; Liked Songs come newest first, so their order stands in.
        let now = Date.now
        let likedSongs = try await liked.enumerated().map { index, song in
            var song = song
            song.addedAt = now.addingTimeInterval(-Double(index))
            return song
        }
        return try await (playlists, likedSongs, albums)
    }

    /// Songs, albums, artists and playlists that match `term`, ten of each.
    func search(_ term: String, household: Household) async throws -> SpotifySearchResults {
        async let tracks = find(term, in: "track", household: household)
        async let artists = find(term, in: "artist", household: household)
        async let albums = find(term, in: "album", household: household)
        async let playlists = find(term, in: "playlist", household: household)
        return try await SpotifySearchResults(tracks: tracks, artists: artists, albums: albums, playlists: playlists)
    }

    private func find(_ term: String, in category: String, household: Household) async throws -> [SpotifyItem] {
        let response = try await withFreshKey(household: household) { _ in
            try await self.call("search", "<id>\(category)</id><term>\(term.xmlEscaped)</term><index>0</index><count>10</count>",
                                household: household, signedIn: true)
        }
        return Self.items(in: response)
    }

    /// Everything in one of the link's lists, page by page, up to `limit`.
    func items(in id: String, household: Household, limit: Int = 2000) async throws -> [SpotifyItem] {
        var found: [SpotifyItem] = []
        var index = 0
        while index < limit {
            let response = try await withFreshKey(household: household) { _ in
                try await self.call("getMetadata", "<id>\(id.xmlEscaped)</id><index>\(index)</index><count>100</count>",
                                    household: household, signedIn: true)
            }
            let page = Self.items(in: response)
            let entries = response.descendants(named: "mediaCollection").count + response.descendants(named: "mediaMetadata").count
            found += page
            index += entries
            let total = response.value("total").flatMap(Int.init) ?? 0
            if entries == 0 || index >= total { break }
        }
        return found
    }

    /// The playlists, albums, artists and songs in a getMetadata or search answer.
    private static func items(in response: XMLNode) -> [SpotifyItem] {
        let entries = response.descendants(named: "mediaCollection") + response.descendants(named: "mediaMetadata")
        return entries.compactMap { entry -> SpotifyItem? in
            guard let uri = entry.value("id").flatMap({ SpotifyURI($0) }), uri.kind != .other,
                  let title = entry.value("title") else { return nil }
            let artist = entry.value("artist") ?? ""
            var item = SpotifyItem(uri: uri, name: title,
                                   subtitle: uri.kind == .album ? "Album · \(artist)" : uri.kind == .artist ? "Artist" : artist,
                                   imageURL: entry.value("albumArtURI").flatMap(URL.init(string:)))
            item.album = entry.value("album")
            return item
        }
    }

    // MARK: Keys

    /// Runs `request` with the current token. When the key expired, it runs again
    /// with the renewed key. Only a link Sonos no longer accepts is removed.
    private func withFreshKey<T>(household: Household, _ request: (String) async throws -> T) async throws -> T {
        guard let used = secrets.read(Keys.token) else { throw AppError("Connect Spotify first.") }
        do {
            return try await request(used)
        } catch is KeyExpired {
            if secrets.read(Keys.token) == used {
                // The browse endpoint says 401 without a new key; a small SOAP call fetches one.
                do {
                    _ = try await call("getMetadata", "<id>root</id><index>0</index><count>1</count>",
                                       household: household, signedIn: true)
                } catch is KeyExpired {}
            }
            guard let fresh = secrets.read(Keys.token), fresh != used else {
                throw AppError("Spotify on Sonos didn't accept the key. Try again in a moment.")
            }
            return try await request(fresh)
        }
    }

    // MARK: SOAP

    private func call(_ action: String, _ body: String, household: Household, signedIn: Bool) async throws -> XMLNode {
        // The link belongs to the player it was made with.
        let deviceID = secrets.read(Keys.device) ?? household.deviceID
        var login = ""
        if signedIn {
            guard let token = secrets.read(Keys.token), let key = secrets.read(Keys.key) else {
                throw AppError("Connect Spotify first.")
            }
            login = "<loginToken><token>\(token)</token><key>\(key)</key><householdId>\(household.id)</householdId></loginToken>"
        }
        let request = SMAPI.request(Self.service, action: action, body: body, credentials: """
            <deviceId>\(deviceID)</deviceId><deviceProvider>Sonos</deviceProvider>\(login)
            """)
        let reply = try await transport(request)
        let response = XMLNode.parse(reply.data)
        guard reply.status == 200, let response else {
            let fault = response?.value("faultcode") ?? ""
            if fault.contains("TokenRefreshRequired") || fault.contains("AuthTokenExpired") {
                // The renewed key comes in the fault's details.
                if let response, store(response) { throw KeyExpired() }
            }
            if fault.contains("NOT_LINKED_RETRY") { throw NotLinkedYet() }
            if fault.contains("LoginUnauthorized") || fault.contains("AuthTokenExpired") {
                unlink()
                throw AppError("Connect Spotify again.")
            }
            throw AppError("Spotify on Sonos: \(action) failed (\(fault.isEmpty ? String(reply.status) : fault)).")
        }
        return response
    }
}

// MARK: Responses

private extension SMAPIBrowsePage.Item {
    /// A playlist, album or artist of the Spotify home.
    var spotifyItem: SpotifyItem? {
        guard let uri = SpotifyURI(id.objectId), let details = content.details, let name = details.name else { return nil }
        return SpotifyItem(uri: uri, name: name,
                           subtitle: details.artist?.name ?? details.type?.capitalized ?? "",
                           imageURL: details.imageUrl.flatMap(URL.init(string:)))
    }
}
