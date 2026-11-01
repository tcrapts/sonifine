import Foundation

/// The Sonos Music API (SMAPI) that music services offer Sonos: SOAP actions
/// such as `getMetadata` and `search`, and a JSON home page at `/v1/browse`.
/// `SonosSpotifyService` and `SonosRadioService` both speak it.
enum SMAPI {
    static let namespace = "http://www.sonos.com/Services/1.1"

    /// A SOAP request for `action` with `body` as its arguments. `credentials` is the
    /// content of the `credentials` header; a service that allows anonymous calls needs none.
    static func request(_ endpoint: URL, action: String, body: String, credentials: String? = nil) -> URLRequest {
        let header = credentials.map { "<s:Header><credentials xmlns=\"\(namespace)\">\($0)</credentials></s:Header>" } ?? ""
        let envelope = """
        <?xml version="1.0" encoding="utf-8"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">\(header)\
        <s:Body><\(action) xmlns="\(namespace)">\(body)</\(action)></s:Body></s:Envelope>
        """
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(namespace)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data(envelope.utf8)
        return request
    }
}

/// The JSON of a service's `GET /v1/browse`: views (rows) of items, each with an
/// object ID and a container or item that describes it.
struct SMAPIBrowsePage: Decodable {
    struct ObjectID: Decodable { let objectId: String }
    struct Details: Decodable {
        struct Artist: Decodable { let name: String? }
        let name: String?
        let type: String?
        let imageUrl: String?
        let artist: Artist?
    }
    struct Content: Decodable {
        let container: Details?
        let item: Details?

        var details: Details? { container ?? item }
    }
    struct Item: Decodable {
        let id: ObjectID
        let content: Content
    }
    struct View: Decodable {
        let id: ObjectID
        let content: Content
        let items: [Item]?
    }
    let views: [View]
}
