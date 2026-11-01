import Foundation

/// A set of rooms that play together. Volume and playback go to the coordinator.
struct SonosGroup: Identifiable, Hashable {
    let id: String
    let name: String
    /// The coordinator's room name; Spotify Connect lists the group under it.
    let roomName: String
    let coordinator: URL
}

/// Reads the groups from the `ZoneGroupState` XML of `GetZoneGroupState`.
final class ZoneGroupParser: NSObject, XMLParserDelegate {
    private struct Member {
        let uuid: String
        let name: String
        let player: URL
        let visible: Bool
    }

    private var groups: [SonosGroup] = []
    private var coordinatorID: String?
    private var members: [Member] = []

    static func parse(_ xml: String) -> [SonosGroup] {
        let delegate = ZoneGroupParser()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        parser.parse()
        return delegate.groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "ZoneGroup":
            coordinatorID = attributes["Coordinator"]
            members = []
        case "ZoneGroupMember":
            guard let uuid = attributes["UUID"],
                  let name = attributes["ZoneName"],
                  let location = attributes["Location"].flatMap(URL.init(string:)),
                  let player = location.sonosPlayerURL else { return }
            members.append(Member(uuid: uuid, name: name, player: player,
                                  visible: attributes["Invisible"] != "1"))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        guard elementName == "ZoneGroup",
              let coordinatorID,
              let coordinator = members.first(where: { $0.uuid == coordinatorID }) else { return }
        let others = Set(members.filter { $0.visible && $0.name != coordinator.name }.map(\.name))
        let name = others.isEmpty ? coordinator.name : "\(coordinator.name) + \(others.count)"
        groups.append(SonosGroup(id: coordinatorID, name: name, roomName: coordinator.name,
                                 coordinator: coordinator.player))
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
}
