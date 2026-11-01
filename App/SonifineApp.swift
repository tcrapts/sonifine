import SwiftUI

@main
struct SonifineApp: App {
    @State private var sonos = SonosController()
    @State private var spotify = SpotifyController()
    @State private var spotifyHome = SpotifyHome()
    @State private var watcher = VolumeButtonWatcher()
    @Environment(\.scenePhase) private var scenePhase

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
            .environment(spotify)
            .environment(spotifyHome)
            .background(HiddenVolumeView(watcher: watcher).frame(width: 1, height: 1))
            .task {
                watcher.onPress = { sonos.nudgeVolume($0) }
                sonos.startDiscovery()
                // Pick up changes made elsewhere, such as in the Sonos app.
                while !Task.isCancelled {
                    await sonos.refresh()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                watcher.start()
                Task { await sonos.loadGroups() }
            }
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
