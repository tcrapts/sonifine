import SwiftUI

/// Searches all of Spotify and the stations of Sonos Radio, with a filter per kind.
struct SearchView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists", radio = "Radio"
        var id: Self { self }
    }

    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(RadioCatalog.self) private var radio
    @Environment(\.play) private var play
    @State private var query = ""
    @State private var filter = Filter.all

    var body: some View {
        let results = catalog.searchResults
        List {
            if !query.isEmpty {
                // Chips that scroll sideways, as in Spotify, so every filter keeps its full name.
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { option in
                            Button(option.rawValue) { filter = option }
                                .font(.subheadline.weight(.medium))
                                .buttonStyle(GlassChip(isSelected: filter == option))
                                .accessibilityAddTraits(filter == option ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch filter {
            case .all:
                rows("Songs", Array(results.tracks.prefix(4)), playing: results.tracks)
                shelf("Artists", results.artists)
                shelf("Albums", results.albums)
                shelf("Playlists", results.playlists)
                if !radio.searchResults.isEmpty {
                    StationShelf(title: "Radio", items: radio.searchResults)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            case .songs: rows("Songs", results.tracks, playing: results.tracks)
            case .artists: rows("Artists", results.artists)
            case .albums: rows("Albums", results.albums)
            case .playlists: rows("Playlists", results.playlists)
            case .radio:
                if !radio.searchResults.isEmpty {
                    Section("Radio") { ForEach(radio.searchResults) { RadioRow(item: $0) } }
                }
            }
            if let message = catalog.errorMessage ?? radio.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .overlay {
            if query.isEmpty {
                if catalog.isSignedIn {
                    ContentUnavailableView("Search Spotify and radio", systemImage: "magnifyingglass",
                                           description: Text("Songs, artists, albums, playlists and stations"))
                } else {
                    ScrollView { SpotifySignIn().padding() }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "What do you want to play?")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            async let spotify: Void = catalog.search(query)
            async let stations: Void = radio.search(query)
            _ = await (spotify, stations)
        }
    }

    /// Songs play with the other songs found; the rest opens.
    @ViewBuilder
    private func rows(_ title: String, _ items: [SpotifyItem], playing list: [SpotifyItem] = []) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in ItemRow(item: item) { play(.tap(item, in: list)) } }
            }
        }
    }

    @ViewBuilder
    private func shelf(_ title: String, _ items: [SpotifyItem]) -> some View {
        if !items.isEmpty {
            Shelf(title: title, items: items)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }
}
