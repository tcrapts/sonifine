import SwiftUI

/// Searches all of Spotify, with a filter per kind.
struct SearchView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", songs = "Songs", artists = "Artists", albums = "Albums", playlists = "Playlists"
        var id: Self { self }
    }

    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyController.self) private var spotify
    @State private var query = ""
    @State private var filter = Filter.all

    var body: some View {
        let results = spotify.searchResults
        let player = Player(sonos: sonos, spotify: spotify)
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
                rows("Songs", results.tracks.prefix(4), player: player, list: results.tracks)
                shelf("Artists", results.artists)
                shelf("Albums", results.albums)
                shelf("Playlists", results.playlists)
            case .songs: rows("Songs", results.tracks[...], player: player, list: results.tracks)
            case .artists: rows("Artists", results.artists[...], player: player, list: [])
            case .albums: rows("Albums", results.albums[...], player: player, list: [])
            case .playlists: rows("Playlists", results.playlists[...], player: player, list: [])
            }
            if let message = spotify.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .overlay {
            if query.isEmpty {
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
            await spotify.search(query)
        }
    }

    @ViewBuilder
    private func rows(_ title: String, _ items: ArraySlice<SpotifyItem>, player: Player,
                      list: [SpotifyItem]) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in ItemRow(item: item) { player.play(item, in: list) } }
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
