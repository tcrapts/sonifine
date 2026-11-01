import Foundation
import Observation
import OSLog

/// Everything the screens show from Spotify, from both connections: the library
/// sign-in (`SpotifyWebAPI`) and the link (`SonosSpotifyService`). The screens
/// ask this catalog; it decides which connection answers.
@MainActor
@Observable
final class SpotifyCatalog {
    // Library sign-in
    private(set) var isSignedIn: Bool
    /// False when the sign-in predates the permission to change Liked Songs.
    private(set) var canLike = true
    /// False when the sign-in predates the permission to read where an episode stopped.
    private(set) var canResume = true
    private(set) var library = SpotifyWebAPI.Library()
    private(set) var searchResults = SpotifySearchResults()

    // Link
    private(set) var isLinked: Bool
    private(set) var homeShelves: [HomeShelf] = []
    /// The Sonos sign-in page while linking.
    private(set) var linkPage: URL?

    private(set) var errorMessage: String?

    private let webAPI: SpotifyWebAPI
    private let sonosService: SonosSpotifyService
    private let household: () async -> Household?

    init(webAPI: SpotifyWebAPI, sonosService: SonosSpotifyService, household: @escaping () async -> Household?) {
        self.webAPI = webAPI
        self.sonosService = sonosService
        self.household = household
        isSignedIn = webAPI.isSignedIn
        isLinked = sonosService.isLinked
        if isSignedIn || isLinked, let saved = Self.savedLibrary() {
            (library, libraryAsked) = saved
        }
        webAPI.onSignedOut = { [weak self] in self?.signedOut() }
    }

    // MARK: Library sign-in

    func signIn(authenticate: (URL) async throws -> URL) async {
        do {
            try await webAPI.signIn(authenticate: authenticate)
            isSignedIn = true
            canLike = true
            errorMessage = nil
            await reload()
        } catch {
            report(error)
        }
    }

    func signOut() {
        webAPI.signOut()
        signedOut()
    }

    private func signedOut() {
        isSignedIn = false
        library = SpotifyWebAPI.Library()
        try? FileManager.default.removeItem(at: Self.libraryFile)
        searchResults = SpotifySearchResults()
    }

    // MARK: Link

    /// Shows the Sonos sign-in page and waits up to ten minutes for the sign-in.
    func link() async {
        errorMessage = nil
        guard let household = await household() else {
            errorMessage = "Looking for your Sonos first…"
            return
        }
        do {
            let (page, code) = try await sonosService.startLink(household: household)
            linkPage = page
            defer { linkPage = nil }
            for _ in 0..<200 {
                try await Task.sleep(for: .seconds(3))
                guard linkPage != nil else { return } // The user closed the page.
                if try await sonosService.finishLink(code: code, household: household) {
                    isLinked = true
                    await loadHome()
                    return
                }
            }
            errorMessage = "Signing in took too long. Try again."
        } catch {
            report(error)
        }
    }

    func cancelLink() { linkPage = nil }

    func unlink() {
        sonosService.unlink()
        isLinked = false
        homeShelves = []
    }

    // MARK: Reading

    /// When the library was last asked for, loaded or not.
    private var libraryAsked = Date.distantPast
    /// The last library Spotify gave, kept on the iPhone, so the app shows it at once
    /// and asks Spotify less: Spotify gives a development app a small quota.
    private static let libraryFile = URL.applicationSupportDirectory.appending(path: "spotify-library.json")

    /// Reloads the library and the Spotify home: always when the user asks
    /// (`force`), else at most every six hours.
    func reload(force: Bool = true) async {
        async let library: Void = loadLibrary(force: force)
        async let home: Void = loadHome()
        _ = await (library, home)
    }

    /// The library comes from the link when there is one: it has no small quota. The
    /// Web API adds what only it has, such as podcasts and recently played, when it can.
    private func loadLibrary(force: Bool) async {
        guard isSignedIn || isLinked, force || Date.now.timeIntervalSince(libraryAsked) > 6 * 60 * 60 else { return }
        let log = Logger(subsystem: "com.example.sonifine", category: "Spotify")
        var loaded = library
        var failure: Error?
        if isLinked {
            // The link needs the Sonos; Home loads again once it is found.
            guard let household = await household() else { return }
            do {
                (loaded.playlists, loaded.likedSongs, loaded.albums) = try await sonosService.library(household: household)
            } catch {
                failure = error
            }
        }
        if isSignedIn {
            do {
                let web = try await webAPI.library()
                loaded.shows = web.shows
                loaded.recentlyPlayed = web.recentlyPlayed
                loaded.jumpBackIn = web.jumpBackIn
                if !isLinked { loaded = web }
            } catch {
                // Without the link the Web API is the only source; with it, the rest still stands.
                if !isLinked || HTTP.isCancellation(error) { failure = failure ?? error }
                else { log.error("web library: \(String(describing: error))") }
            }
        }
        if let failure {
            // A load the view cancelled, such as when Home restarts its task once the
            // Sonos is found, doesn't count: the next one must still go out.
            if !HTTP.isCancellation(failure) { libraryAsked = .now }
            report(failure)
            return
        }
        library = loaded
        libraryAsked = .now
        Self.save(library)
        log.info("library: \(loaded.playlists.count) playlists, \(loaded.likedSongs.count) liked, \(loaded.albums.count) albums, \(loaded.shows.count) podcasts")
        errorMessage = nil
    }

