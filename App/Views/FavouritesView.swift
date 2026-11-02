import SwiftUI

/// The favourite stations: drag to put them in order and swipe to remove them
/// after Edit, tap one to edit it, and add a Sonos Radio station or a custom stream with +.
struct FavouritesView: View {
    @Environment(Favourites.self) private var favourites
    @Environment(SonosController.self) private var sonos
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case edit(Favourite), newStream, newStation

        var id: String {
            switch self {
            case .edit(let favourite): favourite.id.uuidString
            case .newStream: "stream"
            case .newStation: "station"
            }
        }
    }

    var body: some View {
        List {
            ForEach(favourites.all) { favourite in
                Button { sheet = .edit(favourite) } label: {
                    RadioLabel(name: favourite.name, subtitle: favourite.sourceLabel, imageURL: favourite.logoURL,
                               isCurrent: sonos.selectedStatus.station == favourite.name)
                }
                .tint(.primary)
            }
            .onMove { favourites.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { favourites.remove(atOffsets: $0) }
        }
        .overlay {
            if favourites.all.isEmpty {
                ContentUnavailableView("No Favourites", systemImage: "star",
                                       description: Text("Add a Sonos Radio station or a stream of your own with +."))
            }
        }
        .navigationTitle("Favourites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Sonos Radio Station", systemImage: "magnifyingglass") { sheet = .newStation }
                    Button("Custom Stream", systemImage: "link") { sheet = .newStream }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit(let favourite): FavouriteForm(favourite: favourite)
            case .newStream: FavouriteForm(favourite: nil)
            case .newStation: AddStationView()
            }
        }
    }
}

/// Adds a custom stream, or edits a favourite: its name, its logo and, for a
/// custom stream, its address. A new address is checked for audio before it is kept.
private struct FavouriteForm: View {
    /// The favourite to edit; nil for a new custom stream.
    let original: Favourite?
    @Environment(Favourites.self) private var favourites
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var logo: String
    @State private var problem: String?
    @State private var isChecking = false

    init(favourite: Favourite?) {
        original = favourite
        _name = State(initialValue: favourite?.name ?? "")
        _logo = State(initialValue: favourite?.logoURL?.absoluteString ?? "")
        if case .stream(let url) = favourite?.source {
            _address = State(initialValue: url.absoluteString)
        } else {
            _address = State(initialValue: "")
        }
    }

    /// The Sonos Radio station the favourite refers to; nil for a custom stream.
    private var stationID: String? {
        if case .sonosRadio(let id) = original?.source { id } else { nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                // At the top, where the keyboard leaves it in view.
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                Section("Name") {
                    TextField("Station name", text: $name).textInputAutocapitalization(.words)
                }
                if let stationID {
                    Section("Source") { LabeledContent("Sonos Radio", value: stationID) }
                } else {
                    Section {
                        webAddressField("https://example.com/stream.mp3", text: $address)
                    } header: {
                        Text("Stream address")
                    } footer: {
                        Text("The station's own MP3 or AAC stream. It plays straight from the station, without TuneIn.")
                    }
                }
                Section("Logo (optional)") {
                    HStack(spacing: 12) {
                        Artwork(url: logoURL, cornerRadius: 4).frame(width: 48, height: 48)
                        webAddressField("https://example.com/logo.png", text: $logo)
                    }
                }
            }
            .navigationTitle(original == nil ? "Custom Stream" : "Edit Favourite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView().accessibilityLabel("Checking the stream")
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(trimmed(name).isEmpty || (stationID == nil && trimmed(address).isEmpty))
                    }
                }
            }
        }
    }

    private var logoURL: URL? { StreamCheck.webAddress(logo) }

    private func webAddressField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() async {
        problem = nil
        guard trimmed(logo).isEmpty || logoURL != nil else {
            problem = "Enter the logo's address, starting with https://, or leave it empty."
            return
        }
        let source: Favourite.Source
        if let original, stationID != nil {
            source = original.source
        } else {
            do {
                let url = try StreamCheck.address(address)
                if original?.source != .stream(url) {
                    isChecking = true
                    problem = await StreamCheck.problem(with: url)
                    isChecking = false
                    if problem != nil { return }
                }
                source = .stream(url)
            } catch {
                problem = error.localizedDescription
                return
            }
        }
        let favourite = Favourite(id: original?.id ?? UUID(), name: trimmed(name), logoURL: logoURL, source: source)
        if original == nil { favourites.add(favourite) } else { favourites.update(favourite) }
        dismiss()
    }
}

/// Searches Sonos Radio for stations; a tap adds one to the favourites or takes it out.
private struct AddStationView: View {
    @Environment(RadioCatalog.self) private var radio
    @Environment(Favourites.self) private var favourites
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var found: [RadioItem] = []

    var body: some View {
        NavigationStack {
            List(found.filter(\.isStation)) { station in
                let isFavourite = favourites.contains(station)
                Button { favourites.toggle(station) } label: {
                    HStack {
                        RadioLabel(item: station)
                        Image(systemName: isFavourite ? "checkmark.circle.fill" : "plus.circle")
                            .font(.title2)
                            .foregroundStyle(isFavourite ? Color.accent : .secondary)
                    }
                }
                .tint(.primary)
                .accessibilityLabel(isFavourite ? "Remove \(station.name) from Favourites" : "Add \(station.name) to Favourites")
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Find a Station", systemImage: "dot.radiowaves.left.and.right",
                                           description: Text("Search Sonos Radio by name, such as NPO Radio 2."))
                } else if let message = radio.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red).padding()
                }
            }
            .navigationTitle("Sonos Radio Station")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station name")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                if let stations = await radio.stations(matching: query) { found = stations }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
