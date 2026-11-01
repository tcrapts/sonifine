import CryptoKit
import Foundation
import OSLog
import Security

/// The library sign-in: the Spotify Web API through the owner's app on
/// developer.spotify.com, signed in with PKCE (no client secret). It reads the
/// library, search, artists and podcasts, and changes Liked Songs.
@MainActor
final class SpotifyWebAPI {
    static let callbackScheme = "finevolume"
    static let redirectURI = "finevolume://spotify-callback"
    private static let clientID = "YOUR_SPOTIFY_CLIENT_ID"
    private static let scopes = [
        "playlist-read-private", "playlist-read-collaborative", "user-library-read",
        "user-read-recently-played", "user-library-modify", "user-read-playback-position",
    ]
    private static let refreshTokenKey = "spotifyRefreshToken"

    /// Thrown when the sign-in lacks the permission for a request, such as liking a song.
    struct MissingPermission: Error {}

    private let transport: HTTPTransport
    private let secrets: SecretStore
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    /// The permissions of the sign-in, as the last token named them.
    private var grantedScopes: Set<String>?
    /// The refresh in progress. Requests that need a token meanwhile wait for it.
    private var refresh: Task<String, Error>?

    /// After a 429 ("too many requests") the app sends nothing until then: a minute
    /// at first, twice as long each time Spotify refuses again, up to half an hour.
    private let log = Logger(subsystem: "com.example.sonifine", category: "Spotify")
    private var pausedUntil = Date.distantPast
    private var pause: TimeInterval = 60
    /// Whether the last refusal was the developer quota rather than a short rate limit.
    private var isOverQuota = false

    /// Called when Spotify no longer accepts the sign-in.
    var onSignedOut: () -> Void = {}

    private let defaults: UserDefaults?

    /// `defaults` keeps a pause across launches, so a restart doesn't spend the quota again.
    init(transport: @escaping HTTPTransport = HTTP.live, secrets: SecretStore, defaults: UserDefaults? = nil) {
        self.transport = transport
        self.secrets = secrets
        self.defaults = defaults
        if let until = defaults?.object(forKey: "spotifyPausedUntil") as? Date, until > .now {
            pausedUntil = until
            isOverQuota = defaults?.bool(forKey: "spotifyOverQuota") ?? false
        }
    }

    /// The reason Spotify refuses requests now, if it does; nil when the app may ask.
    var refusal: String? {
        Date.now < pausedUntil ? Self.slowDown(until: pausedUntil, quota: isOverQuota).message : nil
    }

    var isSignedIn: Bool { secrets.read(Self.refreshTokenKey) != nil }

    /// False when the sign-in predates the permission to read where the user
    /// stopped in an episode; true when it has it or no token has said yet.
    var canReadPlaybackPosition: Bool { grantedScopes?.contains("user-read-playback-position") ?? true }

    // MARK: Sign-in

