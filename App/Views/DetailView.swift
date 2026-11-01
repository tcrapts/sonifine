import SwiftUI

/// A playlist, album or artist: its cover, Play and Shuffle, and its songs.
struct DetailView: View {
    let item: SpotifyItem
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.play) private var play
    @State private var songs: [SpotifyItem] = []
    @State private var albums: [SpotifyItem] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Artwork(url: item.imageURL, round: item.kind == .artist, cornerRadius: 10)
                        .frame(width: 220, height: 220)
                        .shadow(radius: 12)
                    Text(item.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(item.subtitle).foregroundStyle(.secondary)
                    PlayButtons(play: { play(.tap(item)) }, shuffle: { play(.tap(item, shuffle: true)) })
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
                    // In a playlist or album, a song plays inside it; an artist's songs play as a list.
                    ItemRow(item: song) {
                        play(.tap(song, in: songs, collection: item.kind == .artist ? nil : item))
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                songs = try await catalog.songs(of: item)
            } catch {
                if !HTTP.isCancellation(error) { errorMessage = error.localizedDescription }
            }
            if item.kind == .artist { albums = await catalog.albums(ofArtist: item) }
        }
    }
}
