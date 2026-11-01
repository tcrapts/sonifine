import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import SwiftUI

/// Something from Spotify: a playlist, album, track or artist.
struct SpotifyItem: Identifiable, Hashable {
    enum Kind: String { case playlist, album, track, artist, other }

    let id: String
    let uri: String
    let name: String
    let subtitle: String
    let imageURL: URL?

    /// From the URI, such as `spotify:album:6ZG5lRT77aJ3btmArcykra`.
    var kind: Kind { Kind(rawValue: uri.split(separator: ":").dropFirst().first.map(String.init) ?? "") ?? .other }
    var isTrack: Bool { kind == .track }
}

/// The search results per kind, in the order the Search screen shows them.
struct SpotifySearchResults {
    var tracks: [SpotifyItem] = []
    var artists: [SpotifyItem] = []
    var albums: [SpotifyItem] = []
    var playlists: [SpotifyItem] = []
}

/// Signs in to Spotify and reads the library and search results.
/// `SonosController.playSpotify` plays them through the Spotify account on the Sonos system.
///
/// It uses the Spotify Web API through the owner's app on developer.spotify.com,
/// whose redirect URI is `finevolume://spotify-callback`. PKCE needs no client secret.
@MainActor
@Observable
final class SpotifyController {
    static let redirectURI = "finevolume://spotify-callback"
    private static let scopes = [
        "playlist-read-private", "playlist-read-collaborative", "user-library-read",
        "user-read-recently-played", "user-library-modify",
    ]

    private let clientID = "YOUR_SPOTIFY_CLIENT_ID"

    private(set) var isSignedIn = false
    private(set) var playlists: [SpotifyItem] = []
    private(set) var likedSongs: [SpotifyItem] = []
    private(set) var albums: [SpotifyItem] = []
    /// Songs played recently, newest first, each once.
    private(set) var recentlyPlayed: [SpotifyItem] = []
    /// The playlists and albums those songs were played from.
    private(set) var jumpBackIn: [SpotifyItem] = []
    private(set) var searchResults = SpotifySearchResults()
    private(set) var errorMessage: String?
    /// False when the sign-in predates the permission to change Liked Songs.
    private(set) var canLike = true

    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast

    init() {
        isSignedIn = Keychain.read("spotifyRefreshToken") != nil
    }

    // MARK: Sign-in (authorization code with PKCE)

    func signIn(using session: WebAuthenticationSession) async {
        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded

        var authorize = URLComponents(string: "https://accounts.spotify.com/authorize")!
        authorize.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
        ]

