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
    /// Why the podcasts didn't load, such as Spotify's quota, while the rest of the library did.
    private(set) var podcastsProblem: PodcastsProblem?

    private let webAPI: SpotifyWebAPI
    private let sonosService: SonosSpotifyService
    private let household: () async -> Household?
    private let log = Logger(subsystem: "com.example.sonifine", category: "Spotify")

    /// `libraryFile` keeps the last library on the iPhone.
    init(webAPI: SpotifyWebAPI, sonosService: SonosSpotifyService,
         libraryFile: URL = URL.applicationSupportDirectory.appending(path: "spotify-library.json"),
         household: @escaping () async -> Household?) {
        self.webAPI = webAPI
        self.sonosService = sonosService
        self.libraryFile = libraryFile
        self.household = household
        isSignedIn = webAPI.isSignedIn
        isLinked = sonosService.isLinked
        if isSignedIn || isLinked, let saved = savedLibrary() {
            (library, libraryAsked) = saved
        }
        podcastsProblem = webAPI.pause.map(PodcastsProblem.paused)
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
        (podcastsLoaded, recentlyPlayedLoaded, podcastsProblem) = (false, false, nil)
        try? FileManager.default.removeItem(at: libraryFile)
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
    /// Whether the podcasts and recently played loaded since the app started; until
    /// then an empty list may be a refusal, and they are asked again.
    private var podcastsLoaded = false
    private var recentlyPlayedLoaded = false
    /// The last library Spotify gave, kept on the iPhone, so the app shows it at once
    /// and asks Spotify less: Spotify gives a development app a small quota.
    private let libraryFile: URL

    /// Reloads the library and the Spotify home: always when the user asks
    /// (`force`), else at most every six hours.
    func reload(force: Bool = true) async {
        async let library: Void = loadLibrary(force: force)
        async let home: Void = loadHome()
        _ = await (library, home)
    }

    /// Loads the music, the podcasts and recently played each on its own, so one
    /// that fails leaves the others; a part that fails keeps what it had. Each part
    /// that loads is saved.
    private func loadLibrary(force: Bool) async {
        guard isSignedIn || isLinked else { return }
        guard force || Date.now.timeIntervalSince(libraryAsked) > 6 * 60 * 60 else {
            await loadMissing()
            return
        }
        // The link needs the Sonos; Home loads again once it is found.
        var linkHousehold: Household?
        if isLinked {
            guard let found = await household() else { return }
            linkHousehold = found
        }
        async let podcasts: Void = loadPodcasts()
        await loadMusic(household: linkHousehold)
        // After the music: the playlists and albums it holds need no lookup.
        await loadRecentlyPlayed()
        await podcasts
    }

    /// The playlists, Liked Songs and albums: from the link when there is one, as it
    /// has no small quota, else from the Web API.
    private func loadMusic(household: Household?) async {
        do {
            if let household {
                (library.playlists, library.likedSongs, library.albums) = try await sonosService.library(household: household)
            } else {
                (library.playlists, library.likedSongs, library.albums) = try await webAPI.music()
            }
            libraryAsked = .now
            save(library)
            log.info("library: \(self.library.playlists.count) playlists, \(self.library.likedSongs.count) liked, \(self.library.albums.count) albums")
            errorMessage = nil
        } catch {
            // A load the view cancelled, such as when Home restarts its task once the
            // Sonos is found, doesn't count: the next one must still go out.
            if !HTTP.isCancellation(error) { libraryAsked = .now }
            report(error)
        }
    }

    /// The podcasts the user follows, which only the Web API has. When they don't
    /// load, `podcastsProblem` says why.
    private func loadPodcasts() async {
        guard isSignedIn else { return }
        do {
            library.shows = try await webAPI.podcasts()
            podcastsLoaded = true
            podcastsProblem = nil
            save(library)
            log.info("podcasts: loaded \(self.library.shows.count)")
        } catch {
            if HTTP.isCancellation(error) { return }
            if let pause = error as? SpotifyWebAPI.Pause {
                log.info("podcasts: not loaded, Spotify paused until \(pause.until.formatted(date: .omitted, time: .standard))")
            } else {
                log.error("podcasts: \(String(describing: error))")
            }
            podcastsProblem = PodcastsProblem(error)
        }
    }

    /// What played recently, and the playlists and albums it came from, for Home.
    private func loadRecentlyPlayed() async {
        guard isSignedIn else { return }
        do {
            (library.recentlyPlayed, library.jumpBackIn) =
                try await webAPI.recentlyPlayed(known: library.playlists + library.albums)
            recentlyPlayedLoaded = true
            save(library)
        } catch {
            if !HTTP.isCancellation(error) { log.error("recently played: \(String(describing: error))") }
        }
    }

    /// The stored library may lack the podcasts or recently played because Spotify
    /// refused them: ask again. During a pause nothing goes out.
    private func loadMissing() async {
        if library.shows.isEmpty, !podcastsLoaded { await loadPodcasts() }
        if library.recentlyPlayed.isEmpty, !recentlyPlayedLoaded { await loadRecentlyPlayed() }
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

    private func savedLibrary() -> (SpotifyWebAPI.Library, Date)? {
        guard let data = try? Data(contentsOf: libraryFile),
              let library = try? JSONDecoder().decode(SpotifyWebAPI.Library.self, from: data),
              let saved = try? libraryFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return nil }
        return (library, saved)
    }

    private func save(_ library: SpotifyWebAPI.Library) {
        try? FileManager.default.createDirectory(at: libraryFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(library).write(to: libraryFile, options: .atomic)
    }

    private func report(_ error: Error) {
        guard !HTTP.isCancellation(error) else { return }
        log.error("\(String(describing: error))")
        errorMessage = error.localizedDescription
    }
}

/// Why the podcasts didn't load. The message comes at display time, so a pause
/// counts down and goes away when it is over.
enum PodcastsProblem: Equatable {
    case paused(SpotifyWebAPI.Pause)
    /// Spotify refused with 403, as it does for a sign-in without `user-library-read`.
    case signInAgain
    case failed(String)

    init(_ error: Error) {
        switch error {
        case let pause as SpotifyWebAPI.Pause: self = .paused(pause)
        case is SpotifyWebAPI.MissingPermission: self = .signInAgain
        default: self = .failed(error.localizedDescription)
        }
    }

    /// What the user reads at `now`; nil once a pause is over.
    func message(at now: Date) -> String? {
        switch self {
        case .paused(let pause): pause.message(at: now)
        case .signInAgain: "Sign in to Spotify again to see your podcasts."
        case .failed(let message): message
        }
    }
}
