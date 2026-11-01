import Foundation

// Reading the answers of a Sonos player. Pure functions over the parsed XML, so
// recorded answers test them.

extension SonosGroup {
    /// The groups in the `ZoneGroupState` of `GetZoneGroupState`, sorted by name.
    /// A group led by an invisible player, such as a Boost or Bridge, is left out.
    static func groups(fromZoneGroupState xml: String) -> [SonosGroup] {
        guard let root = XMLNode.parse(xml) else { return [] }
        let groups = root.descendants(named: "ZoneGroup").compactMap { zoneGroup -> SonosGroup? in
            let members = zoneGroup.children.filter { $0.name == "ZoneGroupMember" }
            let visible = members.filter { $0.attributes["Invisible"] != "1" }
            guard let coordinatorID = zoneGroup.attributes["Coordinator"],
                  let coordinator = visible.first(where: { $0.attributes["UUID"] == coordinatorID }),
                  let roomName = coordinator.attributes["ZoneName"],
                  let address = coordinator.sonosAddress
            else { return nil }
            // A stereo pair is two players with one room name.
            let otherRooms = Set(visible.compactMap { $0.attributes["ZoneName"] }).subtracting([roomName])
            let rooms = ([coordinator] + visible.filter { $0.attributes["UUID"] != coordinatorID })
                .compactMap { room(of: $0, among: members) }
            return SonosGroup(
                id: coordinatorID,
                name: otherRooms.isEmpty ? roomName : "\(roomName) + \(otherRooms.count)",
                coordinator: address,
                rooms: rooms)
        }
        return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A visible member as a room, with the invisible players that share its
    /// name (a stereo partner) and its satellites (a Sub, surrounds).
    private static func room(of member: XMLNode, among members: [XMLNode]) -> SonosRoom? {
        guard let id = member.attributes["UUID"], let name = member.attributes["ZoneName"],
              let address = member.sonosAddress else { return nil }
        let partners = members.filter { $0.attributes["Invisible"] == "1" && $0.attributes["ZoneName"] == name }
        let satellites = member.children.filter { $0.name == "Satellite" }
        return SonosRoom(id: id, name: name, address: address,
                         devices: [address] + (partners + satellites).compactMap(\.sonosAddress))
    }
}

private extension XMLNode {
    /// The player address in the `Location` of a zone group member.
    var sonosAddress: URL? { attributes["Location"].flatMap(URL.init(string:))?.sonosPlayerURL }
}

extension SoundSettings {
    /// The settings from the answers to `GetBass`, `GetTreble`, `GetLoudness`
    /// and `GetRoomCalibrationStatus`.
    init(bass: XMLNode, treble: XMLNode, loudness: XMLNode, calibration: XMLNode?) {
        self.init(bass: bass.value("CurrentBass").flatMap(Int.init) ?? 0,
                  treble: treble.value("CurrentTreble").flatMap(Int.init) ?? 0,
                  loudness: loudness.value("CurrentLoudness") == "1",
                  trueplay: calibration?.value("RoomCalibrationEnabled").map { $0 == "1" })
    }
}

extension SonosDevice {
    /// The device from `/xml/device_description.xml` of the player at `address`.
    init(description: XMLNode, address: URL) {
        let device = description.first("device")
        func value(_ name: String) -> String { device?.children.first { $0.name == name }?.text ?? "" }
        let udn = value("UDN")
        self.init(id: udn.hasPrefix("uuid:") ? String(udn.dropFirst(5)) : udn,
                  name: value("displayName"),
                  model: value("modelNumber"),
                  serialNumber: value("serialNum"),
                  softwareVersion: value("softwareVersion"),
                  hardwareVersion: value("hardwareVersion"),
                  ipAddress: address.host() ?? "")
    }
}

extension GroupStatus {
    /// The status from the answers to `GetGroupVolume`, `GetTransportInfo`,
    /// `GetPositionInfo` and `GetTransportSettings`.
    init(volume: XMLNode, transport: XMLNode, position: XMLNode, settings: XMLNode?, player: URL, at date: Date = .now) {
        let trackURI = position.value("TrackURI") ?? ""
        let track = position.value("TrackMetaData").flatMap { XMLNode.parse($0) }
        let state = transport.value("CurrentTransportState")
        // Radio puts the station in the title and the song in `streamContent`.
        let stream = track?.value("streamContent")
        let title = track?.value("title").flatMap { $0.hasPrefix("x-") ? nil : $0 }

        self.init(
            volume: volume.value("CurrentVolume").flatMap(Int.init) ?? 0,
            isPlaying: state == "PLAYING" || state == "TRANSITIONING",
            position: SonosTime.seconds(position.value("RelTime")),
            duration: SonosTime.seconds(position.value("TrackDuration")),
            positionDate: date,
            title: stream ?? title ?? "",
            artist: stream != nil ? title ?? "" : track?.value("creator") ?? track?.value("album") ?? "",
            album: track?.value("album") ?? "",
            artworkURL: track?.value("albumArtURI").flatMap { URL(sonosArtwork: $0, player: player) },
            spotifyTrack: SpotifyURI(sonosTrackURI: trackURI),
            spotifyAccount: SpotifyAccount(sonosTrackURI: trackURI),
            queuePosition: position.value("Track").flatMap(Int.init) ?? 0,
            playMode: settings?.value("PlayMode").map(PlayMode.init(sonos:)) ?? .normal,
            followsAnotherGroup: trackURI.hasPrefix("x-rincon:"))
    }
}

extension QueueEntry {
    /// The songs in the DIDL-Lite `Result` of `Browse Q:0`, which began at place `start`.
    static func entries(fromDIDL didl: String, player: URL, startingAt start: Int = 0) -> [QueueEntry] {
        guard let root = XMLNode.parse(didl) else { return [] }
        return root.descendants(named: "item").enumerated().map { index, item in
            QueueEntry(id: start + index,
                       title: item.value("title") ?? "",
                       artist: item.value("creator") ?? "",
                       artworkURL: item.value("albumArtURI").flatMap { URL(sonosArtwork: $0, player: player) },
                       spotifyTrack: item.value("res").flatMap(SpotifyURI.init(sonosTrackURI:)))
        }
    }
}

extension URL {
    /// `http://192.168.1.147:1400/xml/device_description.xml` → `http://192.168.1.147:1400`
    var sonosPlayerURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host()
        components.port = port
        return components.url
    }

    /// Sonos gives cover art as a full URL or as a path on the player.
    init?(sonosArtwork uri: String, player: URL) {
        self.init(string: uri.hasPrefix("http") ? uri : player.absoluteString + uri)
    }
}
