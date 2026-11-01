import SwiftUI

/// The start screen: the Spotify home and Sonos Radio, one tap from playing.
struct HomeView: View {
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(SonosController.self) private var sonos
    @Environment(RadioCatalog.self) private var radio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if sonos.groups.isEmpty {
                    Label("Looking for your Sonos…", systemImage: "wifi")
                        .foregroundStyle(.secondary).padding(.horizontal)
                }
                if catalog.isLinked {
                    ForEach(catalog.homeShelves) { Shelf(title: $0.title, items: $0.items) }
                    Shelf(title: "Your playlists", items: catalog.library.playlists)
                } else {
                    ConnectSpotifyHome().padding(.horizontal)
                    Shelf(title: "Jump back in", items: catalog.library.jumpBackIn)
                    Shelf(title: "Your playlists", items: catalog.library.playlists)
                    Shelf(title: "Recently played", items: catalog.library.recentlyPlayed)
                    Shelf(title: "Your albums", items: catalog.library.albums)
                }
                // The first row of Sonos Radio; its title opens all of it.
                if let trending = radio.shelves.first {
                    StationShelf(title: "Sonos Radio", items: trending.items, more: .home)
                }
                if !catalog.isSignedIn {
                    SpotifySignIn().padding(.horizontal)
                }
                if let message = catalog.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(greeting)
        .refreshable {
            async let spotify: Void = catalog.reload()
            async let stations: Void = radio.load()
            _ = await (spotify, stations)
        }
        .task { if radio.shelves.isEmpty { await radio.load() } }
        // The Spotify home needs the household, so it loads once Sonos is found.
        .task(id: sonos.groups.isEmpty) {
            if catalog.homeShelves.isEmpty || catalog.library.playlists.isEmpty { await catalog.reload() }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
