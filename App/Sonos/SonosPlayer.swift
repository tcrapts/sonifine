import Foundation

/// One Sonos player on the network, in domain terms. Group operations go to a
/// coordinator; `zoneGroups()` and `householdID()` work on any player.
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
    func seek(to seconds: TimeInterval) async throws
    func setPlayMode(_ mode: PlayMode) async throws

    /// Empties the queue, fills it with `items` and makes the group play from it.
    /// Returns the number of songs added; a playlist or album counts as one.
    func replaceQueue(with items: [SonosQueueItem], groupID: String) async throws -> Int
    /// Adds `items` to the queue: right after `current` (counted from 1) for
    /// Play Next, or at the end. Returns the number of songs added.
    func addToQueue(_ items: [SonosQueueItem], after current: Int?) async throws -> Int
    func queue() async throws -> [QueueEntry]
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
        return try await GroupStatus(volume: volume, transport: transport, position: position,
                                     settings: try? settings, player: address)
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

    func play() async throws { _ = try await call(.avTransport, "Play", ["InstanceID": "0", "Speed": "1"]) }
    func pause() async throws { _ = try await call(.avTransport, "Pause") }
    func next() async throws { _ = try await call(.avTransport, "Next") }
    func previous() async throws { _ = try await call(.avTransport, "Previous") }

    func seek(toTrack number: Int) async throws {
        _ = try await call(.avTransport, "Seek", ["InstanceID": "0", "Unit": "TRACK_NR", "Target": String(number)])
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

    func queue() async throws -> [QueueEntry] {
        let response = try await call(.contentDirectory, "Browse", [
            "ObjectID": "Q:0", "BrowseFlag": "BrowseDirectChildren",
            "Filter": "dc:title,dc:creator,upnp:albumArtURI,res", "StartingIndex": "0",
            "RequestedCount": "200", "SortCriteria": "",
        ])
        return QueueEntry.entries(fromDIDL: response.value("Result") ?? "", player: address)
    }

    // MARK: SOAP

    private func call(_ service: Service, _ action: String,
                      _ arguments: KeyValuePairs<String, String> = ["InstanceID": "0"]) async throws -> XMLNode {
        let body = arguments.map { "<\($0.key)>\(Self.escape($0.value))</\($0.key)>" }.joined()
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>\
        <u:\(action) xmlns:u="\(service.urn)">\(body)</u:\(action)>\
        </s:Body></s:Envelope>
        """
        var request = URLRequest(url: address.appending(path: service.path), timeoutInterval: 4)
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

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The UPnP services of a player that the app uses.
    private enum Service {
        case avTransport, contentDirectory, deviceProperties, groupRenderingControl, zoneGroupTopology

        var path: String {
            switch self {
            case .avTransport: "/MediaRenderer/AVTransport/Control"
            case .contentDirectory: "/MediaServer/ContentDirectory/Control"
            case .deviceProperties: "/DeviceProperties/Control"
            case .groupRenderingControl: "/MediaRenderer/GroupRenderingControl/Control"
            case .zoneGroupTopology: "/ZoneGroupTopology/Control"
            }
        }

        var urn: String {
            switch self {
            case .avTransport: "urn:schemas-upnp-org:service:AVTransport:1"
            case .contentDirectory: "urn:schemas-upnp-org:service:ContentDirectory:1"
            case .deviceProperties: "urn:schemas-upnp-org:service:DeviceProperties:1"
            case .groupRenderingControl: "urn:schemas-upnp-org:service:GroupRenderingControl:1"
            case .zoneGroupTopology: "urn:schemas-upnp-org:service:ZoneGroupTopology:1"
            }
        }
    }
}
