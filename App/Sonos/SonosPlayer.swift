import Foundation

/// One Sonos player on the network, in domain terms. Group operations go to a
/// coordinator; `zoneGroups()` and `householdID()` work on any player; the
/// sound settings and the device belong to the player of one room.
///
/// `SOAPSonosPlayer` talks to a real player; tests use a fake.
@MainActor
protocol SonosPlayer {
    func zoneGroups() async throws -> [SonosGroup]
    func householdID() async throws -> String
    func status() async throws -> GroupStatus

    /// Changes the group volume and returns the new volume. The rooms keep their ratios.
    func adjustVolume(by adjustment: Int) async throws -> Int
    func setVolume(_ volume: Int) async throws

    func play() async throws
    func pause() async throws
    func next() async throws
    func previous() async throws
    /// Jumps to the song at `number` in the queue, counted from 1.
    func seek(toTrack number: Int) async throws
    /// Takes the song at `index`, counted from 0, out of the queue.
    func removeFromQueue(_ index: Int) async throws
    func seek(to seconds: TimeInterval) async throws
    func setPlayMode(_ mode: PlayMode) async throws

    /// Empties the queue, fills it with `items` and makes the group play from it.
    /// Returns the number of songs added; a playlist or album counts as one.
    func replaceQueue(with items: [SonosQueueItem], groupID: String) async throws -> Int
    /// Adds `items` to the queue: right after `current` (counted from 1) for
    /// Play Next, or at the end. Returns the number of songs added.
    func addToQueue(_ items: [SonosQueueItem], after current: Int?) async throws -> Int
    /// `count` songs of the queue from place `start`, counted from 0.
    func queue(from start: Int, count: Int) async throws -> [QueueEntry]
    /// Plays a stream, such as a radio station, instead of the queue. The queue stays.
    func playStream(_ item: SonosQueueItem) async throws

    /// Bass, treble, loudness and Trueplay of this player's room.
    func soundSettings() async throws -> SoundSettings
    func change(_ setting: SoundSetting) async throws
    func device() async throws -> SonosDevice
}

/// Talks UPnP SOAP to port 1400 of a player.
@MainActor
final class SOAPSonosPlayer: SonosPlayer {
    private let address: URL
    private let transport: HTTPTransport

    init(address: URL, transport: @escaping HTTPTransport = HTTP.live) {
        self.address = address
        self.transport = transport
    }

    func zoneGroups() async throws -> [SonosGroup] {
        let response = try await call(.zoneGroupTopology, "GetZoneGroupState", [:])
        return SonosGroup.groups(fromZoneGroupState: response.value("ZoneGroupState") ?? "")
    }

    func householdID() async throws -> String {
        let response = try await call(.deviceProperties, "GetHouseholdID", [:])
        guard let id = response.value("CurrentHouseholdID") else { throw AppError("Sonos gave no household.") }
        return id
    }

    func status() async throws -> GroupStatus {
        async let volume = call(.groupRenderingControl, "GetGroupVolume")
        async let transport = call(.avTransport, "GetTransportInfo")
        async let position = call(.avTransport, "GetPositionInfo")
        async let settings = call(.avTransport, "GetTransportSettings")
        async let media = call(.avTransport, "GetMediaInfo")
        return try await GroupStatus(volume: volume, transport: transport, position: position,
                                     settings: try? settings, media: try? media, player: address)
    }

    func adjustVolume(by adjustment: Int) async throws -> Int {
        // The snapshot keeps the volume ratios between the rooms of a group.
        _ = try await call(.groupRenderingControl, "SnapshotGroupVolume")
        let response = try await call(.groupRenderingControl, "SetRelativeGroupVolume",
                                      ["InstanceID": "0", "Adjustment": String(adjustment)])
        return response.value("NewVolume").flatMap(Int.init) ?? 0
    }

