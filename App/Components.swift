import SwiftUI

extension Color {
    /// Green, a little darker in light mode so green text stays readable on white.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.84, blue: 0.53, alpha: 1)
            : UIColor(red: 0.04, green: 0.62, blue: 0.36, alpha: 1)
    })
}

/// Starts Spotify music on the selected Sonos group.
@MainActor
struct Player {
    let sonos: SonosController
    let spotify: SpotifyController

    /// Plays `item`. A song plays with the songs after it in `list`; an artist
    /// plays their best known songs.
    func play(_ item: SpotifyItem, in list: [SpotifyItem] = [], shuffle: Bool = false) {
        Task {
            switch item.kind {
            case .track:
                let songs = list.filter(\.isTrack).isEmpty ? [item] : list.filter(\.isTrack)
                await sonos.playSpotify(songs.map(\.uri), startIndex: songs.firstIndex(of: item) ?? 0,
                                        shuffle: shuffle)
            case .artist:
                let songs = (try? await spotify.tracks(of: item)) ?? []
                await sonos.playSpotify(songs.map(\.uri), shuffle: shuffle)
            case .playlist, .album, .other:
                await sonos.playSpotify([item.uri], shuffle: shuffle)
            }
        }
    }

    /// Plays a playlist or album from its song at `index`.
    func play(_ collection: SpotifyItem, from index: Int) {
        Task { await sonos.playSpotify([collection.uri], startIndex: index) }
    }

    /// Plays a list of songs, such as Liked Songs.
    func play(songs: [SpotifyItem], from index: Int = 0, shuffle: Bool = false) {
        Task { await sonos.playSpotify(songs.map(\.uri), startIndex: index, shuffle: shuffle) }
    }
}

extension View {
    /// Opens playlists, albums and artists in `DetailView`, and the pages of the library.
    func spotifyDestinations() -> some View {
        navigationDestination(for: SpotifyItem.self) { DetailView(item: $0) }
            .navigationDestination(for: LibraryPage.self) { page in
                switch page {
                case .playlists: LibraryItems(title: "Playlists", items: \.playlists)
                case .likedSongs: LikedSongsView()
                case .albums: LibraryItems(title: "Albums", items: \.albums)
                }
            }
    }
}

struct Artwork: View {
    let url: URL?
    var symbol = "music.note"
    var cornerRadius: CGFloat = 6

    var body: some View {
        // The clear color takes the size it is given; the image fills and is clipped to it.
        Color.clear
            .overlay {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                    Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primary.opacity(0.08))
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
    }
}

/// A cover with a title. Tapping opens the item; the round button plays it at once.
struct Card: View {
    let item: SpotifyItem
    var list: [SpotifyItem] = []
    var size: CGFloat = 150
    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyController.self) private var spotify

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                if item.isTrack {
                    cover
                } else {
                    NavigationLink(value: item) { cover }.buttonStyle(.plain).accessibilityLabel(item.name)
                }
                Button {
                    Player(sonos: sonos, spotify: spotify).play(item, in: list)
                } label: {
                    Image(systemName: "play.fill").font(.title3).foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.accent, in: .circle)
                        .shadow(radius: 4)
                }
                .padding(8)
                .accessibilityLabel("Play \(item.name)")
            }
            Text(item.name).font(.subheadline.bold()).lineLimit(1)
            Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: size)
    }

    private var cover: some View {
        Artwork(url: item.imageURL, symbol: item.kind == .artist ? "person.fill" : "music.note",
                cornerRadius: item.kind == .artist ? size / 2 : 8)
            .frame(width: size, height: size)
    }
}

/// A titled, horizontal row of cards.
struct Shelf: View {
    let title: String
    let items: [SpotifyItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title2.bold()).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { Card(item: $0, list: items) }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

/// A song, playlist, album or artist in a list. Songs play on tap; the others open.
struct ItemRow: View {
    let item: SpotifyItem
    var onPlay: () -> Void

    var body: some View {
        if item.isTrack {
            Button(action: onPlay) { label }.tint(.primary)
        } else {
            NavigationLink(value: item) { label }
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Artwork(url: item.imageURL, symbol: item.kind == .artist ? "person.fill" : "music.note",
                    cornerRadius: item.kind == .artist ? 24 : 4)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// The selected room and what it plays, above the tab bar. Tap it for Now Playing.
struct MiniPlayer: View {
    @Environment(SonosController.self) private var sonos
    @State private var showsNowPlaying = false

    var body: some View {
        if let group = sonos.selectedGroup {
            let status = sonos.selectedStatus
            HStack(spacing: 12) {
                Artwork(url: status.artworkURL).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.caption).foregroundStyle(Color.accent)
                    if let message = sonos.errorMessage {
                        Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                    } else if sonos.isStartingPlayback {
                        Text("Starting…").font(.subheadline.bold())
                    } else {
                        Text(status.title.isEmpty ? "Not playing" : status.title)
                            .font(.subheadline.bold()).lineLimit(1)
                    }
                }
                Spacer()
                RoomMenu()
                Button { Task { await sonos.togglePlayPause(group) } } label: {
                    Image(systemName: status.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                        .frame(width: 36, height: 36)
                }
                .tint(.primary)
            }
            .padding(10)
            .overlay(alignment: .bottom) {
                SongProgressLine(status: status).padding(.horizontal, 14).padding(.bottom, 3)
            }
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
            .onTapGesture { showsNowPlaying = true }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .sheet(isPresented: $showsNowPlaying) { NowPlayingView() }
        }
    }
}

/// Picks the room that plays, from any screen.
struct RoomMenu: View {
    @Environment(SonosController.self) private var sonos

    var body: some View {
        @Bindable var sonos = sonos
        Menu {
            Picker("Play on", selection: $sonos.selectedGroupID) {
                ForEach(sonos.groups) { Text($0.name).tag(Optional($0.id)) }
            }
        } label: {
            Image(systemName: "hifispeaker.fill").font(.title3).frame(width: 36, height: 36)
        }
        .tint(.primary)
        .accessibilityLabel("Room")
    }
}
