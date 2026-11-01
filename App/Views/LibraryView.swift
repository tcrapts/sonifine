import SwiftUI

/// A page of the library. Every screen opens through a value, so one navigation
/// stack can push them all in any order.
enum LibraryPage: Hashable {
    case playlists, likedSongs, albums, podcasts
}

/// The library: playlists, Liked Songs, saved albums and the podcasts the user follows.
struct LibraryView: View {
    @Environment(SpotifyCatalog.self) private var catalog

    var body: some View {
        Group {
            if catalog.isSignedIn {
                List {
                    link("Playlists", systemImage: "music.note.list", count: catalog.library.playlists.count, page: .playlists)
                    link("Liked Songs", systemImage: "heart.fill", count: catalog.library.likedSongs.count, page: .likedSongs)
                    link("Albums", systemImage: "square.stack.fill", count: catalog.library.albums.count, page: .albums)
                    link("Podcasts", systemImage: "mic.fill", count: catalog.library.shows.count, page: .podcasts,
                         note: catalog.library.shows.isEmpty ? catalog.podcastsMessage : nil)
                }
                .refreshable { await catalog.reload() }
            } else {
                ScrollView { SpotifySignIn().padding() }
            }
        }
        .navigationTitle("Library")
    }

    /// A row of the library; `note` says why it is empty, such as Spotify's quota.
    private func link(_ title: String, systemImage: String, count: Int, page: LibraryPage, note: String? = nil) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(Color.accent)
                    .frame(width: 52, height: 52)
                    .background(Color.accent.opacity(0.15), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    if let note {
                        Text(note).font(.caption).foregroundStyle(.orange)
                    } else {
                        Text("\(count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The playlists, Liked Songs, albums or podcasts of the library, each in an `ItemList`.
struct LibraryPageView: View {
    let page: LibraryPage
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play

    var body: some View {
        let library = catalog.library
        switch page {
        case .playlists: list("Playlists", library.playlists, orderKey: "playlistsOrder", sortKeys: [.custom, .title, .added])
        case .albums: list("Albums", library.albums, orderKey: "albumsOrder", sortKeys: [.custom, .title, .artist, .added])
        case .podcasts:
            list("Podcasts", library.shows, orderKey: "podcastsOrder", sortKeys: [.custom, .title, .added])
                .overlay {
                    if library.shows.isEmpty, let message = catalog.podcastsMessage {
                        ContentUnavailableView("Podcasts didn't load", systemImage: "exclamationmark.triangle",
                                               description: Text(message))
                    }
                }
        case .likedSongs: likedSongs(library.likedSongs)
        }
    }

    private func list(_ title: String, _ items: [SpotifyItem], orderKey: String, sortKeys: [ListOrder.Key]) -> some View {
        ItemList(title, items: items, orderKey: orderKey, sortKeys: sortKeys) { item, shown in
            ItemRow(item: item) { play(.tap(item, in: shown.items)) }
        }
    }

    /// Every liked song, newest first unless the user chose otherwise; Play and
    /// Shuffle follow the songs shown.
    private func likedSongs(_ songs: [SpotifyItem]) -> some View {
        ItemList("Liked Songs", items: songs, orderKey: "likedSongsOrder", defaultOrder: .newestFirst,
                 sortKeys: [.title, .artist, .album, .added]) { shown in
            ListHeader(item: nil) {
                PlayButtons(play: { play(.songs(shown.items.map(\.uri), start: 0, shuffle: false)) },
                            shuffle: { play(.songs(shown.items.map(\.uri), start: 0, shuffle: true)) })
            }
        } row: { song, shown in
            ItemRow(item: song) { play(.tap(song, in: shown.items)) }
        }
    }
}