    private func loadHome() async {
        guard isLinked, let household = await household() else { return }
        do {
            homeShelves = try await sonosService.home(household: household)
            errorMessage = nil
        } catch {
            report(error)
            isLinked = sonosService.isLinked
        }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, isSignedIn || isLinked else {
            searchResults = SpotifySearchResults()
            return
        }
        do {
            if isLinked, let household = await household() {
                // Music through the link, which has no small quota; podcasts only the Web API finds.
                var results = try await sonosService.search(query, household: household)
                if isSignedIn, let web = try? await webAPI.search(query) {
                    results.shows = web.shows
                    results.episodes = web.episodes
                }
                searchResults = results
            } else {
                searchResults = try await webAPI.search(query)
            }
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    /// The songs of a playlist, album or artist. The Web API answers first; it
    /// hides Spotify's own playlists, such as Daily Mix, which the link then gives.
    func songs(of item: SpotifyItem) async throws -> [SpotifyItem] {
        var failure: Error?
        // The link first: it has no small quota, and it shows Spotify's own playlists too.
        if isLinked, item.kind == .playlist || item.kind == .album, let household = await household() {
            do {
                let songs = try await sonosService.songs(of: item.uri, household: household)
                if !songs.isEmpty { return songs }
            } catch {
                failure = error
            }
        }
        if isSignedIn {
            do {
                let songs = try await webAPI.songs(of: item)
                if !songs.isEmpty { return songs }
            } catch {
                failure = error
            }
        }
        throw failure ?? AppError(isSignedIn || isLinked ? "No songs found." : "Connect Spotify first.")
    }

    func albums(ofArtist artist: SpotifyItem) async -> [SpotifyItem] {
        guard isSignedIn else { return [] }
        return (try? await webAPI.albums(ofArtist: artist)) ?? []
    }

    /// The episodes of a podcast, newest first, with where the user stopped.
    func episodes(of show: SpotifyItem) async throws -> [SpotifyItem] {
        guard isSignedIn else { throw AppError("Sign in to Spotify for podcasts.") }
        let episodes = try await webAPI.episodes(of: show)
        canResume = webAPI.canReadPlaybackPosition
        return episodes
    }

    func show(of episode: SpotifyURI) async -> SpotifyItem? {
        guard isSignedIn else { return nil }
        return (try? await webAPI.show(of: episode)) ?? nil
    }

    func albumAndArtist(of track: SpotifyURI) async -> (album: SpotifyItem?, artist: SpotifyItem?) {
        guard isSignedIn else { return (nil, nil) }
        return (try? await webAPI.albumAndArtist(of: track)) ?? (nil, nil)
    }

    /// Turns an artist into their best known songs and a podcast into its newest
    /// episode, so Sonos can play them.
    func resolve(_ request: PlayRequest) async throws -> PlayRequest {
        switch request {
        case .artist(let artist, let shuffle):
            let songs = try await songs(of: artist)
            guard !songs.isEmpty else { throw AppError("No songs found for \(artist.name).") }
            return .songs(songs.map(\.uri), start: 0, shuffle: shuffle)
        case .show(let show):
            guard let newest = try await episodes(of: show).first, let request = PlayRequest.tap(newest) else {
                throw AppError("No episodes found for \(show.name).")
            }
            return request
        default:
            return request
        }
    }

    // MARK: Liked Songs

    func isLiked(_ track: SpotifyURI) async -> Bool? {
        guard isSignedIn else { return nil }
        return try? await webAPI.isLiked(track)
    }

    /// Adds the song to Liked Songs or removes it. Returns whether that worked.
    func setLiked(_ liked: Bool, _ track: SpotifyURI) async -> Bool {
        do {
            try await webAPI.setLiked(liked, track)
            library.likedSongs = (try? await webAPI.likedSongs()) ?? library.likedSongs
            return true
        } catch is SpotifyWebAPI.MissingPermission {
            canLike = false
            return false
        } catch {
            report(error)
            return false
        }
    }

    private static func savedLibrary() -> (SpotifyWebAPI.Library, Date)? {
        guard let data = try? Data(contentsOf: libraryFile),
              let library = try? JSONDecoder().decode(SpotifyWebAPI.Library.self, from: data),
              let saved = try? libraryFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        return (library, saved)
    }

    private static func save(_ library: SpotifyWebAPI.Library) {
        try? FileManager.default.createDirectory(at: libraryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(library).write(to: libraryFile, options: .atomic)
    }

    private func report(_ error: Error) {
        guard !HTTP.isCancellation(error) else { return }
        Logger(subsystem: "com.example.sonifine", category: "Spotify").error("\(String(describing: error))")
        errorMessage = error.localizedDescription
    }
}
