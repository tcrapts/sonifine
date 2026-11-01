import SwiftUI

/// The sound of one room (bass, treble, loudness, Trueplay) and the players in it.
/// Every change goes to the room's own player.
struct RoomSettingsView: View {
    let room: SonosRoom
    @Environment(SonosController.self) private var sonos
    @State private var sound: SoundSettings?
    @State private var devices: [SonosDevice] = []
    @State private var isLoading = true

    var body: some View {
        Form {
            Section {
                if let sound {
                    LevelSlider(title: "Bass", value: sound.bass) { send([.bass($0)]) }
                    LevelSlider(title: "Treble", value: sound.treble) { send([.treble($0)]) }
                    Toggle("Loudness", isOn: Binding(get: { sound.loudness }, set: { send([.loudness($0)]) }))
                        .tint(Color.accent)
                    if let trueplay = sound.trueplay {
                        LabeledContent("Trueplay", value: trueplay ? "On" : "Off")
                    }
                    Button("Reset to default", role: .destructive) { send(SoundSettings.defaults) }
                        .frame(maxWidth: .infinity)
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(sonos.errorMessage ?? "\(room.name) doesn't answer.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Reset to default sets bass and treble to 0 and turns loudness on.")
            }
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                Section {
                    Text(device.name).font(.headline)
                    LabeledContent("Model", value: device.model)
                    LabeledContent("ID", value: device.id)
                    LabeledContent("Serial Number", value: device.serialNumber)
                    LabeledContent("Software Version", value: device.softwareVersion)
                    LabeledContent("Hardware Version", value: device.hardwareVersion)
                    LabeledContent("IP Address", value: device.ipAddress)
                } header: {
                    if index == 0 { Text("Devices") }
                }
                .textSelection(.enabled)
            }
        }
        .navigationTitle(room.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let sound = sonos.soundSettings(of: room)
            async let devices = sonos.devices(in: room)
            (self.sound, self.devices) = await (sound, devices)
            isLoading = false
        }
    }

    /// Shows the change at once and sends it; when the player refuses, shows what it has.
    private func send(_ settings: [SoundSetting]) {
        for setting in settings { sound?.apply(setting) }
        Task {
            if await !sonos.change(settings, of: room) { sound = await sonos.soundSettings(of: room) }
        }
    }
}

/// A −10…10 slider that sends its value once, when the finger lets go.
private struct LevelSlider: View {
    let title: String
    let value: Int
    let send: (Int) -> Void
    @State private var dragged: Double?

    var body: some View {
        let shown = dragged ?? Double(value)
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title, value: String(Int(shown)))
            Slider(value: Binding(get: { shown }, set: { dragged = $0 }),
                   in: Double(SoundSettings.range.lowerBound)...Double(SoundSettings.range.upperBound), step: 1) {
                Text(title)
            } minimumValueLabel: {
                Text("\(SoundSettings.range.lowerBound)").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("\(SoundSettings.range.upperBound)").foregroundStyle(.secondary)
            } onEditingChanged: { editing in
                guard !editing, let dragged else { return }
                self.dragged = nil
                if Int(dragged) != value { send(Int(dragged)) }
            }
            .tint(Color.accent)
        }
    }
}