    func setVolume(_ volume: Int) async throws {
        _ = try await call(.groupRenderingControl, "SnapshotGroupVolume")
        _ = try await call(.groupRenderingControl, "SetGroupVolume",
                           ["InstanceID": "0", "DesiredVolume": String(volume)])
    }

    /// Sonos answers Play on a radio stream only once it has connected to it, which
    /// took 5.9 seconds for BNR: give it longer than the other actions.
    func play() async throws {
        _ = try await call(.avTransport, "Play", ["InstanceID": "0", "Speed": "1"], timeout: 20)
    }
    func pause() async throws { _ = try await call(.avTransport, "Pause") }
    func next() async throws { _ = try await call(.avTransport, "Next") }
    func previous() async throws { _ = try await call(.avTransport, "Previous") }

    func seek(toTrack number: Int) async throws {
        _ = try await call(.avTransport, "Seek", ["InstanceID": "0", "Unit": "TRACK_NR", "Target": String(number)])
    }

    func removeFromQueue(_ index: Int) async throws {
        // UpdateID 0 skips Sonos's check that the queue didn't change in between.
        _ = try await call(.avTransport, "RemoveTrackFromQueue",
                           ["InstanceID": "0", "ObjectID": "Q:0/\(index + 1)", "UpdateID": "0"])
    }

    func seek(to seconds: TimeInterval) async throws {
        _ = try await call(.avTransport, "Seek",
                           ["InstanceID": "0", "Unit": "REL_TIME", "Target": SonosTime.string(seconds)])
    }

    func setPlayMode(_ mode: PlayMode) async throws {
        _ = try await call(.avTransport, "SetPlayMode", ["InstanceID": "0", "NewPlayMode": mode.sonosValue])
    }

    func replaceQueue(with items: [SonosQueueItem], groupID: String) async throws -> Int {
        _ = try await call(.avTransport, "RemoveAllTracksFromQueue")
        let added = try await addToQueue(items, after: nil)
        _ = try await call(.avTransport, "SetAVTransportURI",
                           ["InstanceID": "0", "CurrentURI": "x-rincon-queue:\(groupID)#0", "CurrentURIMetaData": ""])
        return added
    }

    func addToQueue(_ items: [SonosQueueItem], after current: Int?) async throws -> Int {
        var added = 0
        var position = current.map { $0 + 1 } ?? 0
        // Sonos takes at most 16 items per call.
        for start in stride(from: 0, to: items.count, by: 16) {
            let chunk = items[start..<min(start + 16, items.count)]
            let response = try await call(.avTransport, "AddMultipleURIsToQueue", [
                "InstanceID": "0", "UpdateID": "0", "NumberOfURIs": String(chunk.count),
                "EnqueuedURIs": chunk.map(\.uri).joined(separator: " "),
                "EnqueuedURIsMetaData": chunk.map(\.metadata).joined(separator: " "),
                "ContainerURI": "", "ContainerMetaData": "",
                "DesiredFirstTrackNumberEnqueued": String(position), "EnqueueAsNext": current == nil ? "0" : "1",
            ])
            let count = response.value("NumTracksAdded").flatMap(Int.init) ?? 0
            added += count
            if position > 0 { position += count }
        }
        return added
    }

    func queue(from start: Int, count: Int) async throws -> [QueueEntry] {
        let response = try await call(.contentDirectory, "Browse", [
            "ObjectID": "Q:0", "BrowseFlag": "BrowseDirectChildren",
            "Filter": "dc:title,dc:creator,upnp:albumArtURI,res", "StartingIndex": String(start),
            "RequestedCount": String(count), "SortCriteria": "",
        ])
        return QueueEntry.entries(fromDIDL: response.value("Result") ?? "", player: address, startingAt: start)
    }

    func playStream(_ item: SonosQueueItem) async throws {
        _ = try await call(.avTransport, "SetAVTransportURI",
                           ["InstanceID": "0", "CurrentURI": item.uri, "CurrentURIMetaData": item.metadata])
        try await play()
    }

