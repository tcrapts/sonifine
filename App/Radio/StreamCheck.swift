import Foundation

/// Checks a custom stream before it becomes a favourite: the address must be
/// http or https, and it must answer with audio. The check reads the answer's
/// headers and first bytes only; nothing plays.
enum StreamCheck {
    /// The stream address the user typed, or why it isn't one.
    static func address(_ text: String) throws -> URL {
        guard let url = webAddress(text) else {
            throw AppError("Enter the stream's address, starting with https:// or http://.")
        }
        return url
    }

    /// An http or https address with a host, such as a stream or a logo; nil for other text.
    static func webAddress(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()),
              url.host()?.isEmpty == false else { return nil }
        return url
    }

    /// Playlist formats, which hold a stream's address instead of its audio.
    private static let playlistTypes = ["audio/x-mpegurl", "audio/mpegurl", "application/vnd.apple.mpegurl",
                                        "application/x-mpegurl", "audio/x-scpls", "audio/scpls"]

    /// Why the answer to a stream request is no audio stream, or nil when it is one.
    static func problem(status: Int, contentType: String?) -> String? {
        guard (200..<300).contains(status) else { return "The address answers with error \(status)." }
        let type = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if playlistTypes.contains(type) {
            return "This address is a playlist (\(type)). Use the stream address inside it."
        }
        guard type.hasPrefix("audio/") || type == "application/ogg" else {
            return type.isEmpty ? "This address gives no audio." : "This address gives \(type), not audio."
        }
        return nil
    }

    /// Asks the address for its first bytes. Returns why it is no audio stream,
    /// or nil when it is one. iOS lets the app ask https addresses only; an http
    /// stream is taken as it is, and the speaker shows whether it plays.
    static func problem(with url: URL) async -> String? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: URLRequest(url: url, timeoutInterval: 8))
            defer { bytes.task.cancel() }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let problem = problem(status: status, contentType: response.mimeType) { return problem }
            for try await _ in bytes { break }
            return nil
        } catch {
            return "The address doesn't answer: \(error.localizedDescription)"
        }
    }
}
