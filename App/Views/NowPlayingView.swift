import AuthenticationServices
import SwiftUI

/// The full player, opened from the mini-player.
struct NowPlayingView: View {
    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyCatalog.self) private var catalog
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss
    @State private var isLiked: Bool?
    @State private var path: [SpotifyItem] = []
    @State private var showsQueue = false
    @State private var neighbours: (previous: URL?, next: URL?) = (nil, nil)

    var body: some View {
        let status = sonos.selectedStatus
        NavigationStack(path: $path) {
            VStack(spacing: 22) {
                topRow(status)
                CoverStrip(previous: neighbours.previous, current: status.artworkURL, next: neighbours.next) { forward in
                    if forward { await sonos.next() } else { await sonos.previous() }
                }
                .padding(.horizontal, -24)  // a page is the screen wide; the cover keeps its margin
                titleRow(status)
                if status.duration > 0 {
                    SongProgress(status: status) { position in Task { await sonos.seek(to: position) } }
                }
                transportRow(status)
                if let group = sonos.selectedGroup {
                    GroupVolumeSlider(group: group, stepButtons: true).font(.title3)
                }
                if let message = sonos.errorMessage ?? (catalog.canLike ? nil : "Sign in to Spotify again to like songs.") {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
                bottomRow
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background { BlurredArtwork(url: status.artworkURL) }
            .toolbar(.hidden, for: .navigationBar)
            .spotifyDestinations()
            .sheet(isPresented: $showsQueue) { QueueView() }
        }
        .modifier(VolumeOverlay())
        .task(id: "\(status.queuePosition) \(status.spotifyTrack?.description ?? "") \(status.playMode.shuffle)") {
            neighbours = await sonos.neighbourArtwork()
        }
        .task(id: status.spotifyTrack) {
            isLiked = nil
            guard let track = status.spotifyTrack else { return }
            isLiked = await catalog.isLiked(track)
        }
    }

    /// Close on the left, the room in the middle and the ⋯ menu on the right, as in Spotify.
    private func topRow(_ status: GroupStatus) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            Spacer()
            Text(sonos.selectedGroup?.name ?? "").font(.subheadline.bold()).lineLimit(1)
            Spacer()
            if let track = status.spotifyTrack, catalog.isSignedIn {
                Menu {
                    Button("Go to album", systemImage: "square.stack") { open(track, \.album) }
                    Button("Go to artist", systemImage: "music.mic") { open(track, \.artist) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .font(.title3)
        .tint(.primary)
        .padding(.top, 8)
    }

    private func titleRow(_ status: GroupStatus) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                MarqueeText(text: status.displayTitle, font: .title2.bold())
                Text([status.artist, status.album].filter { !$0.isEmpty }.joined(separator: " • "))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let track = status.spotifyTrack, catalog.isSignedIn {
                Button { toggleLike(track) } label: {
                    Image(systemName: isLiked == true ? "heart.fill" : "heart")
                        .foregroundStyle(isLiked == true ? Color.accent : .primary)
                        .frame(width: 44, height: 44)
                        .background(Color.primary.opacity(0.1), in: .circle)
                }
                .accessibilityLabel(isLiked == true ? "Remove from Liked Songs" : "Add to Liked Songs")
            }
        }
        .tint(.primary)
    }

    private func transportRow(_ status: GroupStatus) -> some View {
        let mode = status.playMode
        return HStack {
            Button {
                Task { await sonos.setPlayMode(PlayMode(shuffle: !mode.shuffle, repeatMode: mode.repeatMode)) }
            } label: {
                Image(systemName: "shuffle").foregroundStyle(mode.shuffle ? Color.accent : .primary)
            }
            .accessibilityLabel(mode.shuffle ? "Shuffle on" : "Shuffle off")
            Spacer()
            Button { Task { await sonos.previous() } } label: { Image(systemName: "backward.fill").font(.title) }
                .accessibilityLabel("Previous")
            Spacer()
            Button {
                if let group = sonos.selectedGroup { Task { await sonos.togglePlayPause(group) } }
            } label: {
                Image(systemName: status.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34))
                    .frame(width: 76, height: 76)
                    .background(Color.primary.opacity(0.12), in: .circle)
            }
            .accessibilityLabel(status.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { Task { await sonos.next() } } label: { Image(systemName: "forward.fill").font(.title) }
                .accessibilityLabel("Next")
            Spacer()
            Button {
                Task { await sonos.setPlayMode(PlayMode(shuffle: mode.shuffle, repeatMode: mode.repeatMode.next)) }
            } label: {
                Image(systemName: mode.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(mode.repeatMode == .off ? .primary : Color.accent)
            }
            .accessibilityLabel(mode.repeatMode == .off ? "Repeat off" : mode.repeatMode == .all ? "Repeat all" : "Repeat one")
        }
        .font(.title2)
        .tint(.primary)
    }

    private var bottomRow: some View {
        HStack {
            Spacer().frame(width: 44)
            Spacer()
            RoomPicker {
                Label(sonos.selectedGroup?.name ?? "Sonos", systemImage: "hifispeaker.fill").font(.headline)
            }
            Spacer()
            Button { showsQueue = true } label: {
                Image(systemName: "list.bullet").font(.title2).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Queue")
        }
        .tint(.primary)
    }

    private func toggleLike(_ track: SpotifyURI) {
        guard catalog.canLike else {
            Task {
                await catalog.signIn { url in
                    try await webAuthenticationSession.authenticate(
                        using: url, callbackURLScheme: SpotifyWebAPI.callbackScheme)
                }
            }
            return
        }
        let liked = !(isLiked ?? false)
        isLiked = liked
        Task { if await !catalog.setLiked(liked, track) { isLiked = !liked } }
    }

    private func open(_ track: SpotifyURI, _ part: KeyPath<(album: SpotifyItem?, artist: SpotifyItem?), SpotifyItem?>) {
        Task {
            if let item = await catalog.albumAndArtist(of: track)[keyPath: part] { path.append(item) }
        }
    }
}

/// The cover, blurred, as the background of Now Playing.
private struct BlurredArtwork: View {
    let url: URL?

    var body: some View {
        ZStack {
            Color(.systemBackground)
            CachedImage(url: url) { Color.clear }
                .blur(radius: 60)
                .scaleEffect(1.4)
                .opacity(0.8)
            Color(.systemBackground).opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

/// The songs in the queue. Tap one to play it.
struct QueueView: View {
    @Environment(SonosController.self) private var sonos
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [QueueEntry] = []

    var body: some View {
        let current = sonos.selectedStatus.queuePosition - 1
        NavigationStack {
            ScrollViewReader { proxy in
                List(entries) { entry in
                    Button { Task { await sonos.playFromQueue(entry.id) } } label: {
                        HStack(spacing: 12) {
                            Artwork(url: entry.artworkURL).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).lineLimit(1)
                                    .foregroundStyle(entry.id == current ? Color.accent : .primary)
                                Text(entry.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if entry.id == current {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accent)
                            }
                        }
                    }
                    .id(entry.id)
                }
                .overlay {
                    if entries.isEmpty { ContentUnavailableView("The queue is empty", systemImage: "list.bullet") }
                }
                .task {
                    entries = await sonos.queue()
                    proxy.scrollTo(max(0, current), anchor: .top)
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// How far the song is, with the elapsed and total time. Drag to jump in the song.
struct SongProgress: View {
    let status: GroupStatus
    let onSeek: (TimeInterval) -> Void
    @State private var draggedPosition: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = draggedPosition ?? status.position(at: context.date)
            VStack(spacing: 2) {
                Slider(value: Binding(get: { position }, set: { draggedPosition = $0 }),
                       in: 0...max(status.duration, 1)) { editing in
                    guard !editing, let target = draggedPosition else { return }
                    onSeek(target)
                    draggedPosition = nil
                }
                .tint(.primary)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text(Self.format(status.duration))
                }
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Song position")
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The cover with the previous and next covers beside it, as in Spotify: a paging
/// scroll view, so the swipe feels like any iOS swipe. Landing on a neighbour plays it.
private struct CoverStrip: View {
    let previous: URL?
    let current: URL?
    let next: URL?
    /// Skips forward (true) or back, and returns once Sonos plays the new song.
    let skip: (Bool) async -> Void

    private enum Page: Hashable { case previous, current, next }
    @State private var page: Page? = .current
    @State private var isSkipping = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                cover(previous).id(Page.previous)
                cover(current).id(Page.current)
                cover(next).id(Page.next)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $page, anchor: .center)
        .defaultScrollAnchor(.center)
        .scrollIndicators(.hidden)
        // Room for the shadow; the pages are a screen wide, so the neighbours stay off screen.
        .scrollClipDisabled()
        .disabled(isSkipping)
        .onChange(of: page) { _, landed in
            guard let landed, landed != .current, !isSkipping else { return }
            isSkipping = true
            Task { await finishSkip(forward: landed == .next) }
        }
        // The song changed: the neighbour it showed is the new middle cover. Move back to
        // the middle page without animation; the picture stays the same.
        .onChange(of: current) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { page = .current }
            isSkipping = false
        }
    }

    private func cover(_ url: URL?) -> some View {
        Artwork(url: url, cornerRadius: 14)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            .padding(.horizontal, 24)
            .containerRelativeFrame(.horizontal)
    }

    private func finishSkip(forward: Bool) async {
        await skip(forward)
        // The new cover ends the skip in `onChange`. If none came (a refused skip,
        // or the same album cover), go back to the middle.
        try? await Task.sleep(for: .seconds(1))
        guard isSkipping else { return }
        withAnimation { page = .current }
        isSkipping = false
    }
}
