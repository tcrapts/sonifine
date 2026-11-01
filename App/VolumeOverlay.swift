import SwiftUI

/// Shows the Sonos volume for a moment after each press of a volume button.
/// It stands in for the iOS volume overlay, which the app hides because that one
/// shows the iPhone's own volume.
struct VolumeOverlay: ViewModifier {
    @Environment(SonosController.self) private var sonos
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isVisible, let group = sonos.selectedGroup {
                    let volume = sonos.selectedStatus.volume
                    HStack(spacing: 12) {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.title3)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.name).font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: Double(volume), total: 100).tint(Color.accent)
                        }
                        Text("\(volume)")
                            .font(.title2.bold()).monospacedDigit()
                            .frame(minWidth: 44, alignment: .trailing)
                            .contentTransition(.numericText(value: Double(volume)))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 340)
                    .background(.regularMaterial, in: .capsule)
                    .shadow(radius: 10)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.snappy, value: volume)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(group.name) volume \(volume)")
                }
            }
            .animation(.snappy, value: isVisible)
            .task(id: sonos.volumeButtonPresses) {
                guard sonos.volumeButtonPresses > 0 else { return }
                isVisible = true
                try? await Task.sleep(for: .seconds(1.5))
                // A newer press cancels this task and starts the wait again.
                guard !Task.isCancelled else { return }
                isVisible = false
            }
    }
}
