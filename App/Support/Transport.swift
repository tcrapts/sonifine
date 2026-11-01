import Foundation

/// Sends an HTTP request and returns the body and status code. Every network
/// call of the app goes through one, so tests can answer with recorded responses.
typealias HTTPTransport = (URLRequest) async throws -> (data: Data, status: Int)

enum HTTP {
    static let live: HTTPTransport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
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
