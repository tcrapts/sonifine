import AuthenticationServices
import SafariServices
import SwiftUI

extension Color {
    /// Green, a little darker in light mode so green text stays readable on white.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.84, blue: 0.53, alpha: 1)
            : UIColor(red: 0.04, green: 0.62, blue: 0.36, alpha: 1)
    })
}

/// Starts music on the selected Sonos group. The app puts one in the
/// environment; every play button and song row calls it.
struct PlayAction {
    let run: (PlayRequest?) -> Void
    func callAsFunction(_ request: PlayRequest?) { run(request) }
}

/// Adds a song, album or playlist to the queue: next, or at the end.
struct QueueAction {
    let run: (SpotifyURI, _ next: Bool) -> Void
    func callAsFunction(_ uri: SpotifyURI, next: Bool) { run(uri, next) }
}

extension EnvironmentValues {
    @Entry var play = PlayAction { _ in }
    @Entry var addToQueue = QueueAction { _, _ in }
}

extension SpotifyItem {
    /// Songs, albums and playlists can join the queue.
    var queues: Bool { kind == .track || kind == .album || kind == .playlist }
}

/// The Play Next and Add to Queue buttons, for swipe actions and context menus.
private struct QueueButtons: View {
    let item: SpotifyItem

    var body: some View {
        QueueButtonsSingle(item: item, next: true)
        QueueButtonsSingle(item: item, next: false)
    }
}

extension View {
    /// Swipe right for Play Next, left for Add to Queue; or touch and hold for both.
    @ViewBuilder
    func queueActions(for item: SpotifyItem) -> some View {
        if item.queues {
            swipeActions(edge: .leading, allowsFullSwipe: true) {
                QueueButtonsSingle(item: item, next: true).tint(.indigo)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                QueueButtonsSingle(item: item, next: false).tint(.orange)
            }
            .contextMenu { QueueButtons(item: item) }
        } else {
            self
        }
    }
}

/// One of the two queue buttons, for a swipe action.
private struct QueueButtonsSingle: View {
    let item: SpotifyItem
    let next: Bool
    @Environment(\.addToQueue) private var addToQueue

    var body: some View {
        Button { addToQueue(item.uri, next: next) } label: {
            Label(next ? "Play Next" : "Add to Queue",
                  systemImage: next ? "text.line.first.and.arrowtriangle.forward" : "text.line.last.and.arrowtriangle.forward")
        }
    }
}

extension View {
    /// Opens playlists, albums and artists, and the pages of the library.
    func spotifyDestinations() -> some View {
        navigationDestination(for: SpotifyItem.self) { DetailView(item: $0) }
            .navigationDestination(for: LibraryPage.self) { LibraryPageView(page: $0) }
    }
}

struct Artwork: View {
    let url: URL?
    var round = false
    var cornerRadius: CGFloat = 6

    var body: some View {
        // The clear color takes the size it is given; the image fills and is clipped to it.
        Color.clear
            .overlay {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                    Image(systemName: round ? "person.fill" : "music.note").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primary.opacity(0.08))
                }
            }
            .clipShape(round ? AnyShape(Circle()) : AnyShape(.rect(cornerRadius: cornerRadius)))
    }
}

/// A cover with a title. Tapping opens the item; the round button plays it at once.
struct Card: View {
    let item: SpotifyItem
    var list: [SpotifyItem] = []
    var size: CGFloat = 150
    @Environment(\.play) private var play

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                if item.opens {
                    NavigationLink(value: item) { cover }.buttonStyle(.plain).accessibilityLabel(item.name)
                } else {
                    cover
                }
                Button { play(.tap(item, in: list)) } label: {
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
        .contextMenu { if item.queues { QueueButtons(item: item) } }
    }