    /// Signs in through Spotify's page. `authenticate` shows it and returns the callback URL.
    func signIn(authenticate: (URL) async throws -> URL) async throws {
        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        var authorize = URLComponents(string: "https://accounts.spotify.com/authorize")!
        authorize.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
        ]
        let callback = try await authenticate(authorize.url!)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AppError("Spotify did not return a sign-in code.")
        }
        _ = try await requestToken([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "code_verifier": verifier,
        ])
    }

    func signOut() {
        secrets.delete(Self.refreshTokenKey)
        accessToken = nil
        accessTokenExpiry = .distantPast
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, Date.now < accessTokenExpiry { return accessToken }
        if let refresh { return try await refresh.value }
        guard let refreshToken = secrets.read(Self.refreshTokenKey) else {
            throw AppError("Sign in to Spotify first.")
        }
        let task = Task { try await requestToken(["grant_type": "refresh_token", "refresh_token": refreshToken]) }
        refresh = task
        defer { refresh = nil }
        return try await task.value
    }

    /// Asks the token endpoint for an access token and keeps the new refresh token.
    private func requestToken(_ parameters: [String: String]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = parameters.merging(["client_id": Self.clientID]) { $1 }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)

        let (data, status) = try await transport(request)
        if parameters["grant_type"] == "refresh_token", status == 400 || status == 401 {
            // Revoked or expired: only a new sign-in helps.
            signOut()
            onSignedOut()
            throw AppError("Sign in to Spotify again.")
        }
        guard status == 200, let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw AppError("Spotify sign-in failed (\(status)).")
        }
        accessToken = token.access_token
        accessTokenExpiry = Date.now.addingTimeInterval(TimeInterval(token.expires_in - 60))
        grantedScopes = token.scope.map { Set($0.split(separator: " ").map(String.init)) }
        if let refreshToken = token.refresh_token, !secrets.save(refreshToken, for: Self.refreshTokenKey) {
            throw AppError("Couldn't keep the Spotify sign-in on this iPhone.")
        }
        return token.access_token
    }

    // MARK: Library

    struct Library: Codable {
        var playlists: [SpotifyItem] = []
        var likedSongs: [SpotifyItem] = []
        var albums: [SpotifyItem] = []
        /// The podcasts the user follows, most recently followed first.
        var shows: [SpotifyItem] = []
        /// Songs played recently, newest first, each once.
        var recentlyPlayed: [SpotifyItem] = []
        /// The playlists and albums those songs were played from, newest first.
        var jumpBackIn: [SpotifyItem] = []
    }

    func library() async throws -> Library {
        async let playlistPage: Page<Playlist> = get("/me/playlists?limit=50")
        async let liked = likedSongs()
        async let albumPage: Page<SavedAlbum> = get("/me/albums?limit=50")
        async let recentPage: Page<PlayHistory> = get("/me/player/recently-played?limit=50")
        async let savedShows: [SavedShow?] = all("/me/shows?limit=50")

        var library = Library()
        library.playlists = try await playlistPage.items.compactMap { $0?.item }
        library.likedSongs = try await liked
        library.albums = try await albumPage.items.compactMap { $0?.album.item }
        // The library loads without its podcasts when Spotify refuses them.
        library.shows = ((try? await savedShows) ?? []).compactMap { $0?.show.item }
        let history = try await recentPage.items.compactMap { $0 }
        var seen = Set<SpotifyURI>()
        library.recentlyPlayed = history.compactMap(\.track.item).filter { seen.insert($0.uri).inserted }
        library.jumpBackIn = await contexts(of: history, known: library.playlists + library.albums)
        return library
    }

    /// Only what the Sonos link doesn't give: the podcasts and what played recently.
    /// `known` are the playlists and albums the link already loaded.
    func extras(known: [SpotifyItem]) async throws -> (shows: [SpotifyItem], recentlyPlayed: [SpotifyItem], jumpBackIn: [SpotifyItem]) {
        async let savedShows: [SavedShow?] = all("/me/shows?limit=50")
        async let recentPage: Page<PlayHistory> = get("/me/player/recently-played?limit=50")
        let shows = try await savedShows.compactMap { $0?.show.item }
        let history = try await recentPage.items.compactMap { $0 }
        var seen = Set<SpotifyURI>()
        let recent = history.compactMap(\.track.item).filter { seen.insert($0.uri).inserted }
        return (shows, recent, await contexts(of: history, known: known))
    }

    /// Every liked song, newest first.
    func likedSongs() async throws -> [SpotifyItem] {
        let saved: [SavedTrack?] = try await all("/me/tracks?limit=50")
        return saved.compactMap { $0?.song }
    }

    /// The playlists and albums behind the recently played songs. Spotify's own
    /// mixes are left out; the Web API doesn't share them with this app.
    private func contexts(of history: [PlayHistory], known: [SpotifyItem]) async -> [SpotifyItem] {
        var seen = Set<String>()
        let uris = history.compactMap { $0.context.flatMap { SpotifyURI($0.uri) } }
            .filter { seen.insert($0.description).inserted }
            .prefix(8)
        let knownByURI = Dictionary(known.map { ($0.uri, $0) }) { first, _ in first }

        var found: [SpotifyItem] = []
        // Each one the library doesn't hold costs a request, and Spotify limits how
        // many an app may send: look up at most four.
        var lookups = 4
        for uri in uris {
            if let item = knownByURI[uri] {
                found.append(item)
                continue
            }
            guard lookups > 0, uri.kind == .playlist || uri.kind == .album else { continue }
            lookups -= 1
            if uri.kind == .playlist, let playlist: Playlist = try? await get("/playlists/\(uri.id)") {
                found.append(contentsOf: [playlist.item].compactMap { $0 })
            } else if uri.kind == .album, let album: Album = try? await get("/albums/\(uri.id)") {
                found.append(contentsOf: [album.item].compactMap { $0 })
            }
        }
        return found
    }

    // MARK: Search and contents

    func search(_ query: String) async throws -> SpotifySearchResults {
        let result: SearchResponse = try await get(
            "/search?q=\(Self.encode(query))&type=track,artist,album,playlist,show,episode&limit=10")
        return SpotifySearchResults(
            tracks: result.tracks?.items.compactMap { $0?.item } ?? [],
            artists: result.artists?.items.compactMap { $0?.item } ?? [],
            albums: result.albums?.items.compactMap { $0?.item } ?? [],
            playlists: result.playlists?.items.compactMap { $0?.item } ?? [],
            shows: result.shows?.items.compactMap { $0?.item } ?? [],
            episodes: result.episodes?.items.compactMap { $0?.item } ?? [])
    }

    /// The episodes of a podcast, newest first: the latest hundred.
    func episodes(of show: SpotifyItem) async throws -> [SpotifyItem] {
        let episodes: [Episode?] = try await all("/shows/\(show.uri.id)/episodes?limit=50", limit: 100)
        return episodes.compactMap { $0?.item(showImage: show.imageURL) }
    }

    /// The podcast an episode belongs to.
    func show(of episode: SpotifyURI) async throws -> SpotifyItem? {
        let details: Episode = try await get("/episodes/\(episode.id)")
        return details.show?.item
    }

    /// The songs of a playlist or album, or an artist's best known songs.
    func songs(of item: SpotifyItem) async throws -> [SpotifyItem] {
        switch item.kind {
        case .playlist:
            // Newer Spotify responses call the entries `items`, older ones `tracks`.
            let entries: [PlaylistEntry?]
            do {
                entries = try await all("/playlists/\(item.uri.id)/items?limit=100")
            } catch {
                entries = try await all("/playlists/\(item.uri.id)/tracks?limit=100")
            }
            return entries.compactMap { $0?.song }
        case .album:
            let page: Page<Track> = try await get("/albums/\(item.uri.id)/tracks?limit=50")
            return page.items.compactMap { $0?.item(albumImage: item.imageURL) }
        case .artist:
            let result: SearchResponse = try await get(
                "/search?q=\(Self.encode("artist:\"\(item.name)\""))&type=track&limit=10")
            return result.tracks?.items.compactMap { $0?.item } ?? []
        case .track:
            return [item]
        case .show, .episode, .other:
            return []
        }
    }

    /// An artist's albums and singles, newest first.
    func albums(ofArtist artist: SpotifyItem) async throws -> [SpotifyItem] {
        let page: Page<Album> = try await get("/artists/\(artist.uri.id)/albums?include_groups=album,single&limit=10")
        return page.items.compactMap { $0?.item }
    }

    /// The album and the first artist of a song.
    func albumAndArtist(of track: SpotifyURI) async throws -> (album: SpotifyItem?, artist: SpotifyItem?) {
        let details: Track = try await get("/tracks/\(track.id)")
        var artist = details.artists.first?.item
        if let id = artist?.uri.id, let full: Artist = try? await get("/artists/\(id)") { artist = full.item }
        return (details.album?.item, artist)
    }

    // MARK: Liked Songs

    func isLiked(_ track: SpotifyURI) async throws -> Bool {
        let result: [Bool] = try await get("/me/library/contains?uris=\(Self.encode(track.description))")
        return result.first ?? false
    }

    func setLiked(_ liked: Bool, _ track: SpotifyURI) async throws {
        // Since February 2026, apps in development mode save through /me/library; /me/tracks answers 403.
        _ = try await send(liked ? "PUT" : "DELETE", "/me/library?uris=\(Self.encode(track.description))")
    }

    // MARK: Requests

    /// Every entry of a list that Spotify splits into pages, up to `limit` entries.
    private func all<T: Decodable>(_ path: String, limit: Int = 2000) async throws -> [T?] {
        var page: Page<T> = try await get(path)
        var items = page.items
        while let next = page.nextPath, items.count < limit {
            page = try await get(next)
            items += page.items
        }
        return items
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await send("GET", path))
    }

    private func send(_ method: String, _ path: String) async throws -> Data {
        // Every request during a pause would make Spotify's limit last longer.
        guard Date.now >= pausedUntil else { throw Self.slowDown(until: pausedUntil, quota: isOverQuota) }
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, status) = try await transport(request)
        if !(200..<300).contains(status) {
            log.error("\(method) \(path.prefix(60)): \(status) \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        if status == 429 {
            // QUOTA_EXCEEDED is the budget of the developer account, which lasts much longer
            // than a short rate limit; Spotify doesn't say how long, so wait an hour.
            let quota = String(decoding: data, as: UTF8.self).contains("QUOTA_EXCEEDED")
            pausedUntil = Date.now.addingTimeInterval(quota ? 60 * 60 : pause)
            pause = min(pause * 2, 30 * 60)
            isOverQuota = quota
            defaults?.set(pausedUntil, forKey: "spotifyPausedUntil")
            defaults?.set(quota, forKey: "spotifyOverQuota")
            throw Self.slowDown(until: pausedUntil, quota: quota)
        }
        pause = 60
        if status == 403 { throw MissingPermission() }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
            throw AppError("Spotify: \(message ?? "request failed (\(status))")")
        }
        return data
    }

    private static func slowDown(until date: Date, quota: Bool) -> AppError {
        let minutes = max(1, Int((date.timeIntervalSinceNow / 60).rounded(.up)))
        return AppError(quota
            ? "Spotify's quota for this app is used up. Sonifine tries again in \(minutes) min."
            : "Spotify asks Sonifine to slow down. It tries again in \(minutes) min.")
    }

    private static func encode(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }
}

