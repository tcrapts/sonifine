import Foundation

/// Sonos Radio, Sonos's own free radio (service 303): its home page, its
/// categories and a search for stations. Browsing and searching need no sign-in;
/// playing goes through the household's Sonos Radio account on the speaker. See ADR 0005.
@MainActor
final class SonosRadioService {
    private static let service = URL(string: "https://sali.sonos.superhi.fi/smapi")!
    private static let browse = URL(string: "https://sali.sonos.superhi.fi/browse/v1")!

    private let transport: HTTPTransport

    init(transport: @escaping HTTPTransport = HTTP.live) {
        self.transport = transport
    }

    /// The rows of the Sonos Radio home, such as "Trending Now", and last
    /// "Browse Radio" with its categories: music, news and talk, sports, places.
    func home() async throws -> [RadioShelf] {
        var request = URLRequest(url: Self.browse, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let reply = try await transport(request)
        guard reply.status == 200 else { throw AppError("Sonos Radio didn't load (\(reply.status)).") }
        let page = try JSONDecoder().decode(SMAPIBrowsePage.self, from: reply.data)
        return page.views.compactMap { view in
            let items = view.items?.compactMap(\.radioItem) ?? []
            guard !items.isEmpty else { return nil }
            return RadioShelf(id: view.id.objectId, title: view.content.details?.name ?? "", items: items)
        }
    }

    /// The stations and categories in a category, up to 100.
    func items(in category: RadioItem) async throws -> [RadioItem] {
        let response = try await call("getMetadata", "<id>\(category.id.xmlEscaped)</id><index>0</index><count>100</count>")
        return Self.items(in: response)
    }

    /// The stations whose name or description matches `term`, Sonos Radio's own first.
    func search(_ term: String) async throws -> [RadioItem] {
        let response = try await call("search", "<id>stations</id><term>\(term.xmlEscaped)</term><index>0</index><count>30</count>")
        return Self.items(in: response)
    }

    /// The stations (`mediaMetadata`) and categories (`mediaCollection`) of an answer, in its order.
    private static func items(in response: XMLNode) -> [RadioItem] {
        func entries(_ node: XMLNode) -> [XMLNode] {
            node.children.flatMap { ["mediaMetadata", "mediaCollection"].contains($0.name) ? [$0] : entries($0) }
        }
        return entries(response).compactMap { entry in
            guard let id = entry.value("id"), let title = entry.value("title") else { return nil }
            let image = entry.value("albumArtURI") ?? entry.value("logo")
            return RadioItem(id: id, itemType: entry.value("itemType"), name: title,
                             subtitle: entry.value("artist") ?? "", imageURL: image.flatMap(originalImage))
        }
    }

    /// Search gives a logo through Sonos's image proxy at 60 pixels wide; the
    /// `image` parameter holds the original, which is sharp on a card.
    private static func originalImage(_ string: String) -> URL? {
        guard let url = URL(string: string) else { return nil }
        let original = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "image" }?.value.flatMap(URL.init(string:))
        return original ?? url
    }

    private func call(_ action: String, _ body: String) async throws -> XMLNode {
        let reply = try await transport(SMAPI.request(Self.service, action: action, body: body))
        guard reply.status == 200, let response = XMLNode.parse(reply.data) else {
            throw AppError("Sonos Radio: \(action) failed (\(reply.status)).")
        }
        return response
    }
}

private extension SMAPIBrowsePage.Item {
    var radioItem: RadioItem? {
        guard let details = content.details, let name = details.name else { return nil }
        return RadioItem(id: id.objectId, itemType: details.type, name: name, subtitle: details.artist?.name ?? "",
                         imageURL: details.imageUrl.flatMap(URL.init(string:)))
    }
}
