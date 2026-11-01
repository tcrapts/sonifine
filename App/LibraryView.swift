import SwiftUI

/// A page of the library. Every screen opens through a value, so that one
/// navigation stack can push them all in any order.
enum LibraryPage: Hashable {
    case playlists, likedSongs, albums
}

/// Your Spotify library: playlists, liked songs and saved albums.
struct LibraryView: View {
    @Environment(SpotifyController.self) private var spotify

    var body: some View {
        Group {
            if spotify.isSignedIn {
                List {
                    link("Playlists", systemImage: "music.note.list", count: spotify.playlists.count, page: .playlists)
                    link("Liked Songs", systemImage: "heart.fill", count: spotify.likedSongs.count, page: .likedSongs)
                    link("Albums", systemImage: "square.stack.fill", count: spotify.albums.count, page: .albums)
                }
                .refreshable { await spotify.loadLibrary() }
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

/// The playlists or albums of the library.
struct LibraryItems: View {
    let title: String
    let items: KeyPath<SpotifyController, [SpotifyItem]>
    @Environment(SpotifyController.self) private var spotify

    var body: some View { ItemList(title: title, items: spotify[keyPath: items]) }
}

/// A plain list of playlists or albums.
struct ItemList: View {
    let title: String
    let items: [SpotifyItem]
    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyController.self) private var spotify

    var body: some View {
        List(items) { item in
            ItemRow(item: item) { Player(sonos: sonos, spotify: spotify).play(item, in: items) }
        }
        .navigationTitle(title)
    }
}

struct LikedSongsView: View {
    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyController.self) private var spotify

    var body: some View {
        let player = Player(sonos: sonos, spotify: spotify)
        let songs = spotify.likedSongs
        List {
            Section {
                PlayButtons(
                    play: { player.play(songs: songs) },
                    shuffle: { player.play(songs: songs, shuffle: true) })
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                ItemRow(item: song) { player.play(songs: songs, from: index) }
            }
        }
        .navigationTitle("Liked Songs")
    }
}

/// The large Play and Shuffle buttons of a playlist, album or artist.
struct PlayButtons: View {
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                Label("Play", systemImage: "play.fill").bold().frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .foregroundStyle(.black)
            Button(action: shuffle) {
                Label("Shuffle", systemImage: "shuffle").bold().frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
    }
}