// MARK: Responses

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
    /// The permissions, separated by spaces.
    let scope: String?
}

private struct APIError: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}

/// Spotify sometimes returns `null` entries in lists, hence the optionals.
private struct Page<T: Decodable>: Decodable {
    let items: [T?]
    let next: String?

    /// The next page as a path for `get`.
    var nextPath: String? {
        next.map { $0.replacingOccurrences(of: "https://api.spotify.com/v1", with: "") }
    }
}

private struct SpotifyImage: Decodable { let url: String }

private extension Array where Element == SpotifyImage {
    var firstURL: URL? { first.flatMap { URL(string: $0.url) } }
}

private struct Playlist: Decodable {
    struct Owner: Decodable { let display_name: String? }
    struct Count: Decodable { let total: Int }
    let uri: String, name: String
    let images: [SpotifyImage]?
    let owner: Owner?
    /// Spotify reports the size as `tracks` or, in newer responses, `items`.
    let tracks: Count?
    let items: Count?

    var item: SpotifyItem? {
        guard let uri = SpotifyURI(uri) else { return nil }
        let count = (tracks ?? items).map { " · \($0.total) songs" } ?? ""
        return SpotifyItem(uri: uri, name: name, subtitle: (owner?.display_name ?? "Playlist") + count,
                           imageURL: images?.firstURL)
    }
}

