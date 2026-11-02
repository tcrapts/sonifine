import SwiftUI

/// Searches all of Spotify, podcasts included, and the stations of Sonos Radio, with a filter per kind.
struct SearchView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists",
             podcasts = "Podcasts", radio = "Radio"
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
                FilterChips(options: Filter.allCases.filter { $0 != .podcasts || catalog.hasWebAPI },
                            selection: $filter) { $0.rawValue }
            }
            switch filter {
            case .all:
                rows("Songs", Array(results.tracks.prefix(4)), playing: results.tracks)
                shelf("Artists", results.artists)
                shelf("Albums", results.albums)
                shelf("Playlists", results.playlists)
                shelf("Podcasts", results.shows)
                if !radio.searchResults.isEmpty {
                    StationShelf(title: "Radio", items: radio.searchResults)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
            case .songs: rows("Songs", results.tracks, playing: results.tracks)
            case .artists: rows("Artists", results.artists)
            case .albums: rows("Albums", results.albums)
            case .playlists: rows("Playlists", results.playlists)
            case .podcasts:
                rows("Podcasts", results.shows)
                rows("Episodes", results.episodes)
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
                if catalog.hasLibrary {
                    ContentUnavailableView("Search Spotify and radio", systemImage: "magnifyingglass",
                                           description: Text(catalog.hasWebAPI
                                               ? "Songs, artists, albums, playlists, podcasts and stations"
                                               : "Songs, artists, albums, playlists and stations"))
                } else {
                    ScrollView {
                    // Without a developer app, the link is the way to Spotify.
                    Group { if catalog.hasWebAPI { SpotifySignIn() } else { ConnectSpotifyHome() } }.padding()
                }
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
                ForEach(items) { item in ItemRow(item: item) { play(.tap(item, in: list), showing: item) } }
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
