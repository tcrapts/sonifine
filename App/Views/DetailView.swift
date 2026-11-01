import SwiftUI

/// The order of a playlist's songs. The choice holds for every playlist.
enum PlaylistOrder: String {
    case playlist, recentlyAdded

    /// The songs in this order. Songs without a date keep their place at the end.
    func apply(to songs: [SpotifyItem]) -> [SpotifyItem] {
        guard self == .recentlyAdded else { return songs }
        return songs.enumerated().sorted { a, b in
            let (dateA, dateB) = (a.element.addedAt ?? .distantPast, b.element.addedAt ?? .distantPast)
            return dateA != dateB ? dateA > dateB : a.offset < b.offset
        }.map(\.element)
    }
}

/// A playlist, album or artist: its cover, Play and Shuffle, and its songs.
struct DetailView: View {
    let item: SpotifyItem
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play
    @AppStorage("playlistOrder") private var order = PlaylistOrder.playlist
    @State private var loadedSongs: [SpotifyItem] = []
    @State private var albums: [SpotifyItem] = []
    @State private var errorMessage: String?

    /// Only playlists from the library sign-in know when each song was added.
    private var canSort: Bool { item.kind == .playlist && loadedSongs.contains { $0.addedAt != nil } }
    private var isSorted: Bool { canSort && order != .playlist }
    private var songs: [SpotifyItem] { canSort ? order.apply(to: loadedSongs) : loadedSongs }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Artwork(url: item.imageURL, round: item.kind == .artist, cornerRadius: 10)
                        .frame(width: 220, height: 220)
                        .shadow(radius: 12)
                    Text(item.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(item.subtitle).foregroundStyle(.secondary)
                    PlayButtons(play: { play(playAll()) }, shuffle: { play(playAll(shuffle: true)) })
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            if !albums.isEmpty {
                Section {
                    Shelf(title: "Albums", items: albums).padding(.horizontal, -16)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section(item.kind == .artist ? "Popular" : "") {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                ForEach(songs) { song in
                    // In a playlist or album, a song plays inside it; an artist's songs and
                    // a sorted playlist play as the list shown.
                    ItemRow(item: song) {
                        play(.tap(song, in: songs, collection: item.kind == .artist || isSorted ? nil : item))
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canSort {
                Menu {
                    Picker("Sort", selection: $order) {
                        Text("Playlist order").tag(PlaylistOrder.playlist)
                        Text("Recently added").tag(PlaylistOrder.recentlyAdded)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .task {
            do {
                loadedSongs = try await catalog.songs(of: item)
            } catch {
                if !HTTP.isCancellation(error) { errorMessage = error.localizedDescription }
            }
            if item.kind == .artist { albums = await catalog.albums(ofArtist: item) }
        }
    }

    /// Play and Shuffle: the playlist itself, or the songs in the order shown.
    private func playAll(shuffle: Bool = false) -> PlayRequest? {
        isSorted ? .songs(songs.map(\.uri), start: 0, shuffle: shuffle) : .tap(item, shuffle: shuffle)
    }
}
