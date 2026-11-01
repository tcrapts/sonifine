import SwiftUI

/// Where the start screen gets its music from.
enum HomeSource: String, CaseIterable, Identifiable {
    case spotify = "Spotify", radio = "Sonos Radio"
    var id: Self { self }
}

/// The start screen: the Spotify home or Sonos Radio, chosen at the top, one tap from playing.
struct HomeView: View {
    @AppStorage("homeSource") private var source = HomeSource.spotify
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(SonosController.self) private var sonos
    @Environment(RadioCatalog.self) private var radio

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 8) {
                    ForEach(HomeSource.allCases) { option in
                        Button(option.rawValue) { source = option }
                            .font(.subheadline.weight(.medium))
                            .buttonStyle(GlassChip(isSelected: source == option))
                            .accessibilityAddTraits(source == option ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
                if sonos.groups.isEmpty {
                    Label("Looking for your Sonos…", systemImage: "wifi")
                        .foregroundStyle(.secondary).padding(.horizontal)
                }
                switch source {
                case .spotify: spotify
                case .radio: RadioHomeContent()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(greeting)
        .refreshable {
            switch source {
            case .spotify: await catalog.reload()
            case .radio: await radio.load()
            }
        }
        .task(id: source) { if source == .radio, radio.shelves.isEmpty { await radio.load() } }
        // The Spotify home needs the household, so it loads once Sonos is found.
        .task(id: sonos.groups.isEmpty) {
            if catalog.homeShelves.isEmpty || catalog.library.playlists.isEmpty { await catalog.reload(force: false) }
        }
    }

    @ViewBuilder private var spotify: some View {
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
        if !catalog.isSignedIn {
            SpotifySignIn().padding(.horizontal)
        }
        if let message = catalog.errorMessage {
            Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal)
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
