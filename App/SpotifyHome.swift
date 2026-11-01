import Foundation
import Observation

/// A titled row on the Spotify home page, such as "Jump back in" or "Your top mixes".
struct HomeShelf: Identifiable {
    let id: String
    let title: String
    let items: [SpotifyItem]
}

/// Spotify as the Sonos system offers it: the personal home page with Daily Mix,
/// Release Radar and radio stations, and the songs inside any playlist or album.
///
/// The Spotify Web API hides Spotify's own playlists from new apps. Sonos's Spotify
/// service shows them. The app links to that service once, the way Sonos apps do
/// (AppLink): the user signs in on a Sonos web page, and the app receives its own key.
@MainActor
@Observable
final class SpotifyHome {
    private static let service = URL(string: "https://spotify-v5.ws.sonos.com/smapi")!
    private static let browse = URL(string: "https://spotify-v5.ws.sonos.com/v1/browse")!
    private static let namespace = "http://www.sonos.com/Services/1.1"

    private(set) var isLinked = false
    private(set) var shelves: [HomeShelf] = []
    /// The sign-in page to show while linking.
    private(set) var linkURL: URL?
    private(set) var errorMessage: String?

    private var token: String?
    private var key: String?

    init() {
        token = Keychain.read("sonosSpotifyToken")
        key = Keychain.read("sonosSpotifyKey")
        isLinked = token != nil
    }

    // MARK: Linking

