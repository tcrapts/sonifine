import Foundation

/// Something a list shows: what its search matches, its sort compares and its
/// filter tells apart. Songs, playlists, albums, podcasts, episodes and stations.
protocol Listable: Identifiable {
    var name: String { get }
    /// The line under the name: the artist of a song, the owner of a playlist.
    var subtitle: String { get }
    /// The album of a song.
    var album: String? { get }
    /// When the item was added to the list it was loaded from.
    var addedAt: Date? { get }
    /// When a podcast episode came out.
    var released: Date? { get }
    /// The kind in the plural, as a filter chip names it, such as "Songs".
    var kindName: String { get }
}

extension Listable {
    var album: String? { nil }
    var addedAt: Date? { nil }
    var released: Date? { nil }
}

extension SpotifyItem: Listable {
    var released: Date? { episode?.released }

    var kindName: String {
        switch kind {
        case .track: "Songs"
        case .episode: "Episodes"
        case .playlist: "Playlists"
        case .album: "Albums"
        case .artist: "Artists"
        case .show: "Podcasts"
        case .other: "Other"
        }
    }
}

extension RadioItem: Listable {
    var kindName: String { isStation ? "Stations" : "Categories" }
}

/// How a list is sorted, as in Spotify's sort sheet: choose a key, and choose it
/// again to turn the direction.
struct ListOrder: Equatable, RawRepresentable {
    enum Key: String, CaseIterable {
        /// The order the list came in: a playlist's own, Liked Songs newest first.
        case custom, title, artist, album, added, released

        var label: String {
            switch self {
            case .custom: "Custom order"
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .added: "Recently added"
            case .released: "Release date"
            }
        }

        /// Dates start with the newest, text at A.
        var startsAscending: Bool { self != .added && self != .released }
    }

    var key: Key
    /// A to Z, or oldest first for a date.
    var ascending: Bool

    static let custom = ListOrder(key: .custom, ascending: true)
    static let newestFirst = ListOrder(key: .added, ascending: false)

    init(key: Key, ascending: Bool) {
        self.key = key
        self.ascending = ascending
    }

    /// The keys of `wanted` that `items` can be sorted by: a key on the album or
    /// a date only when some item has one.
    static func keys<Item: Listable>(_ wanted: [Key], for items: [Item]) -> [Key] {
        wanted.filter { key in
            switch key {
            case .album: items.contains { $0.album != nil }
            case .added: items.contains { $0.addedAt != nil }
            case .released: items.contains { $0.released != nil }
            case .custom, .title, .artist: true
            }
        }
    }

    /// The choice after tapping `key`: the same key turns the direction, a new one
    /// starts at A or at the newest.
    func choosing(_ key: Key) -> ListOrder {
        if key == self.key { return key == .custom ? self : ListOrder(key: key, ascending: !ascending) }
        return ListOrder(key: key, ascending: key.startsAscending)
    }

    /// The items in this order. Equal items keep their order; items without a
    /// date or album go last.
    func apply<Item: Listable>(to items: [Item]) -> [Item] {
        guard key != .custom else { return items }
        return items.enumerated().sorted { a, b in
            switch compare(a.element, b.element) {
            case .orderedSame: a.offset < b.offset
            case .orderedAscending: true
            case .orderedDescending: false
            }
        }.map(\.element)
    }

    private func compare<Item: Listable>(_ a: Item, _ b: Item) -> ComparisonResult {
        switch key {
        case .custom: .orderedSame
        case .title: directed(a.name.localizedStandardCompare(b.name))
        case .artist: directed(a.subtitle.localizedStandardCompare(b.subtitle))
        case .album: missingLast(a.album, b.album) { directed($0.localizedStandardCompare($1)) }
        case .added: missingLast(a.addedAt, b.addedAt) { directed(Self.compare($0, $1)) }
        case .released: missingLast(a.released, b.released) { directed(Self.compare($0, $1)) }
        }
    }

    private static func compare(_ a: Date, _ b: Date) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
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

/// What a list shows: the items that match the search text and the chosen kind,
/// in the chosen order.
struct ListQuery: Equatable {
    var text = ""
    /// The kind chosen in the filter, such as "Stations"; nil shows every kind.
    var kind: String?
    var order = ListOrder.custom

    /// The items as the list shows them.
    func apply<Item: Listable>(to items: [Item]) -> [Item] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return order.apply(to: items.filter { item in
            (kind == nil || item.kindName == kind) && words.allSatisfy { Self.item(item, contains: $0) }
        })
    }

    /// Whether the list shows other items, or in another order, than it came with.
    /// A song then plays with the songs shown instead of inside its playlist.
    var rearranges: Bool {
        order.key != .custom || kind != nil || !text.allSatisfy(\.isWhitespace)
    }

    /// The kinds in `items`, in the order they first appear. A filter makes sense
    /// from two kinds on.
    static func kinds<Item: Listable>(in items: [Item]) -> [String] {
        var seen: Set<String> = []
        return items.map(\.kindName).filter { seen.insert($0).inserted }
    }

    /// Each word of a search matches the name, the subtitle or the album, whatever
    /// the case or accents.
    private static func item<Item: Listable>(_ item: Item, contains word: String) -> Bool {
        [item.name, item.subtitle, item.album ?? ""].contains { $0.localizedStandardContains(word) }
    }
}