    private var cover: some View {
        Artwork(url: item.imageURL, round: item.kind == .artist, cornerRadius: 8)
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

/// A song, playlist, album or artist in a list. Items with a page open it; the
/// others play on tap.
struct ItemRow: View {
    let item: SpotifyItem
    let onPlay: () -> Void

    var body: some View {
        Group {
            if item.opens {
                NavigationLink(value: item) { label }
            } else {
                Button(action: onPlay) { label }.tint(.primary)
            }
        }
        .queueActions(for: item)
    }

    private var label: some View {
        HStack(spacing: 12) {
            Artwork(url: item.imageURL, round: item.kind == .artist, cornerRadius: 4)
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

/// The volume of a group: a slider that sends on release, and the number.
/// With `stepButtons`, the speaker icons step the volume like the volume buttons.
struct GroupVolumeSlider: View {
    let group: SonosGroup
    var stepButtons = false
    @Environment(SonosController.self) private var sonos
    @State private var draggedVolume: Double?

    var body: some View {
        let volume = draggedVolume ?? Double(sonos.statuses[group.id]?.volume ?? 0)
        HStack(spacing: 6) {
            speaker("speaker.fill", direction: -1, label: "Volume down")
            Slider(value: Binding(get: { volume }, set: { draggedVolume = $0 }), in: 0...100, step: 1) { editing in
                guard !editing, let target = draggedVolume else { return }
                Task {
                    await sonos.setVolume(Int(target), of: group)
                    draggedVolume = nil
                }
            }
            .tint(.primary)
            if stepButtons { speaker("speaker.wave.3.fill", direction: 1, label: "Volume up") }
            Text("\(Int(volume))").monospacedDigit().frame(width: 36, alignment: .trailing)
        }
        .tint(.secondary)
    }

    @ViewBuilder
    private func speaker(_ symbol: String, direction: Int, label: String) -> some View {
        if stepButtons {
            Button { sonos.nudgeVolume(direction) } label: {
                Image(systemName: symbol).frame(width: 32, height: 36)
            }
            .accessibilityLabel(label)
        } else {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }
}

/// Picks the room that plays, from any screen.
struct RoomPicker<Label: View>: View {
    @ViewBuilder let label: () -> Label
    @Environment(SonosController.self) private var sonos

    var body: some View {
        Menu {
            Picker("Play on", selection: Binding(get: { sonos.selectedGroup?.id },
                                                 set: { id in sonos.groups.first { $0.id == id }.map(sonos.select) })) {
                ForEach(sonos.groups) { Text($0.name).tag(Optional($0.id)) }
            }
        } label: { label() }
        .tint(.primary)
    }
}

/// A card that explains a connection and offers its button.
struct ConnectCard: View {
    let title: String
    let text: String
    let button: String
    var message: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            Text(text).foregroundStyle(.secondary)
            Button(action: action) {
                Text(button).bold().frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .foregroundStyle(.black)
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .padding()
        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 16))
    }
}

/// Links the app to Spotify on Sonos, for the Spotify home.
struct ConnectSpotifyHome: View {
    @Environment(SpotifyCatalog.self) private var catalog

    var body: some View {
        ConnectCard(title: "Get your Spotify home",
                    text: "Daily Mix, Release Radar, your top mixes and radio stations, as in the Spotify app.",
                    button: "Connect Spotify") {
            Task { await catalog.link() }
        }
    }
}

/// Signs in to the Spotify Web API, for the library, search and Liked Songs.
struct SpotifySignIn: View {
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        ConnectCard(title: "Connect your library",
                    text: "Your own playlists, liked songs, albums and search.",
                    button: "Sign in with Spotify") {
            Task {
                await catalog.signIn { url in
                    try await webAuthenticationSession.authenticate(
                        using: url, callbackURLScheme: SpotifyWebAPI.callbackScheme)
                }
            }
        }
    }
}

/// Shows the Sonos sign-in page while linking; it closes by itself once linked.
/// Every screen that can start the link carries it, so it shows above sheets too.
struct SpotifyLinkSheet: ViewModifier {
    @Environment(SpotifyCatalog.self) private var catalog

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { catalog.linkPage != nil },
                                           set: { if !$0 { catalog.cancelLink() } })) {
            if let page = catalog.linkPage { SafariView(url: page).ignoresSafeArea() }
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
