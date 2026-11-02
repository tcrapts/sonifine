import SwiftUI

/// The selected room and what it plays, in the tab bar's accessory. Tap it for Now Playing.
struct MiniPlayer: View {
    @Environment(SonosController.self) private var sonos
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var showsNowPlaying = false

    var body: some View {
        let status = sonos.selectedStatus
        // Folded into the tab bar there is room for the cover, title and play button only.
        let isInline = placement == .inline
        HStack(spacing: 10) {
            // While Sonos starts something, show that, not what played before.
            Artwork(url: sonos.starting.map(\.imageURL) ?? status.artworkURL, cornerRadius: 6)
                .frame(width: isInline ? 26 : 34, height: isInline ? 26 : 34)
            VStack(alignment: .leading, spacing: 0) {
                if let message = sonos.errorMessage {
                    Text(message).foregroundStyle(.red).lineLimit(1)
                } else if let notice = sonos.notice {
                    Label(notice, systemImage: "checkmark").lineLimit(1)
                } else if let starting = sonos.starting {
                    Text(starting.name.isEmpty ? "Starting…" : starting.name).lineLimit(1)
                    if !isInline {
                        Text(status.streamProgress?.label ?? "Starting…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(sonos.selectedGroup == nil ? "Looking for your Sonos…" : status.displayTitle).lineLimit(1)
                }
                if !isInline, sonos.starting == nil {
                    Text(sonos.selectedGroup?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            if let group = sonos.selectedGroup {
                Button { Task { await sonos.togglePlayPause(group) } } label: {
                    Image(systemName: status.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(status.isPlaying ? "Pause" : "Play")
            }
        }
        .padding(.horizontal, 12)
        .contentShape(.rect)
        .onTapGesture { showsNowPlaying = true }
        .sheet(isPresented: $showsNowPlaying) { NowPlayingView() }
    }
}