    func soundSettings() async throws -> SoundSettings {
        async let bass = call(.renderingControl, "GetBass")
        async let treble = call(.renderingControl, "GetTreble")
        async let loudness = call(.renderingControl, "GetLoudness", ["InstanceID": "0", "Channel": "Master"])
        async let calibration = call(.renderingControl, "GetRoomCalibrationStatus")
        return try await SoundSettings(bass: bass, treble: treble, loudness: loudness, calibration: try? calibration)
    }

    func change(_ setting: SoundSetting) async throws {
        switch setting {
        case .bass(let value):
            _ = try await call(.renderingControl, "SetBass", ["InstanceID": "0", "DesiredBass": String(value)])
        case .treble(let value):
            _ = try await call(.renderingControl, "SetTreble", ["InstanceID": "0", "DesiredTreble": String(value)])
        case .loudness(let on):
            _ = try await call(.renderingControl, "SetLoudness",
                               ["InstanceID": "0", "Channel": "Master", "DesiredLoudness": on ? "1" : "0"])
        }
    }

    func device() async throws -> SonosDevice {
        let request = URLRequest(url: address.appending(path: "/xml/device_description.xml"), timeoutInterval: 4)
        let (data, status) = try await transport(request)
        guard status == 200, let description = XMLNode.parse(data) else {
            throw AppError("\(address.host() ?? "The speaker") gave no device description.")
        }
        return SonosDevice(description: description, address: address)
    }

    // MARK: SOAP

    private func call(_ service: Service, _ action: String,
                      _ arguments: KeyValuePairs<String, String> = ["InstanceID": "0"],
                      timeout: TimeInterval = 4) async throws -> XMLNode {
        let body = arguments.map { "<\($0.key)>\($0.value.xmlEscaped)</\($0.key)>" }.joined()
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>\
        <u:\(action) xmlns:u="\(service.urn)">\(body)</u:\(action)>\
        </s:Body></s:Envelope>
        """
        var request = URLRequest(url: address.appending(path: service.path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(envelope.utf8)

        let (data, status) = try await transport(request)
        let response = XMLNode.parse(data)
        guard status == 200, let response else {
            let code = response?.value("errorCode").flatMap(Int.init)
            throw AppError("\(action) failed on \(address.host() ?? "the speaker")\(code.map { " (error \($0))" } ?? "")",
                           code: code)
        }
        return response
    }

    /// The UPnP services of a player that the app uses.
    private enum Service {
        case avTransport, contentDirectory, deviceProperties, groupRenderingControl, renderingControl, zoneGroupTopology

        var path: String {
            switch self {
            case .avTransport: "/MediaRenderer/AVTransport/Control"
            case .contentDirectory: "/MediaServer/ContentDirectory/Control"
            case .deviceProperties: "/DeviceProperties/Control"
            case .groupRenderingControl: "/MediaRenderer/GroupRenderingControl/Control"
            case .renderingControl: "/MediaRenderer/RenderingControl/Control"
            case .zoneGroupTopology: "/ZoneGroupTopology/Control"
            }
        }

        var urn: String {
            switch self {
            case .avTransport: "urn:schemas-upnp-org:service:AVTransport:1"
            case .contentDirectory: "urn:schemas-upnp-org:service:ContentDirectory:1"
            case .deviceProperties: "urn:schemas-upnp-org:service:DeviceProperties:1"
            case .groupRenderingControl: "urn:schemas-upnp-org:service:GroupRenderingControl:1"
            case .renderingControl: "urn:schemas-upnp-org:service:RenderingControl:1"
            case .zoneGroupTopology: "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
            }
        }
    }
}

extension SonosPlayer {
    /// The first 200 songs of the queue.
    func queue() async throws -> [QueueEntry] { try await queue(from: 0, count: 200) }
}
