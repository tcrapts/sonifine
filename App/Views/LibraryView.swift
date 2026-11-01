import SwiftUI

/// A page of the library. Every screen opens through a value, so one navigation
/// stack can push them all in any order.
enum LibraryPage: Hashable {
    case playlists, likedSongs, albums
}

/// The library: playlists, Liked Songs and saved albums.
struct LibraryView: View {
    @Environment(SpotifyCatalog.self) private var catalog

    var body: some View {
        Group {
            if catalog.isSignedIn {
                List {
                    link("Playlists", systemImage: "music.note.list", count: catalog.library.playlists.count, page: .playlists)
                    link("Liked Songs", systemImage: "heart.fill", count: catalog.library.likedSongs.count, page: .likedSongs)
                    link("Albums", systemImage: "square.stack.fill", count: catalog.library.albums.count, page: .albums)
                }
                .refreshable { await catalog.reload() }
            } else {
                ScrollView { SpotifySignIn().padding() }
            }
        }
        .navigationTitle("Library")
    }

    private func link(_ title: String, systemImage: String, count: Int, page: LibraryPage) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(Color.accent)
                    .frame(width: 52, height: 52)
                    .background(Color.accent.opacity(0.15), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text("\(count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The playlists, Liked Songs or albums of the library.
struct LibraryPageView: View {
    let page: LibraryPage
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play

    var body: some View {
        let library = catalog.library
        switch page {
        case .playlists: list("Playlists", library.playlists)
        case .albums: list("Albums", library.albums)
        case .likedSongs: LikedSongsView()
        }
    }

    private func list(_ title: String, _ items: [SpotifyItem]) -> some View {
        List(items) { item in ItemRow(item: item) { play(.tap(item, in: items)) } }
            .navigationTitle(title)
    }

}

/// Every liked song, sorted as the user chose; Play and Shuffle follow that order.
private struct LikedSongsView: View {
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play
    @AppStorage("likedSongsOrder") private var order = SongOrder.newestFirst

    var body: some View {
        let songs = order.apply(to: catalog.library.likedSongs)
        List {
            Section {
                PlayButtons(play: { play(.songs(songs.map(\.uri), start: 0, shuffle: false)) },
                            shuffle: { play(.songs(songs.map(\.uri), start: 0, shuffle: true)) })
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            ForEach(songs) { song in
                ItemRow(item: song) { play(.tap(song, in: songs)) }
            }
        }
        .navigationTitle("Liked Songs")
        .toolbar { SortMenu(order: $order, keys: [.title, .artist, .album, .added]) }
    }
}
