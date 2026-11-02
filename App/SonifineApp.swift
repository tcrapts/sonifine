import SwiftUI

@main
struct SonifineApp: App {
    @State private var sonos: SonosController
    @State private var catalog: SpotifyCatalog
    @State private var radio = RadioCatalog(service: SonosRadioService())
    @State private var favourites = Favourites()
    @State private var watcher = VolumeButtonWatcher()
    @State private var nowPlaying: NowPlayingSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let sonos = SonosController()
        let secrets = KeychainStore()
        _sonos = State(initialValue: sonos)
        _catalog = State(initialValue: SpotifyCatalog(
            webAPI: SpotifyWebAPI(secrets: secrets, defaults: .standard),
            sonosService: SonosSpotifyService(secrets: secrets),
            household: { await sonos.household() }))
        _nowPlaying = State(initialValue: NowPlayingSession(commands: .init(
            play: { Task { if !sonos.selectedStatus.isPlaying, let group = sonos.selectedGroup { await sonos.togglePlayPause(group) } } },
            pause: { Task { if sonos.selectedStatus.isPlaying, let group = sonos.selectedGroup { await sonos.togglePlayPause(group) } } },
            next: { Task { await sonos.next() } },
            previous: { Task { await sonos.previous() } },
            seek: { seconds in Task { await sonos.seek(to: seconds) } })))
    }

    /// Unit tests run inside the app; it then starts nothing, so no test reaches the
    /// Sonos or Spotify, whose small developer quota the tests had been using up.
    private static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup {
            if Self.isTesting { Color.clear } else { app }
        }
    }

    private var app: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") { screen { HomeView() } }
            Tab("Library", systemImage: "books.vertical.fill") { screen { LibraryView() } }
            Tab("Search", systemImage: "magnifyingglass") { screen { SearchView() } }
            Tab("System", systemImage: "hifispeaker.2.fill") { screen { SystemView() } }
        }
        // The mini-player rides above the tab bar. Scrolling down folds the tab bar,
        // and the mini-player moves into it, as in Apple Music.
        .tabViewBottomAccessory { MiniPlayer() }
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(SpotifyLinkSheet())
        .modifier(VolumeOverlay())
        .environment(sonos)
        .environment(catalog)
        .environment(radio)
        .environment(favourites)
        .environment(\.play, PlayAction { request, starting in Task { await play(request, showing: starting) } })
        .environment(\.addToQueue, QueueAction { uri, next in Task { await sonos.addToQueue(uri, next: next) } })
        .background(HiddenVolumeView(watcher: watcher).frame(width: 1, height: 1))
        .task {
            watcher.onPress = { sonos.nudgeVolume($0) }
            sonos.startDiscovery()
            // Pick up changes made elsewhere, such as in the Sonos app.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await sonos.poll()
                nowPlaying.update(group: sonos.selectedGroup, status: sonos.selectedStatus)
            }
        }
        // Load the covers of the next songs, so a new song shows its cover at once.
        .task(id: "\(sonos.selectedStatus.queuePosition) \(sonos.selectedStatus.spotifyTrack?.description ?? "")") {
            ImageCache.shared.prefetch(await sonos.upcomingArtwork())
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            nowPlaying.start()
            watcher.start()
            Task { await sonos.loadGroups() }
        }
    }

    /// The one way the screens start music: the catalog turns an artist into
    /// songs, then Sonos plays the request.
    private func play(_ request: PlayRequest?, showing starting: Starting?) async {
        guard let request else {
            sonos.report("Sonos can't play this kind of item.")
            return
        }
        do {
            await sonos.play(try await catalog.resolve(request), showing: starting)
        } catch {
            if !HTTP.isCancellation(error) { sonos.report(error.localizedDescription) }
        }
    }

    /// A tab's navigation stack.
    private func screen(_ content: () -> some View) -> some View {
        NavigationStack {
            content().spotifyDestinations()
        }
    }
}
