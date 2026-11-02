import AuthenticationServices
import SafariServices
import SwiftUI

extension Color {
    /// Neon green (#33FF73), a little deeper in light mode (#00C752) so green text stays
    /// readable on white.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 1.00, blue: 0.45, alpha: 1)
            : UIColor(red: 0.00, green: 0.78, blue: 0.32, alpha: 1)
    })
}

/// Starts music on the selected Sonos group. The app puts one in the
/// environment; every play button and song row calls it.
struct PlayAction {
    let run: (PlayRequest?, Starting?) -> Void

    /// `showing` is what the mini-player shows while it starts, such as the tapped playlist.
    func callAsFunction(_ request: PlayRequest?, showing item: SpotifyItem? = nil) {
        run(request, item.map(Starting.init))
    }
}

/// Adds a song, album or playlist to the queue: next, or at the end.
struct QueueAction {
    let run: (SpotifyURI, _ next: Bool) -> Void
    func callAsFunction(_ uri: SpotifyURI, next: Bool) { run(uri, next) }
}

extension EnvironmentValues {
    @Entry var play = PlayAction { _, _ in }
    @Entry var addToQueue = QueueAction { _, _ in }
}

extension SpotifyItem {
    /// Songs, episodes, albums and playlists can join the queue.
    var queues: Bool { kind == .track || kind == .episode || kind == .album || kind == .playlist }
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
    /// Opens playlists, albums, artists and podcasts, the pages of the library and those of Sonos Radio.
    func spotifyDestinations() -> some View {
        navigationDestination(for: SpotifyItem.self) { item in
            if item.kind == .show { ShowView(show: item) } else { DetailView(item: item) }
        }
            .navigationDestination(for: LibraryPage.self) { LibraryPageView(page: $0) }
            .navigationDestination(for: RadioPage.self) { RadioPageView(page: $0) }
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
                CachedImage(url: url) {
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
                PlayCircle(name: item.name) { play(.tap(item, in: list), showing: item) }
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

/// The round green button on a cover that plays it at once.
struct PlayCircle: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill").font(.title3).foregroundStyle(.black)
                .frame(width: 40, height: 40)
                .background(Color.accent, in: .circle)
                .shadow(radius: 4)
        }
        .padding(8)
        .accessibilityLabel("Play \(name)")
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
/// others play on tap. A song has a ⋯ menu with the queue actions, as in Spotify.
struct ItemRow: View {
    let item: SpotifyItem
    let onPlay: () -> Void
    @Environment(SonosController.self) private var sonos

    /// The song or episode the selected room plays now: green, with a sound icon, as in Spotify.
    private var isCurrent: Bool {
        (item.isTrack || item.kind == .episode) && sonos.selectedStatus.spotifyTrack == item.uri
    }

    var body: some View {
        Group {
            if item.opens {
                NavigationLink(value: item) { label }
            } else {
                HStack(spacing: 0) {
                    // Borderless buttons keep their own tap area inside a list row.
                    Button(action: onPlay) { label }.buttonStyle(.borderless).tint(.primary)
                    if item.queues {
                        MoreMenu(name: item.name) { QueueButtons(item: item) }
                    }
                }
            }
        }
        .queueActions(for: item)
    }

    private var label: some View {
        HStack(spacing: 12) {
            Artwork(url: item.imageURL, round: item.kind == .artist, cornerRadius: 4)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: sonos.selectedStatus.isPlaying)
                            .font(.caption.bold())
                            .accessibilityLabel(sonos.selectedStatus.isPlaying ? "Playing" : "Paused")
                    }
                    // An episode's title is often long; it gets a second line.
                    Text(item.name).lineLimit(item.episode == nil ? 1 : 2).multilineTextAlignment(.leading)
                }
                .foregroundStyle(isCurrent ? Color.accent : .primary)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let progress = item.episode?.progress, progress < 1 {
                    ProgressView(value: progress).tint(Color.accent).frame(maxWidth: 120)
                        .accessibilityLabel("Listened")
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// The ⋯ at the end of a row, with the actions for its item.
struct MoreMenu<Actions: View>: View {
    let name: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        Menu(content: actions) {
            Image(systemName: "ellipsis").foregroundStyle(.secondary)
                .frame(width: 36, height: 44).contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .tint(.secondary)
        .accessibilityLabel("More for \(name)")
    }
}

/// The glass Shuffle, Play and room buttons of a playlist, album or artist.
struct PlayButtons: View {
    let play: () -> Void
    let shuffle: () -> Void
    @Environment(SonosController.self) private var sonos

    var body: some View {
        HStack(spacing: 16) {
            Button(action: shuffle) {
                Image(systemName: "shuffle").foregroundStyle(Color.accent).frame(width: 44, height: 44)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("Shuffle")
            Button(action: play) {
                Label("Play", systemImage: "play.fill").bold().foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            RoomPicker {
                Image(systemName: "hifispeaker.fill").frame(width: 44, height: 44)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("Play on")
            .accessibilityValue(sonos.selectedGroup?.name ?? "")
        }
        .font(.title3)
        .buttonStyle(.glass)
        // Room for the glass shadow, which the list row would clip.
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
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
                    button: "Sign in with Spotify",
                    message: SpotifyWebAPI.clientID == nil ? SpotifyWebAPI.missingClientIDMessage : nil) {
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

/// One line of text that scrolls sideways when it doesn't fit, as titles do in
/// Spotify: it waits, scrolls one round, and starts again.
struct MarqueeText: View {
    let text: String
    var font: Font = .body
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date.now
    private let gap: CGFloat = 48
    private let speed: CGFloat = 30  // points per second
    private let pause: TimeInterval = 2.5

    var body: some View {
        let overflows = boxWidth > 0 && textWidth > boxWidth
        Text(text).font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                TimelineView(.animation(paused: !overflows)) { context in
                    HStack(spacing: gap) {
                        label.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                        if overflows { label }
                    }
                    .fixedSize()
                    .offset(x: overflows ? -offset(at: context.date) : 0)
                }
            }
            // Fade the edges while scrolling, and keep the text inside its column.
            .mask {
                LinearGradient(stops: overflows ? [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.92), .init(color: .clear, location: 1),
                ] : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                startPoint: .leading, endPoint: .trailing)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .onChange(of: text) { start = .now }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let round = textWidth + gap
        let cycle = pause + round / speed
        let elapsed = date.timeIntervalSince(start).truncatingRemainder(dividingBy: cycle)
        return elapsed < pause ? 0 : CGFloat(elapsed - pause) * speed
    }
}

/// An image from `ImageCache`: shown at once when it is there, else loaded.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url, ImageCache.shared.cached(url) == nil,
                  let image = await ImageCache.shared.image(for: url) else { return }
            loaded = (url, image)
        }
    }

    /// The cover of this URL only, so a new song never shows the old cover.
    private var image: UIImage? {
        guard let url else { return nil }
        return ImageCache.shared.cached(url) ?? (loaded?.url == url ? loaded?.image : nil)
    }
}

/// A capsule on glass for a choice among a few, such as a search filter; the chosen
/// one is green.
struct GlassChip: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(isSelected ? .regular.tint(Color.accent).interactive() : .regular.interactive(), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
