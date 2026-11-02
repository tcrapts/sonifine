import SwiftUI

/// Every room with what it plays, play/pause and volume. Tap a room to play there;
/// its slider button opens the sound and devices of the room.
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
        .navigationDestination(for: SonosRoom.self) { RoomSettingsView(room: $0) }
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
            HStack {
                Text(group.name).font(.headline)
                Spacer()
                roomSettingsLink
            }
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

    /// Opens the sound and devices of the room; a group of several rooms asks which.
    @ViewBuilder private var roomSettingsLink: some View {
        let label = Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 44, height: 28)
        if group.rooms.count == 1, let room = group.rooms.first {
            NavigationLink(value: room) { label }
                .tint(.primary)
                .accessibilityLabel("Sound and devices of \(room.name)")
        } else {
            Menu {
                ForEach(group.rooms) { room in NavigationLink(room.name, value: room) }
            } label: { label }
                .tint(.primary)
                .accessibilityLabel("Sound and devices of a room")
        }
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
                if catalog.hasWebAPI {
                    Section("Spotify podcasts and more") {
                        if catalog.isSignedIn {
                            Button("Sign out", role: .destructive) { catalog.signOut() }
                        } else {
                            SpotifySignIn()
                        }
                    }
                }
                Section {
                    ForEach(sonos.rooms) { room in NavigationLink(room.name, value: room) }
                } header: {
                    Text("Rooms")
                } footer: {
                    Text("Bass, treble, loudness and Trueplay of each room, and its speakers.")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SonosRoom.self) { RoomSettingsView(room: $0) }
            .toolbar { Button("Done") { dismiss() } }
        }
        // This sheet would hide the app's own link page, so it shows its own.
        .modifier(SpotifyLinkSheet())
    }
}
