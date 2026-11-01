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
                                           description: Text(sonos.errorMessage ?? "This iPhone has to be on the same Wi-Fi."))
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

    var body: some View {
        let status = sonos.statuses[group.id] ?? GroupStatus()
        let isSelected = group.id == sonos.selectedGroup?.id
        VStack(alignment: .leading, spacing: 10) {
            Text(group.name).font(.headline)
            HStack(spacing: 12) {
                Artwork(url: status.artworkURL).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.isReachable ? status.displayTitle : "Not reachable").bold().lineLimit(1)
                    Text(status.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { Task { await sonos.togglePlayPause(group) } } label: {
                    Image(systemName: status.isPlaying ? "pause.fill" : "play.fill").font(.title)
                        .frame(width: 44, height: 44)
                }
                .tint(.primary)
                .accessibilityLabel(status.isPlaying ? "Pause \(group.name)" : "Play \(group.name)")
            }
            GroupVolumeSlider(group: group)
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
        .onTapGesture { sonos.select(group) }
    }
}

struct SettingsView: View {
    @Environment(SonosController.self) private var sonos
    @Environment(SpotifyCatalog.self) private var catalog
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
                    if catalog.isLinked {
                        Button("Disconnect Spotify home", role: .destructive) { catalog.unlink() }
                    } else {
                        ConnectSpotifyHome()
                    }
                } header: {
                    Text("Spotify home")
                } footer: {
                    Text("Daily Mix, Release Radar and the rest of your Spotify home page, through Sonos.")
                }
                Section("Spotify library and search") {
                    if catalog.isSignedIn {
                        Button("Sign out", role: .destructive) { catalog.signOut() }
                    } else {
                        SpotifySignIn()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
        // This sheet would hide the app's own link page, so it shows its own.
        .modifier(SpotifyLinkSheet())
    }
}
