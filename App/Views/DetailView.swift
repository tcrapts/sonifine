import SwiftUI

/// A playlist, album or artist: its cover, Play and Shuffle, and its songs in an `ItemList`.
struct DetailView: View {
    let item: SpotifyItem
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play
    @State private var songs: [SpotifyItem]?
    @State private var albums: [SpotifyItem] = []
    @State private var errorMessage: String?

    var body: some View {
        // Playlists keep the key they had before every list could sort.
        ItemList("", items: songs, orderKey: item.kind == .playlist ? "playlistSongOrder" : "\(item.kind)SongOrder",
                 sortKeys: [.custom, .title, .artist, .album, .added], sectionTitle: item.kind == .artist ? "Popular" : "",
                 message: errorMessage, prompt: "Search in \(item.name)") { shown in
            ListHeader(item: item) {
                PlayButtons(play: { play(playAll(shown), showing: item) },
                            shuffle: { play(playAll(shown, shuffle: true), showing: item) })
            }
            if !albums.isEmpty {
                Section {
                    Shelf(title: "Albums", items: albums).padding(.horizontal, -16)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        } row: { song, shown in
            // In a playlist or album as it came, a song plays inside it; an artist's
            // songs and a searched or sorted list play as the songs shown.
            ItemRow(item: song) {
                play(.tap(song, in: shown.items, collection: item.kind == .artist || shown.rearranged ? nil : item),
                     showing: song)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                songs = try await catalog.songs(of: item)
            } catch {
                if HTTP.isCancellation(error) { return }
                songs = []
                errorMessage = error.localizedDescription
            }
            if item.kind == .artist { albums = await catalog.albums(ofArtist: item) }
        }
    }

    /// Play and Shuffle: the playlist itself, or the songs as shown.
    private func playAll(_ shown: ShownItems<SpotifyItem>, shuffle: Bool = false) -> PlayRequest? {
        guard shown.rearranged else { return .tap(item, shuffle: shuffle) }
        return shown.items.isEmpty ? nil : .songs(shown.items.map(\.uri), start: 0, shuffle: shuffle)
    }
}
