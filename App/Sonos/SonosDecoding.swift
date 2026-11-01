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
                  let address = coordinator.attributes["Location"].flatMap(URL.init(string:))?.sonosPlayerURL
            else { return nil }
            // A stereo pair is two players with one room name.
            let otherRooms = Set(visible.compactMap { $0.attributes["ZoneName"] }).subtracting([roomName])
            return SonosGroup(
                id: coordinatorID,
                name: otherRooms.isEmpty ? roomName : "\(roomName) + \(otherRooms.count)",
                coordinator: address,
                roomIDs: visible.compactMap { $0.attributes["UUID"] })
        }
        return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
    /// The songs in the DIDL-Lite `Result` of `Browse Q:0`.
    static func entries(fromDIDL didl: String, player: URL) -> [QueueEntry] {
        guard let root = XMLNode.parse(didl) else { return [] }
        return root.descendants(named: "item").enumerated().map { index, item in
            QueueEntry(id: index,
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
