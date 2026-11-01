import Foundation
@testable import Sonifine

/// Answers requests from a list of recorded responses and keeps every request.
@MainActor
final class RecordedTransport {
    typealias Answer = (status: Int, body: String)
    private(set) var requests: [URLRequest] = []
    private var answers: [(matches: (URLRequest) -> Bool, answer: Answer)] = []

    /// Answers the next request that `matches` (once per call of `answer`).
    func answer(_ answer: Answer, when matches: @escaping (URLRequest) -> Bool) {
        answers.append((matches, answer))
    }

    func answer(soapAction action: String, _ answer: Answer) {
        self.answer(answer) { $0.soapAction == action }
    }

    var transport: HTTPTransport {
        { [self] request in
            requests.append(request)
            guard let index = answers.firstIndex(where: { $0.matches(request) }) else {
                return (Data("no recorded answer".utf8), 599)
            }
            let answer = answers.remove(at: index).answer
            return (Data(answer.body.utf8), answer.status)
        }
    }

    func count(soapAction action: String) -> Int { requests.filter { $0.soapAction == action }.count }
}

extension URLRequest {
    /// `"urn:…:AVTransport:1#Play"` → `Play`
    var soapAction: String? {
        value(forHTTPHeaderField: "SOAPACTION")?.split(separator: "#").last.map { $0.replacingOccurrences(of: "\"", with: "") }
    }

    var bodyText: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }
}

final class MemorySecrets: SecretStore {
    var values: [String: String] = [:]
    func read(_ key: String) -> String? { values[key] }
    func save(_ value: String, for key: String) -> Bool { values[key] = value; return true }
    func delete(_ key: String) { values[key] = nil }
}

/// A Sonos UPnP answer, as a player sends it.
func soapAnswer(_ action: String, _ body: String) -> String {
    """
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>\
    <u:\(action)Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">\(body)</u:\(action)Response>\
    </s:Body></s:Envelope>
    """
}

func xmlEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

func xml(_ text: String) -> XMLNode { XMLNode.parse(text)! }

func song(_ id: String, _ name: String = "Song") -> SpotifyItem {
    SpotifyItem(uri: SpotifyURI("spotify:track:\(id)")!, name: name, subtitle: "", imageURL: nil)
}

/// A Sonos player that keeps what the controller asks of it.
@MainActor
final class FakeSonosPlayer: SonosPlayer {
    var groups: [SonosGroup] = []
    var status = GroupStatus()
    var queueEntries: [QueueEntry] = []
    var tracksAdded = 1
    var failure: AppError?
    /// How long `status()` takes, to let a user action overtake a poll.
    var statusDelay: Duration = .zero

    private(set) var adjustments: [Int] = []
    private(set) var queuedItems: [SonosQueueItem] = []
    private(set) var seeks: [Int] = []
    private(set) var playModes: [PlayMode] = []
    private(set) var plays = 0

    func zoneGroups() async throws -> [SonosGroup] { groups }
    func householdID() async throws -> String { "Sonos_Household" }

    func status() async throws -> GroupStatus {
        let answer = status
        try await Task.sleep(for: statusDelay)
        return answer
    }

    func adjustVolume(by adjustment: Int) async throws -> Int {
        adjustments.append(adjustment)
        status.volume += adjustment
        return status.volume
    }

    func setVolume(_ volume: Int) async throws { status.volume = volume }
    func play() async throws { plays += 1 }
    func pause() async throws {}
    func next() async throws {}
    func previous() async throws {}
    func seek(toTrack number: Int) async throws { seeks.append(number) }
    func seek(to seconds: TimeInterval) async throws {}
    func setPlayMode(_ mode: PlayMode) async throws { playModes.append(mode) }

    func replaceQueue(with items: [SonosQueueItem], groupID: String) async throws -> Int {
        if let failure { throw failure }
        queuedItems = items
        return tracksAdded
    }

    func queue() async throws -> [QueueEntry] { queueEntries }
}
