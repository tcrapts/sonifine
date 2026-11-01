import Foundation

/// The UPnP services of a Sonos player that this app uses.
enum SonosService {
    case avTransport
    case contentDirectory
    case deviceProperties
    case groupRenderingControl
    case zoneGroupTopology

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

struct SonosError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Sends a SOAP action to a Sonos player on port 1400 and returns the text of
/// each element in the response, keyed by element name.
enum SonosSOAP {
    static func call(
        _ player: URL,
        _ service: SonosService,
        _ action: String,
        _ arguments: KeyValuePairs<String, String> = ["InstanceID": "0"]
    ) async throws -> [String: String] {
        let body = arguments.map { "<\($0.key)>\(escape($0.value))</\($0.key)>" }.joined()
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>\
        <u:\(action) xmlns:u="\(service.urn)">\(body)</u:\(action)>\
        </s:Body></s:Envelope>
        """

        var request = URLRequest(url: player.appending(path: service.path), timeoutInterval: 4)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.urn)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(envelope.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let code = ElementTextParser.parse(data)["errorCode"].map { " (error \($0))" } ?? ""
            throw SonosError(message: "\(action) failed on \(player.host() ?? "speaker")\(code)")
        }
        return ElementTextParser.parse(data)
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Collects the text content of every element, keyed by its (prefixed) name.
/// Sonos returns nested XML as escaped text, which comes out decoded here.
final class ElementTextParser: NSObject, XMLParserDelegate {
    private var values: [String: String] = [:]
    private var text = ""

    static func parse(_ data: Data) -> [String: String] {
        let delegate = ElementTextParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.values
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if values[elementName] == nil, !text.isEmpty { values[elementName] = text }
        text = ""
    }
}
