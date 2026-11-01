import SwiftUI

/// Every room with what it plays, play/pause and volume. Tap a room to play there.
struct SystemView: View {
    @Environment(SonosController.self) private var sonos
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if sonos.groups.isEmpty {
                    ContentUnavailableView("Looking for your Sonos…", systemImage: "wifi",
                                           description: Text("This iPhone has to be on the same Wi-Fi."))
                }
                ForEach(sonos.groups) { RoomCard(group: $0) }
            }
            .padding()
        }
        .navigationTitle("System")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Pause All") { Task { await sonos.pauseAll() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .refreshable { await sonos.loadGroups() }
    }
}

private struct RoomCard: View {
    let group: SonosGroup
    @Environment(SonosController.self) private var sonos
    @State private var draggedVolume: Double?

    var body: some View {
        let status = sonos.statuses[group.id] ?? GroupStatus()
        let isSelected = group.id == sonos.selectedGroupID
        VStack(alignment: .leading, spacing: 10) {
            Text(group.name).font(.headline)
            HStack(spacing: 12) {
                Artwork(url: status.artworkURL).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title.isEmpty ? "Not playing" : status.title).bold().lineLimit(1)
                    Text(status.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { Task { await sonos.togglePlayPause(group) } } label: {
                    Image(systemName: status.isPlaying ? "pause.fill" : "play.fill").font(.title)
                        .frame(width: 44, height: 44)
                }
                .tint(.primary)
            }
            HStack {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
                Slider(value: Binding(get: { draggedVolume ?? Double(status.volume) },
                                      set: { draggedVolume = $0 }),
                       in: 0...100, step: 1) { editing in
                    guard !editing, let volume = draggedVolume else { return }
                    Task {
                        await sonos.setVolume(Int(volume), of: group)
                        draggedVolume = nil
                    }
                }
                .tint(.primary)
                Text("\(Int(draggedVolume ?? Double(status.volume)))")
                    .monospacedDigit().frame(width: 32, alignment: .trailing)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected
                      ? AnyShapeStyle(LinearGradient(colors: [Color.accent.opacity(0.55), Color.accent.opacity(0.25)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.primary.opacity(0.07)))
        }
        .contentShape(.rect)
        .onTapGesture { sonos.selectedGroupID = group.id }
    }
}

struct SettingsView: View {
    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyController.self) private var spotify
    @Environment(SpotifyHome.self) private var home
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var sonos = sonos
        NavigationStack {
            Form {
                Section {
                    Stepper("Step per button press: \(sonos.stepSize)", value: $sonos.stepSize, in: 1...10)
                } header: {
                    Text("Volume buttons")
                } footer: {
                    Text("While the app is open, each press of a volume button changes the Sonos volume by this much, out of 100.")
                }
                Section {
                    if home.isLinked {
                        Button("Disconnect Spotify home", role: .destructive) { home.unlink() }
                    } else {
                        ConnectSpotifyHome()
                    }
                } header: {
                    Text("Spotify home")
                } footer: {
                    Text("Daily Mix, Release Radar and the rest of your Spotify home page, through Sonos.")
                }
                Section("Spotify library and search") {
                    if spotify.isSignedIn {
                        Button("Sign out", role: .destructive) { spotify.signOut() }
                    } else {
                        SpotifySignIn()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
