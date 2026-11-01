import Foundation

/// An XML document as a small tree, with element names reduced to their local
/// name (`u:GetPositionInfoResponse` → `GetPositionInfoResponse`).
///
/// Sonos and its Spotify service answer in SOAP, often with more XML escaped
/// inside an element. Reading every answer through this one tree keeps prefix
/// and entity handling in one place.
struct XMLNode {
    let name: String
    let attributes: [String: String]
    fileprivate(set) var text = ""
    fileprivate(set) var children: [XMLNode] = []

    /// The root element, or nil when the data is not XML.
    static func parse(_ data: Data) -> XMLNode? {
        let builder = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    static func parse(_ string: String) -> XMLNode? { parse(Data(string.utf8)) }

    /// Every element below this one with the local name `name`, in document order.
    func descendants(named name: String) -> [XMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(named: name) }
    }

    func first(_ name: String) -> XMLNode? {
        for child in children {
            if child.name == name { return child }
            if let match = child.first(name) { return match }
        }
        return nil
    }

    /// The text of the first element named `name` below this one, when not empty.
    func value(_ name: String) -> String? {
        let text = first(name)?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

private final class TreeBuilder: NSObject, XMLParserDelegate {
    var root: XMLNode?
    private var stack: [XMLNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let localName = elementName.split(separator: ":").last.map(String.init) ?? elementName
        stack.append(XMLNode(name: localName, attributes: attributes))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let node = stack.removeLast()
        if stack.isEmpty {
            root = node
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }
}
