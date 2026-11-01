import Foundation
import Network
import Observation

/// What one group is playing, and how loud.
struct GroupStatus: Equatable {
    var volume = 0
    var isPlaying = false
    /// Seconds into the song when Sonos reported it, at `positionDate`.
    var position: TimeInterval = 0
    /// The length of the song in seconds; 0 for radio.
    var duration: TimeInterval = 0
    var positionDate = Date.distantPast
    var title = ""
    var artist = ""
    var album = ""
    var artworkURL: URL?
    /// The Spotify ID of the song, when it comes from Spotify.
    var spotifyTrackID: String?
    /// The song's place in the queue, counted from 1.
    var queuePosition = 0
    var shuffle = false
    var repeatMode = RepeatMode.off
}

enum RepeatMode: CaseIterable {
    case off, all, one

    var next: RepeatMode { self == .off ? .all : self == .all ? .one : .off }
}

/// A song in the queue of a group.
struct QueueEntry: Identifiable {
    let id: Int
    let title: String
    let artist: String
    let artworkURL: URL?
}

/// Finds the Sonos groups on the network, keeps the status of each, and
/// controls them. The selected group is the one the volume buttons and the
/// mini-player control.
@MainActor
@Observable
final class SonosController {
    private(set) var groups: [SonosGroup] = []
    private(set) var statuses: [String: GroupStatus] = [:]
    /// Counts presses of the volume buttons, so the volume overlay can show each one.
    private(set) var volumeButtonPresses = 0
    /// True while a playlist, album or song is being put in the queue.
    private(set) var isStartingPlayback = false

    /// Shows the failure of the last action until the next one, or else a lost connection.
    var errorMessage: String? { actionError ?? connectionError }
    private var actionError: String?
    private var connectionError: String?

    var selectedGroupID: String? {
        didSet { UserDefaults.standard.set(selectedGroupID, forKey: "selectedGroupID") }
    }

    /// Sonos volume points (0–100) per press of a volume button.
    var stepSize: Int {
        didSet { UserDefaults.standard.set(stepSize, forKey: "stepSize") }
    }

    var selectedGroup: SonosGroup? { groups.first { $0.id == selectedGroupID } }
    var selectedStatus: GroupStatus { selectedGroupID.flatMap { statuses[$0] } ?? GroupStatus() }

    private var householdID: String?
    private var browser: NWBrowser?
    private var knownPlayer: URL?
    private var pendingAdjustment = 0
    private var isSendingVolume = false

    init() {
        let savedStep = UserDefaults.standard.integer(forKey: "stepSize")
        stepSize = savedStep == 0 ? 1 : savedStep
        selectedGroupID = UserDefaults.standard.string(forKey: "selectedGroupID")
    }

    // MARK: Discovery