        do {
            let callback = try await session.authenticate(using: authorize.url!, callbackURLScheme: "finevolume")
            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw SonosError(message: "Spotify did not return a sign-in code.")
            }
            try await requestToken([
                "grant_type": "authorization_code", "code": code,
                "redirect_uri": Self.redirectURI, "code_verifier": verifier,
            ])
            isSignedIn = true
            canLike = true
            errorMessage = nil
            await loadLibrary()
        } catch ASWebAuthenticationSessionError.canceledLogin {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        Keychain.delete("spotifyRefreshToken")
        accessToken = nil
        isSignedIn = false
        playlists = []
        likedSongs = []
        albums = []
        recentlyPlayed = []
        jumpBackIn = []
        searchResults = SpotifySearchResults()
    }

    private func requestToken(_ parameters: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = (parameters.merging(["client_id": clientID]) { a, _ in a })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SonosError(message: "Spotify sign-in failed. Check the Client ID and redirect URI.")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in - 60))
        if let refresh = token.refresh_token { Keychain.save(refresh, for: "spotifyRefreshToken") }
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, Date() < accessTokenExpiry { return accessToken }
        guard let refresh = Keychain.read("spotifyRefreshToken") else {
            isSignedIn = false
            throw SonosError(message: "Sign in to Spotify again.")
        }
        try await requestToken(["grant_type": "refresh_token", "refresh_token": refresh])
        return accessToken!
    }

    // MARK: Library and search

    func loadLibrary() async {
        do {
            async let playlistPage: Page<Playlist> = get("/me/playlists?limit=50")
            async let likedPage: Page<SavedTrack> = get("/me/tracks?limit=50")
            async let albumPage: Page<SavedAlbum> = get("/me/albums?limit=50")
            async let recentPage: Page<PlayHistory> = get("/me/player/recently-played?limit=50")

            playlists = try await playlistPage.items.compactMap { $0?.item }
            likedSongs = try await likedPage.items.compactMap { $0?.track.item }
            albums = try await albumPage.items.compactMap { $0?.album.item }
            let history = try await recentPage.items.compactMap { $0 }
            var seen = Set<String>()
            recentlyPlayed = history.map(\.track.item).filter { seen.insert($0.uri).inserted }
            jumpBackIn = await contexts(of: history)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The playlists and albums behind the recently played songs, newest first.
    /// Spotify's own mixes are left out: Spotify doesn't share those with other apps.
    private func contexts(of history: [PlayHistory]) async -> [SpotifyItem] {
        var seen = Set<String>()
        let uris = history.compactMap(\.context?.uri).filter { seen.insert($0).inserted }.prefix(12)
        let known = Dictionary((playlists + albums).map { ($0.uri, $0) }) { first, _ in first }

        return await withTaskGroup(of: (Int, SpotifyItem?).self) { group in
            for (index, uri) in uris.enumerated() {
                group.addTask { @MainActor in
                    if let item = known[uri] { return (index, item) }
                    let parts = uri.split(separator: ":")
                    guard parts.count == 3 else { return (index, nil) }
                    switch parts[1] {
                    case "playlist":
                        let playlist: Playlist? = try? await self.get("/playlists/\(parts[2])")
                        return (index, playlist?.item)
                    case "album":
                        let album: Album? = try? await self.get("/albums/\(parts[2])")
                        return (index, album?.item)
                    default:
                        return (index, nil)
                    }
                }
            }
            var found: [(Int, SpotifyItem)] = []
            for await case let (index, item?) in group { found.append((index, item)) }
            return found.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { searchResults = SpotifySearchResults(); return }
        do {
            let result: SearchResponse = try await get("/search?q=\(Self.encode(query))&type=track,artist,album,playlist&limit=10")
            searchResults = SpotifySearchResults(
                tracks: result.tracks?.items.compactMap { $0?.item } ?? [],
                artists: result.artists?.items.compactMap { $0?.item } ?? [],
                albums: result.albums?.items.compactMap { $0?.item } ?? [],
                playlists: result.playlists?.items.compactMap { $0?.item } ?? [])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Liked Songs

    /// Whether the song is in Liked Songs, or nil when Spotify can't tell.
    func isLiked(trackID: String) async -> Bool? {
        let result: [Bool]? = try? await get("/me/tracks/contains?ids=\(trackID)")
        return result?.first
    }

    /// Adds the song to Liked Songs or removes it. Returns whether that worked.
    func setLiked(_ liked: Bool, trackID: String) async -> Bool {
        do {
            _ = try await send(liked ? "PUT" : "DELETE", "/me/tracks?ids=\(trackID)")
            likedSongs = []  // Reload on the next visit, so the list matches.
            return true
        } catch let error as SpotifyHTTPError where error.status == 403 {
            canLike = false
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// The album and the first artist of a song, for "Go to album" and "Go to artist".
    func albumAndArtist(ofTrack trackID: String) async -> (album: SpotifyItem?, artist: SpotifyItem?) {
        guard let track: Track = try? await get("/tracks/\(trackID)") else { return (nil, nil) }
        var artist = track.artists.first?.item
        if let id = artist?.id, let full: Artist = try? await get("/artists/\(id)") { artist = full.item }
        return (track.album?.item, artist)
    }

    // MARK: Contents

    /// The songs in a playlist or album, or the best known songs of an artist.
    func tracks(of item: SpotifyItem) async throws -> [SpotifyItem] {
        switch item.kind {
        case .playlist:
            // Newer Spotify responses call the entries `items`, older ones `tracks`.
            let id = item.id
            let page: Page<PlaylistEntry>
            do {
                page = try await get("/playlists/\(id)/items?limit=100")
            } catch {
                page = try await get("/playlists/\(id)/tracks?limit=100")
            }
            return page.items.compactMap { $0?.song?.item }
        case .album:
            let page: Page<Track> = try await get("/albums/\(item.id)/tracks?limit=50")
            return page.items.compactMap { $0?.item(albumImage: item.imageURL) }
        case .artist:
            let result: SearchResponse = try await get(
                "/search?q=\(Self.encode("artist:\"\(item.name)\""))&type=track&limit=10")
            return result.tracks?.items.compactMap { $0?.item } ?? []
        case .track, .other:
            return [item]
        }
    }

    /// The albums of an artist, newest first.
    func albums(of artist: SpotifyItem) async throws -> [SpotifyItem] {
        let page: Page<Album> = try await get("/artists/\(artist.id)/albums?include_groups=album,single&limit=10")
        return page.items.compactMap { $0?.item }
    }

    // MARK: Web API

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send("GET", path)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(_ method: String, _ path: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
            throw SpotifyHTTPError(status: status, message: "Spotify: \(message ?? "request failed (\(status))")")
        }
        return data
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

// MARK: Web API responses

struct SpotifyHTTPError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int
    let refresh_token: String?
}

private struct APIError: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}

/// Spotify sometimes returns `null` entries in lists, hence the optionals.
private struct Page<T: Decodable>: Decodable { let items: [T?] }

private struct SpotifyImage: Decodable { let url: String }

private struct Playlist: Decodable {
    struct Owner: Decodable { let display_name: String? }
    let id: String, uri: String, name: String
    let images: [SpotifyImage]?
    let owner: Owner?
    /// Spotify reports the size as `tracks` or, in newer responses, `items`.
    let tracks: Count?
    let items: Count?
    struct Count: Decodable { let total: Int }

    var item: SpotifyItem {
        let count = (tracks ?? items).map { " · \($0.total) songs" } ?? ""
        return SpotifyItem(id: id, uri: uri, name: name, subtitle: (owner?.display_name ?? "Playlist") + count,
                           imageURL: images?.first.flatMap { URL(string: $0.url) })
    }
}

private struct Artist: Decodable {
    let id: String?, uri: String?, name: String
    let images: [SpotifyImage]?

    var item: SpotifyItem? {
        guard let id, let uri else { return nil }
        return SpotifyItem(id: id, uri: uri, name: name, subtitle: "Artist",
                           imageURL: images?.first.flatMap { URL(string: $0.url) })
    }
}

private struct Album: Decodable {
    let id: String, uri: String, name: String
    let images: [SpotifyImage]?
    let artists: [Artist]?

    var item: SpotifyItem {
        SpotifyItem(id: id, uri: uri, name: name,
                    subtitle: "Album · " + (artists?.map(\.name).joined(separator: ", ") ?? ""),
                    imageURL: images?.first.flatMap { URL(string: $0.url) })
    }
}

private struct Track: Decodable {
    let id: String?, uri: String, name: String
    let artists: [Artist]
    let album: Album?

    var item: SpotifyItem { item(albumImage: nil) }

    /// Album tracks come without their album; `albumImage` fills in the cover.
    func item(albumImage: URL?) -> SpotifyItem {
        SpotifyItem(id: id ?? uri, uri: uri, name: name, subtitle: artists.map(\.name).joined(separator: ", "),
                    imageURL: album?.images?.first.flatMap { URL(string: $0.url) } ?? albumImage)
    }
}

private struct SavedTrack: Decodable { let track: Track }
private struct SavedAlbum: Decodable { let album: Album }
private struct PlayHistory: Decodable {
    struct Context: Decodable { let uri: String }
    let track: Track
    let context: Context?
}

/// A playlist entry; podcast episodes and missing songs decode as `nil`.
private struct PlaylistEntry: Decodable {
    let track: Track?
    let item: Track?
    var song: Track? { (track ?? item).flatMap { $0.uri.hasPrefix("spotify:track:") ? $0 : nil } }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        track = try? container.decodeIfPresent(Track.self, forKey: .track)
        item = try? container.decodeIfPresent(Track.self, forKey: .item)
    }

    private enum CodingKeys: String, CodingKey { case track, item }
}

private struct SearchResponse: Decodable {
    let tracks: Page<Track>?
    let artists: Page<Artist>?
    let albums: Page<Album>?
    let playlists: Page<Playlist>?
}

// MARK: Helpers

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Stores the Spotify keys in the Keychain.
enum Keychain {
    static func save(_ value: String, for key: String) {
        delete(key)
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                    kSecValueData: Data(value.utf8)] as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                                          kSecReturnData: true] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
    }
}
