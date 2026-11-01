import Foundation

/// How a list of songs is sorted, as in Spotify's sort sheet: choose a key, and
/// choose it again to turn the direction.
struct SongOrder: Equatable, RawRepresentable {
    enum Key: String, CaseIterable {
        /// The order of the playlist itself; Liked Songs come newest first.
        case custom, title, artist, album, added

        var label: String {
            switch self {
            case .custom: "Custom order"
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .added: "Recently added"
            }
        }
    }

    var key: Key
    /// A to Z, or oldest first for `added`.
    var ascending: Bool

    static let custom = SongOrder(key: .custom, ascending: true)
    static let newestFirst = SongOrder(key: .added, ascending: false)

    init(key: Key, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// The choice after tapping `key`: the same key turns the direction, a new one
    /// starts at A or at the newest song.
    func choosing(_ key: Key) -> SongOrder {
        if key == self.key { return key == .custom ? self : SongOrder(key: key, ascending: !ascending) }
        return SongOrder(key: key, ascending: key != .added)
    }

    /// The songs in this order. Equal songs keep their order; songs without a
    /// date or album go last.
    func apply(to songs: [SpotifyItem]) -> [SpotifyItem] {
        guard key != .custom else { return songs }
        return songs.enumerated().sorted { a, b in
            switch compare(a.element, b.element) {
            case .orderedSame: a.offset < b.offset
            case .orderedAscending: true
            case .orderedDescending: false
            }
        }.map(\.element)
    }

    private func compare(_ a: SpotifyItem, _ b: SpotifyItem) -> ComparisonResult {
        switch key {
        case .custom: return .orderedSame
        case .title: return directed(a.name.localizedStandardCompare(b.name))
        case .artist: return directed(a.subtitle.localizedStandardCompare(b.subtitle))
        case .album: return missingLast(a.album, b.album) { directed($0.localizedStandardCompare($1)) }
        case .added: return missingLast(a.addedAt, b.addedAt) { directed($0 < $1 ? .orderedAscending : $0 > $1 ? .orderedDescending : .orderedSame) }
        }
    }

    private func directed(_ result: ComparisonResult) -> ComparisonResult {
        guard !ascending else { return result }
        return result == .orderedAscending ? .orderedDescending : result == .orderedDescending ? .orderedAscending : .orderedSame
    }

    private func missingLast<T>(_ a: T?, _ b: T?, _ compare: (T, T) -> ComparisonResult) -> ComparisonResult {
        switch (a, b) {
        case let (a?, b?): compare(a, b)
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        }
    }

    // MARK: Stored as text in the settings

    init?(rawValue: String) {
        let parts = rawValue.split(separator: " ")
        guard parts.count == 2, let key = Key(rawValue: String(parts[0])) else { return nil }
        self.init(key: key, ascending: parts[1] == "ascending")
    }

    var rawValue: String { "\(key.rawValue) \(ascending ? "ascending" : "descending")" }
}
