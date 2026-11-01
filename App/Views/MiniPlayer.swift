import SwiftUI

/// The selected room and what it plays, in the tab bar's accessory. Tap it for Now Playing.
struct MiniPlayer: View {
    @Environment(SonosController.self) private var sonos
    @State private var showsNowPlaying = false

    var body: some View {
        let status = sonos.selectedStatus
        HStack(spacing: 10) {
            Artwork(url: status.artworkURL, cornerRadius: 6).frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                if let message = sonos.errorMessage {
                    Text(message).foregroundStyle(.red).lineLimit(1)
                } else if let notice = sonos.notice {
                    Label(notice, systemImage: "checkmark").lineLimit(1)
                } else if sonos.isStartingPlayback {
                    Text("Starting…")
                } else {
                    Text(sonos.selectedGroup == nil ? "Looking for your Sonos…" : status.displayTitle).lineLimit(1)
                }
                Text(sonos.selectedGroup?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
