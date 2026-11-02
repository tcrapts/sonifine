import Foundation

/// Sends an HTTP request and returns the answer. Every network call of the app
/// goes through one, so tests can answer with recorded responses.
typealias HTTPTransport = (URLRequest) async throws -> HTTPResponse

/// The answer to an HTTP request: its status code, header fields and body.
struct HTTPResponse {
    var status: Int
    /// The header fields, such as `Retry-After`. `header(_:)` finds one whatever its case.
    var headers: [String: String] = [:]
    var data: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

enum HTTP {
    static let live: HTTPTransport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let headers = (http?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { headers, field in
            if let name = field.key as? String { headers[name] = "\(field.value)" }
        }
        return HTTPResponse(status: http?.statusCode ?? 0, headers: headers, data: data)
    }

    /// True for a request that the user or the view cancelled, such as an
    /// earlier search while typing. Those are no failure to report.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// A failure with a message for the user.
struct AppError: LocalizedError, Equatable {
    let message: String
    /// The UPnP error code of a Sonos fault, such as 804 for an item it can't open.
    var code: Int?

    init(_ message: String, code: Int? = nil) {
        self.message = message
        self.code = code
    }

    var errorDescription: String? { message }
}
