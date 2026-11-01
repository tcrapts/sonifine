import SwiftUI

/// Searches all of Spotify, with a filter per kind.
struct SearchView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists"
        var id: Self { self }
    }

    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play
    @State private var query = ""
    @State private var filter = Filter.all

    var body: some View {
        let results = catalog.searchResults
        List {
            if !query.isEmpty {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            switch filter {
            case .all:
                rows("Songs", Array(results.tracks.prefix(4)), playing: results.tracks)
                shelf("Artists", results.artists)
                shelf("Albums", results.albums)
                shelf("Playlists", results.playlists)
            case .songs: rows("Songs", results.tracks, playing: results.tracks)
            case .artists: rows("Artists", results.artists)
            case .albums: rows("Albums", results.albums)
            case .playlists: rows("Playlists", results.playlists)
            }
            if let message = catalog.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .overlay {
            if !catalog.isSignedIn {
                ScrollView { SpotifySignIn().padding() }
            } else if query.isEmpty {
                ContentUnavailableView("Search Spotify", systemImage: "magnifyingglass",
                                       description: Text("Songs, artists, albums and playlists"))
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "What do you want to play?")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await catalog.search(query)
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