private struct Artist: Decodable {
    let uri: String?, name: String
    let images: [SpotifyImage]?

    var item: SpotifyItem? {
        guard let uri = uri.flatMap({ SpotifyURI($0) }) else { return nil }
        return SpotifyItem(uri: uri, name: name, subtitle: "Artist", imageURL: images?.firstURL)
    }
}

private struct Album: Decodable {
    let uri: String, name: String
    let images: [SpotifyImage]?
    let artists: [Artist]?

    var item: SpotifyItem? {
        guard let uri = SpotifyURI(uri) else { return nil }
        return SpotifyItem(uri: uri, name: name,
                           subtitle: "Album · " + (artists?.map(\.name).joined(separator: ", ") ?? ""),
                           imageURL: images?.firstURL)
    }
}

private struct Track: Decodable {
    let uri: String, name: String
    let artists: [Artist]
    let album: Album?

    var item: SpotifyItem? { item(albumImage: nil) }

    /// Album tracks come without their album; `albumImage` fills in the cover.
    func item(albumImage: URL?) -> SpotifyItem? {
        guard let uri = SpotifyURI(uri), uri.kind == .track else { return nil }
        var item = SpotifyItem(uri: uri, name: name, subtitle: artists.map(\.name).joined(separator: ", "),
                               imageURL: album?.images?.firstURL ?? albumImage)
        item.album = album?.name
        return item
    }
}

