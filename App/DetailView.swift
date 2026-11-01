import SwiftUI

/// A playlist, album or artist: its cover, Play and Shuffle, and its songs.
struct DetailView: View {
    let item: SpotifyItem
    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyController.self) private var spotify
    @Environment(SpotifyHome.self) private var home
    @State private var songs: [SpotifyItem] = []
    @State private var artistAlbums: [SpotifyItem] = []
    @State private var errorMessage: String?

    var body: some View {
        let player = Player(sonos: sonos, spotify: spotify)
        List {
            Section {
                VStack(spacing: 12) {
                    Artwork(url: item.imageURL, symbol: item.kind == .artist ? "person.fill" : "music.note",
                            cornerRadius: item.kind == .artist ? 110 : 10)
                        .frame(width: 220, height: 220)
                        .shadow(radius: 12)
                    Text(item.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(item.subtitle).foregroundStyle(.secondary)
                    PlayButtons(
                        play: { player.play(item) },
                        shuffle: { player.play(item, shuffle: true) })
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            if !artistAlbums.isEmpty {
                Section {
                    Shelf(title: "Albums", items: artistAlbums).padding(.horizontal, -16)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section(item.kind == .artist ? "Popular" : "") {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    ItemRow(item: song) {
                        if item.kind == .artist {
                            player.play(songs: songs, from: index)
                        } else {
                            player.play(item, from: index)
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            songs = await loadSongs()
            if item.kind == .artist { artistAlbums = (try? await spotify.albums(of: item)) ?? [] }
        }
    }

    /// Asks Spotify first. Spotify keeps its own playlists, such as Daily Mix, from
    /// other apps; those come from Sonos's Spotify service.
    private func loadSongs() async -> [SpotifyItem] {
        var failure: Error?
        if spotify.isSignedIn {
            do {
                let songs = try await spotify.tracks(of: item)
                if !songs.isEmpty { return songs }
            } catch {
                failure = error
            }
        }
        if home.isLinked, item.kind != .artist, let household = await sonos.household() {
            do {
                return try await home.tracks(of: item, household: household)
            } catch {
                failure = error
            }
        }
        errorMessage = failure?.localizedDescription ?? "No songs found."
        return []
    }
}