    /// Gets a sign-in page, then waits up to ten minutes until the user has signed in.
    func link(household: Household) async {
        errorMessage = nil
        do {
            let response = try await call("getAppLink", "<householdId>\(household.id)</householdId>", household: household)
            guard let url = response["ns2:regUrl"].flatMap(URL.init(string:)),
                  let code = response["ns2:linkCode"] else {
                throw SonosError(message: "Sonos did not return a sign-in page.")
            }
            linkURL = url
            defer { linkURL = nil }

            for _ in 0..<200 {
                try await Task.sleep(for: .seconds(3))
                guard linkURL != nil else { return } // The user closed the page.
                let result = try? await call("getDeviceAuthToken", """
                    <householdId>\(household.id)</householdId><linkCode>\(code)</linkCode>\
                    <linkDeviceId>\(household.deviceID)</linkDeviceId>
                    """, household: household)
                if let result, store(result) {
                    await loadHome(household: household)
                    return
                }
            }
            errorMessage = "Signing in took too long. Try again."
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelLink() { linkURL = nil }

    func unlink() {
        Keychain.delete("sonosSpotifyToken")
        Keychain.delete("sonosSpotifyKey")
        token = nil
        key = nil
        isLinked = false
        shelves = []
    }

    /// Keeps the key from `getDeviceAuthToken` or `refreshAuthToken`. Returns whether there was one.
    private func store(_ response: [String: String]) -> Bool {
        guard let newToken = response["ns2:authToken"], let newKey = response["ns2:privateKey"] else { return false }
        token = newToken
        key = newKey
        Keychain.save(newToken, for: "sonosSpotifyToken")
        Keychain.save(newKey, for: "sonosSpotifyKey")
        isLinked = true
        return true
    }

    // MARK: Home page

    func loadHome(household: Household) async {
        guard isLinked else { return }
        do {
            let page: BrowsePage = try await withFreshToken(household: household) { token in
                var request = URLRequest(url: Self.browse, timeoutInterval: 10)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 401 { throw TokenExpired() }
                return try JSONDecoder().decode(BrowsePage.self, from: data)
            }
            // "Your Library" links to the Library tab instead.
            shelves = page.views.filter { $0.id.objectId != "yourmusic_root" }.compactMap { view in
                let items = view.items?.compactMap(\.spotifyItem) ?? []
                guard !items.isEmpty else { return nil }
                return HomeShelf(id: view.id.objectId, title: Self.shelfTitle(view.content.container?.name ?? ""), items: items)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Spotify greets in the time of its own clock, which runs hours off the iPhone's.
    /// The screen title greets in local time, so the greeting row is named after its contents.
    private static func shelfTitle(_ name: String) -> String {
        let greetings = ["good morning", "good afternoon", "good evening", "good night",
                         "goedemorgen", "goedemiddag", "goedenavond", "goedenacht"]
        return greetings.contains(name.lowercased()) ? "Jump back in" : name
    }

    // MARK: Contents

    /// The songs in a playlist or album, including Spotify's own playlists.
    func tracks(of item: SpotifyItem, household: Household) async throws -> [SpotifyItem] {
        let response = try await withFreshToken(household: household) { _ in
            try await self.callRaw("getMetadata", """
                <id>\(item.uri)</id><index>0</index><count>100</count>
                """, household: household)
        }
        return SongParser.parse(response)
    }

    // MARK: SOAP

    private struct TokenExpired: Error {}

    /// Runs `request`; when the key has expired, renews it once and runs it again.
    private func withFreshToken<T>(household: Household, _ request: (String) async throws -> T) async throws -> T {
        guard let token else { throw SonosError(message: "Connect Spotify first.") }
        do {
            return try await request(token)
        } catch is TokenExpired {
            try await renewToken(household: household)
            guard let token = self.token else { throw SonosError(message: "Connect Spotify again.") }
            return try await request(token)
        }
    }

    /// Sonos services renew an expired key in the fault of the next call
    /// (`Client.TokenRefreshRequired`), which `callRaw` stores. A small call
    /// triggers that.
    private func renewToken(household: Household) async throws {
        let before = token
        do {
            _ = try await callRaw("getMetadata", "<id>root</id><index>0</index><count>1</count>", household: household)
        } catch is TokenExpired {
            // The fault carried the new key; `callRaw` has stored it.
        }
        if token == before {
            // Sonos no longer accepts this link at all.
            unlink()
            throw SonosError(message: "Connect Spotify again.")
        }
    }

    private func call(_ action: String, _ body: String, household: Household) async throws -> [String: String] {
        ElementTextParser.parse(try await callRaw(action, body, household: household))
    }

    private func callRaw(_ action: String, _ body: String, household: Household) async throws -> Data {
        let login = token.flatMap { token in key.map { key in
            "<loginToken><token>\(token)</token><key>\(key)</key><householdId>\(household.id)</householdId></loginToken>"
        } } ?? ""
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Header>\
        <credentials xmlns="\(Self.namespace)"><deviceId>\(household.deviceID)</deviceId>\
        <deviceProvider>Sonos</deviceProvider>\(login)</credentials></s:Header>\
        <s:Body><\(action) xmlns="\(Self.namespace)">\(body)</\(action)></s:Body></s:Envelope>
        """
        var request = URLRequest(url: Self.service, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(Self.namespace)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(envelope.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let fault = ElementTextParser.parse(data)
            let code = fault["faultcode"] ?? ""
            if code.contains("TokenRefreshRequired") || code.contains("AuthTokenExpired") {
                // The new key comes in the fault's details.
                let detail = fault.reduce(into: [String: String]()) { result, entry in
                    result["ns2:" + (entry.key.split(separator: ":").last.map(String.init) ?? entry.key)] = entry.value
                }
                _ = store(detail)
                throw TokenExpired()
            }
            if code.contains("NOT_LINKED_RETRY") { throw SonosError(message: "Not linked yet") }
            throw SonosError(message: "Spotify on Sonos: \(action) failed \(code)")
        }
        return data
    }
}

/// The Sonos household and a player in it, which the Sonos Spotify service needs.
struct Household {
    let id: String
    let deviceID: String
}

// MARK: Responses

private struct BrowsePage: Decodable {
    struct ObjectID: Decodable { let objectId: String }
    struct Container: Decodable {
        struct Artist: Decodable { let name: String? }
        let name: String?
        let type: String?
        let imageUrl: String?
        let artist: Artist?
    }
    struct Content: Decodable { let container: Container?; let item: Container? }
    struct Item: Decodable {
        let id: ObjectID
        let content: Content

        var spotifyItem: SpotifyItem? {
            let uri = id.objectId
            let parts = uri.split(separator: ":")
            guard parts.count == 3, parts[0] == "spotify",
                  let details = content.container ?? content.item, let name = details.name else { return nil }
            return SpotifyItem(id: String(parts[2]), uri: uri, name: name,
                               subtitle: details.artist?.name ?? details.type?.capitalized ?? "",
                               imageURL: details.imageUrl.flatMap(URL.init(string:)))
        }
    }
    struct View: Decodable {
        let id: ObjectID
        let content: Content
        let items: [Item]?
    }
    let views: [View]
}

/// Reads the songs (`mediaMetadata`) from a `getMetadata` response.
private final class SongParser: NSObject, XMLParserDelegate {
    private var songs: [SpotifyItem] = []
    private var fields: [String: String]?
    private var text = ""

    static func parse(_ data: Data) -> [SpotifyItem] {
        let delegate = SongParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.songs
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName.hasSuffix("mediaMetadata") { fields = [:] }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "mediaMetadata", let fields {
            if let uri = fields["id"], uri.hasPrefix("spotify:track:"), let title = fields["title"] {
                songs.append(SpotifyItem(id: uri, uri: uri, name: title, subtitle: fields["artist"] ?? "",
                                         imageURL: fields["albumArtURI"].flatMap(URL.init(string:))))
            }
            self.fields = nil
        } else if fields != nil, fields?[name] == nil {
            fields?[name] = text
        }
        text = ""
    }
}