    /// Sonos players advertise `_sonos._tcp` with their address in the TXT record.
    func startDiscovery() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let players = results.compactMap { result -> URL? in
                guard case .bonjour(let txt) = result.metadata else { return nil }
                return txt["location"].flatMap(URL.init(string:))?.sonosPlayerURL
            }
            Task { @MainActor in
                guard let self, let player = players.first, self.knownPlayer == nil else { return }
                self.knownPlayer = player
                await self.loadGroups()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func loadGroups() async {
        guard let knownPlayer else { return }
        do {
            let response = try await SonosSOAP.call(knownPlayer, .zoneGroupTopology, "GetZoneGroupState", [:])
            groups = ZoneGroupParser.parse(response["ZoneGroupState"] ?? "")
            if selectedGroup == nil { selectedGroupID = groups.first?.id }
            connectionError = nil
            await refresh()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    /// The household of the speakers, for the Sonos Spotify service.
    func household() async -> Household? {
        guard let group = selectedGroup ?? groups.first else { return nil }
        if householdID == nil {
            let response = try? await SonosSOAP.call(group.coordinator, .deviceProperties, "GetHouseholdID", [:])
            householdID = response?["CurrentHouseholdID"]
        }
        return householdID.map { Household(id: $0, deviceID: group.id) }
    }

    // MARK: Status

    /// Reads the status of every group at once.
    func refresh() async {
        let groups = groups
        await withTaskGroup(of: (String, GroupStatus?).self) { taskGroup in
            for group in groups {
                taskGroup.addTask { @MainActor in (group.id, try? await self.status(of: group)) }
            }
            for await (id, status) in taskGroup {
                guard var status else { continue }
                // Keep the volume the buttons just set until Sonos has caught up.
                if id == selectedGroupID, pendingAdjustment != 0 || isSendingVolume {
                    status.volume = statuses[id]?.volume ?? status.volume
                }
                if statuses[id] != status { statuses[id] = status }
            }
        }
    }

    private func status(of group: SonosGroup) async throws -> GroupStatus {
        let player = group.coordinator
        async let volumeInfo = SonosSOAP.call(player, .groupRenderingControl, "GetGroupVolume")
        async let transport = SonosSOAP.call(player, .avTransport, "GetTransportInfo")
        async let position = SonosSOAP.call(player, .avTransport, "GetPositionInfo")
        async let settings = SonosSOAP.call(player, .avTransport, "GetTransportSettings")
        let (volumeValues, transportValues, positionValues) = try await (volumeInfo, transport, position)
        let playMode = (try? await settings)?["PlayMode"] ?? "NORMAL"
        let trackURI = positionValues["TrackURI"] ?? ""

        rememberSpotifyAccount(from: trackURI)
        let track = ElementTextParser.parse(Data((positionValues["TrackMetaData"] ?? "").utf8))
        return GroupStatus(
            volume: volumeValues["CurrentVolume"].flatMap(Int.init) ?? 0,
            isPlaying: transportValues["CurrentTransportState"] == "PLAYING",
            position: Self.seconds(positionValues["RelTime"]),
            duration: Self.seconds(positionValues["TrackDuration"]),
            positionDate: .now,
            title: track["dc:title"] ?? track["r:streamContent"] ?? "",
            artist: track["dc:creator"] ?? track["upnp:album"] ?? "",
            album: track["upnp:album"] ?? "",
            artworkURL: track["upnp:albumArtURI"].flatMap { uri in
                uri.hasPrefix("http") ? URL(string: uri) : URL(string: player.absoluteString + uri)
            },
            spotifyTrackID: Self.spotifyTrackID(in: trackURI),
            queuePosition: positionValues["Track"].flatMap(Int.init) ?? 0,
            shuffle: playMode.hasPrefix("SHUFFLE"),
            repeatMode: playMode.hasSuffix("REPEAT_ONE") ? .one
                : playMode == "REPEAT_ALL" || playMode == "SHUFFLE" ? .all : .off)
    }

    /// `x-sonos-spotify:spotify%3atrack%3a3AJwUDP919kvQ9QcozQPxg?sid=9…` → `3AJwUDP919kvQ9QcozQPxg`
    private static func spotifyTrackID(in trackURI: String) -> String? {
        let decoded = trackURI.removingPercentEncoding ?? trackURI
        guard let range = decoded.range(of: "spotify:track:") else { return nil }
        return String(decoded[range.upperBound...].prefix { $0.isLetter || $0.isNumber })
    }

    /// `0:03:45` → 225 seconds. Sonos uses `NOT_IMPLEMENTED` for radio.
    private static func seconds(_ time: String?) -> TimeInterval {
        let parts = (time ?? "").split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return 0 }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    // MARK: Volume

    /// One press of a volume button: `direction` is +1 or -1.
    func nudgeVolume(_ direction: Int) {
        guard let id = selectedGroupID else { return }
        volumeButtonPresses += 1
        let adjustment = direction * stepSize
        statuses[id, default: GroupStatus()].volume = min(100, max(0, selectedStatus.volume + adjustment))
        pendingAdjustment += adjustment
        guard !isSendingVolume else { return }
        Task { await sendPendingAdjustments() }
    }

    /// Presses that arrive while a request is on its way are summed into the next one.
    private func sendPendingAdjustments() async {
        guard let group = selectedGroup else { pendingAdjustment = 0; return }
        isSendingVolume = true
        defer { isSendingVolume = false }
        while pendingAdjustment != 0 {
            let adjustment = pendingAdjustment
            pendingAdjustment = 0
            do {
                // The snapshot keeps the volume ratios between the rooms of a group.
                _ = try await SonosSOAP.call(group.coordinator, .groupRenderingControl, "SnapshotGroupVolume")
                let response = try await SonosSOAP.call(group.coordinator, .groupRenderingControl,
                                                         "SetRelativeGroupVolume",
                                                         ["InstanceID": "0", "Adjustment": String(adjustment)])
                if pendingAdjustment == 0, let newVolume = response["NewVolume"].flatMap(Int.init) {
                    statuses[group.id]?.volume = newVolume
                }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func setVolume(_ volume: Int, of group: SonosGroup) async {
        statuses[group.id, default: GroupStatus()].volume = volume
        await perform {
            _ = try await SonosSOAP.call(group.coordinator, .groupRenderingControl, "SnapshotGroupVolume")
            _ = try await SonosSOAP.call(group.coordinator, .groupRenderingControl, "SetGroupVolume",
                                         ["InstanceID": "0", "DesiredVolume": String(volume)])
        }
    }

    // MARK: Playback

    func togglePlayPause(_ group: SonosGroup) async {
        let isPlaying = statuses[group.id]?.isPlaying ?? false
        statuses[group.id]?.isPlaying = !isPlaying
        await transport(isPlaying ? "Pause" : "Play", group)
    }

    func pauseAll() async {
        for group in groups where statuses[group.id]?.isPlaying == true {
            statuses[group.id]?.isPlaying = false
            await transport("Pause", group)
        }
    }

    // MARK: Play mode and queue

    func setPlayMode(shuffle: Bool, repeatMode: RepeatMode) async {
        guard let group = selectedGroup else { return }
        statuses[group.id]?.shuffle = shuffle
        statuses[group.id]?.repeatMode = repeatMode
        // Sonos names every combination of shuffle and repeat.
        let mode = switch (shuffle, repeatMode) {
        case (false, .off): "NORMAL"
        case (false, .all): "REPEAT_ALL"
        case (false, .one): "REPEAT_ONE"
        case (true, .off): "SHUFFLE_NOREPEAT"
        case (true, .all): "SHUFFLE"
        case (true, .one): "SHUFFLE_REPEAT_ONE"
        }
        await perform {
            _ = try await SonosSOAP.call(group.coordinator, .avTransport, "SetPlayMode",
                                         ["InstanceID": "0", "NewPlayMode": mode])
        }
    }

    /// The songs in the queue of the selected group, up to 200.
    func queue() async -> [QueueEntry] {
        guard let group = selectedGroup else { return [] }
        let response = try? await SonosSOAP.call(group.coordinator, .contentDirectory, "Browse", [
            "ObjectID": "Q:0", "BrowseFlag": "BrowseDirectChildren",
            "Filter": "dc:title,dc:creator,upnp:albumArtURI", "StartingIndex": "0",
            "RequestedCount": "200", "SortCriteria": "",
        ])
        return QueueParser.parse(response?["Result"] ?? "", player: group.coordinator)
    }

    /// Plays the song at `index` in the queue, counted from 0.
    func playFromQueue(_ index: Int) async {
        guard let group = selectedGroup else { return }
        await perform {
            _ = try await SonosSOAP.call(group.coordinator, .avTransport, "Seek",
                                         ["InstanceID": "0", "Unit": "TRACK_NR", "Target": String(index + 1)])
            _ = try await SonosSOAP.call(group.coordinator, .avTransport, "Play", ["InstanceID": "0", "Speed": "1"])
        }
        await refresh()
    }

    /// Jumps to a moment in the current song.
    func seek(to seconds: TimeInterval) async {
        guard let group = selectedGroup else { return }
        statuses[group.id]?.position = seconds
        statuses[group.id]?.positionDate = .now
        let total = Int(seconds)
        let target = String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        await perform {
            _ = try await SonosSOAP.call(group.coordinator, .avTransport, "Seek",
                                         ["InstanceID": "0", "Unit": "REL_TIME", "Target": target])
        }
    }

    func next() async { if let group = selectedGroup { await transport("Next", group) } }
    func previous() async { if let group = selectedGroup { await transport("Previous", group) } }

    private func transport(_ action: String, _ group: SonosGroup) async {
        let arguments: KeyValuePairs<String, String> = action == "Play"
            ? ["InstanceID": "0", "Speed": "1"] : ["InstanceID": "0"]
        await perform { _ = try await SonosSOAP.call(group.coordinator, .avTransport, action, arguments) }
        await refresh()
    }

    private func perform(_ action: () async throws -> Void) async {
        do {
            try await action()
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: Spotify

    /// Replaces the queue of the selected group with Spotify items and plays it.
    ///
    /// - Parameters:
    ///   - uris: Spotify URIs of songs, or of one playlist or album.
    ///   - startIndex: The song to start with, counted from 0 across the queue.
    ///   - shuffle: Plays the queue in random order.
    func playSpotify(_ uris: [String], startIndex: Int = 0, shuffle: Bool = false) async {
        guard let group = selectedGroup, !uris.isEmpty else { return }
        let player = group.coordinator
        let items = uris.compactMap { SpotifyQueueItem(uri: $0, account: spotifyAccount) }
        isStartingPlayback = true
        actionError = nil
        defer { isStartingPlayback = false }

        do {
            _ = try await SonosSOAP.call(player, .avTransport, "RemoveAllTracksFromQueue")
            var tracksAdded = 0
            // Sonos takes at most 16 items per call.
            for start in stride(from: 0, to: items.count, by: 16) {
                let chunk = items[start..<min(start + 16, items.count)]
                let response = try await SonosSOAP.call(player, .avTransport, "AddMultipleURIsToQueue", [
                    "InstanceID": "0", "UpdateID": "0", "NumberOfURIs": String(chunk.count),
                    "EnqueuedURIs": chunk.map(\.uri).joined(separator: " "),
                    "EnqueuedURIsMetaData": chunk.map(\.metadata).joined(separator: " "),
                    "ContainerURI": "", "ContainerMetaData": "",
                    "DesiredFirstTrackNumberEnqueued": "0", "EnqueueAsNext": "0",
                ])
                tracksAdded += response["NumTracksAdded"].flatMap(Int.init) ?? 0
            }
            guard tracksAdded > 0 else {
                actionError = "There is nothing to play in this list."
                return
            }
            _ = try await SonosSOAP.call(player, .avTransport, "SetAVTransportURI", [
                "InstanceID": "0", "CurrentURI": "x-rincon-queue:\(group.id)#0", "CurrentURIMetaData": "",
            ])
            _ = try await SonosSOAP.call(player, .avTransport, "SetPlayMode", [
                "InstanceID": "0", "NewPlayMode": shuffle ? "SHUFFLE_NOREPEAT" : "NORMAL",
            ])
            if startIndex > 0, !shuffle {
                // For a playlist or album, Sonos counts the list as one item added, so
                // the start can lie beyond `tracksAdded`. If it doesn't exist, play from the top.
                _ = try? await SonosSOAP.call(player, .avTransport, "Seek", [
                    "InstanceID": "0", "Unit": "TRACK_NR", "Target": String(startIndex + 1),
                ])
            }
            _ = try await SonosSOAP.call(player, .avTransport, "Play", ["InstanceID": "0", "Speed": "1"])
        } catch {
            // 804: the Sonos can't open the item, such as an empty playlist or one with only podcasts.
            actionError = error.localizedDescription.hasSuffix("(error 804)")
                ? "Sonos can't play this. Is it empty, or does it hold only podcasts or local files?"
                : "Couldn't play this on \(group.name): \(error.localizedDescription)"
        }
        await refresh()
    }

    /// The Spotify service and account number, as in `x-sonos-spotify:…?sid=9&flags=0&sn=1`.
    private var spotifyAccount = SpotifyAccount(
        serviceID: UserDefaults.standard.string(forKey: "spotifyServiceID") ?? "9",
        serialNumber: UserDefaults.standard.string(forKey: "spotifySerialNumber") ?? "1")

    private func rememberSpotifyAccount(from trackURI: String) {
        guard trackURI.hasPrefix("x-sonos-spotify:"),
              let query = URLComponents(string: trackURI)?.queryItems,
              let serviceID = query.first(where: { $0.name == "sid" })?.value,
              let serialNumber = query.first(where: { $0.name == "sn" })?.value,
              serviceID != spotifyAccount.serviceID || serialNumber != spotifyAccount.serialNumber else { return }
        spotifyAccount = SpotifyAccount(serviceID: serviceID, serialNumber: serialNumber)
        UserDefaults.standard.set(serviceID, forKey: "spotifyServiceID")
        UserDefaults.standard.set(serialNumber, forKey: "spotifySerialNumber")
    }
}

/// Reads the songs from the DIDL-Lite list of a queue.
private final class QueueParser: NSObject, XMLParserDelegate {
    private let player: URL
    private var entries: [QueueEntry] = []
    private var fields: [String: String]?
    private var text = ""

    private init(player: URL) { self.player = player }

    static func parse(_ didl: String, player: URL) -> [QueueEntry] {
        let delegate = QueueParser(player: player)
        let parser = XMLParser(data: Data(didl.utf8))
        parser.delegate = delegate
        parser.parse()
        return delegate.entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "item" { fields = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "item", let fields {
            let art = fields["upnp:albumArtURI"].flatMap { uri in
                uri.hasPrefix("http") ? URL(string: uri) : URL(string: player.absoluteString + uri)
            }
            entries.append(QueueEntry(id: entries.count, title: fields["dc:title"] ?? "",
                                      artist: fields["dc:creator"] ?? "", artworkURL: art))
            self.fields = nil
        } else if fields != nil {
            fields?[elementName] = text
        }
        text = ""
    }
}
