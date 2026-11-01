import SwiftUI

@main
struct SonifineApp: App {
    @State private var sonos: SonosController
    @State private var catalog: SpotifyCatalog
    @State private var watcher = VolumeButtonWatcher()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let sonos = SonosController()
        let secrets = KeychainStore()
        _sonos = State(initialValue: sonos)
        _catalog = State(initialValue: SpotifyCatalog(
            webAPI: SpotifyWebAPI(secrets: secrets),
            sonosService: SonosSpotifyService(secrets: secrets),
            household: { await sonos.household() }))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Home", systemImage: "house.fill") { screen { HomeView() } }
                Tab("Library", systemImage: "books.vertical.fill") { screen { LibraryView() } }
                Tab("Search", systemImage: "magnifyingglass") { screen { SearchView() } }
                Tab("System", systemImage: "hifispeaker.2.fill") { screen { SystemView() } }
            }
            .tint(Color.accent)
            .modifier(SpotifyLinkSheet())
            .modifier(VolumeOverlay())
            .environment(sonos)
            .environment(catalog)
            .environment(\.play, PlayAction { request in Task { await play(request) } })
            .background(HiddenVolumeView(watcher: watcher).frame(width: 1, height: 1))
            .task {
                watcher.onPress = { sonos.nudgeVolume($0) }
                sonos.startDiscovery()
                // Pick up changes made elsewhere, such as in the Sonos app.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    await sonos.poll()
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                watcher.start()
                Task { await sonos.loadGroups() }
            }
        }
    }

    /// The one way the screens start music: the catalog turns an artist into
    /// songs, then Sonos plays the request.
    private func play(_ request: PlayRequest?) async {
        guard let request else {
            sonos.report("Sonos can't play this kind of item.")
            return
        }
        do {
            await sonos.play(try await catalog.resolve(request))
        } catch {
            if !HTTP.isCancellation(error) { sonos.report(error.localizedDescription) }
        }
    }

    /// A tab's navigation stack with the mini-player above the tab bar.
    private func screen(_ content: () -> some View) -> some View {
        NavigationStack {
            content().spotifyDestinations()
        }
        // Room below the last row of every screen in the stack, so the mini-player
        // never covers it.
        .contentMargins(.bottom, 84, for: .scrollContent)
        .overlay(alignment: .bottom) { MiniPlayer() }
    }
}