private struct SavedTrack: Decodable {
    let track: Track
    let added_at: String?

    var song: SpotifyItem? { track.item?.added(added_at) }
}
private extension SpotifyItem {
    /// The item with the moment Spotify gives as `added_at`, such as `2026-10-30T08:00:00Z`.
    func added(_ timestamp: String?) -> SpotifyItem {
        var item = self
        item.addedAt = timestamp.flatMap { try? Date($0, strategy: .iso8601) }
        return item
    }
}

private struct SavedAlbum: Decodable { let album: Album }

private struct Show: Decodable {
    let uri: String, name: String
    let images: [SpotifyImage]?
    /// Spotify no longer gives the publisher to apps in development mode.
    let publisher: String?

    var item: SpotifyItem? {
        guard let uri = SpotifyURI(uri), uri.kind == .show else { return nil }
        let by = publisher.flatMap { $0.isEmpty ? nil : " · " + $0 } ?? ""
        return SpotifyItem(uri: uri, name: name, subtitle: "Podcast" + by, imageURL: images?.firstURL)
    }
}

private struct SavedShow: Decodable { let show: Show }

/// A podcast episode. Its show comes along in search results and on its own page,
/// not in the list of a show's episodes.
private struct Episode: Decodable {
    struct ResumePoint: Decodable {
        let fully_played: Bool
        let resume_position_ms: Int
    }

    let uri: String, name: String
    let images: [SpotifyImage]?
    let duration_ms: Int
    /// `2026-10-30`, or only the year or month, as `release_date_precision` says.
    let release_date: String?
    /// Only with the permission `user-read-playback-position`.
    let resume_point: ResumePoint?
    let show: Show?

    var item: SpotifyItem? { item(showImage: nil) }

    func item(showImage: URL?) -> SpotifyItem? {
        guard let uri = SpotifyURI(uri), uri.kind == .episode else { return nil }
        let details = SpotifyItem.Episode(
            released: release_date.flatMap { try? Date($0 + "T12:00:00Z", strategy: .iso8601) },
            duration: TimeInterval(duration_ms) / 1000,
            resumePosition: resume_point.map { TimeInterval($0.resume_position_ms) / 1000 },
            fullyPlayed: resume_point?.fully_played ?? false)
        var item = SpotifyItem(uri: uri, name: name, subtitle: details.summary(show: show?.name),
                               imageURL: images?.firstURL ?? show?.images?.firstURL ?? showImage)
        item.episode = details
        return item
    }
}

extension SpotifyItem.Episode {
    /// The line below an episode's title, such as `Podcast · 30 Oct 2026 · 45 min left`.
    func summary(show: String? = nil) -> String {
        let length = fullyPlayed ? "Played"
            : progress != nil ? Self.minutes(duration - (resumePosition ?? 0)) + " left"
            : Self.minutes(duration)
        return [show, released?.formatted(date: .abbreviated, time: .omitted), length]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// `45 min` or `1 hr 5 min`.
    private static func minutes(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(60, seconds)).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

private struct PlayHistory: Decodable {
    struct Context: Decodable { let uri: String }
    let track: Track
    let context: Context?
}

/// A playlist entry, with the day it was added. Podcast episodes and missing songs come out as nil.
private struct PlaylistEntry: Decodable {
    let song: SpotifyItem?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entry = (try? container.decodeIfPresent(Track.self, forKey: .track))
            ?? (try? container.decodeIfPresent(Track.self, forKey: .item))
        let addedAt = (try? container.decodeIfPresent(String.self, forKey: .added_at)) ?? nil
        song = entry?.item?.added(addedAt)
    }

    private enum CodingKeys: String, CodingKey { case track, item, added_at }
}

private struct SearchResponse: Decodable {
    let tracks: Page<Track>?
    let artists: Page<Artist>?
    let albums: Page<Album>?
    let playlists: Page<Playlist>?
    let shows: Page<Show>?
    let episodes: Page<Episode>?
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
