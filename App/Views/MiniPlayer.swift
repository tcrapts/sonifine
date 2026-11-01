import SwiftUI

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
                        Text(status.displayTitle).font(.subheadline.bold()).lineLimit(1)
                    }
                }
                Spacer()
                RoomPicker {
                    Image(systemName: "hifispeaker.fill").font(.title3).frame(width: 36, height: 36)
                }
                .accessibilityLabel("Room")
                Button { Task { await sonos.togglePlayPause(group) } } label: {
                    Image(systemName: status.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                        .frame(width: 36, height: 36)
                }
                .tint(.primary)
                .accessibilityLabel(status.isPlaying ? "Pause" : "Play")
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
