import Foundation

/// Something from Spotify: a playlist, album, song or artist.
struct SpotifyItem: Identifiable, Hashable {
    let uri: SpotifyURI
    let name: String
    let subtitle: String
    let imageURL: URL?
    /// The album of a song, when Spotify gave it.
    var album: String? = nil
    /// When the song was added to the playlist or to Liked Songs it was loaded from.
    var addedAt: Date? = nil

    var id: String { uri.description }
    var kind: SpotifyURI.Kind { uri.kind }
    var isTrack: Bool { kind == .track }
    /// Playlists, albums and artists open on a page of their own.
    var opens: Bool { kind == .playlist || kind == .album || kind == .artist }
}

/// A titled row of the Spotify home, such as "Jump back in" or "Your top mixes".
struct HomeShelf: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [SpotifyItem]
}

/// Search results per kind, in the order the Search screen shows them.
struct SpotifySearchResults: Equatable {
    var tracks: [SpotifyItem] = []
    var artists: [SpotifyItem] = []
    var albums: [SpotifyItem] = []
    var playlists: [SpotifyItem] = []
}

/// What a tap asks Sonos to play.
enum PlayRequest: Equatable {
    /// Songs in this order, beginning with the one at `start`.
    case songs([SpotifyURI], start: Int, shuffle: Bool)
    /// A playlist or album, beginning with the song `start` when given.
    case collection(SpotifyURI, start: SpotifyURI?, shuffle: Bool)
    /// An artist's best known songs; the catalog looks them up first.
    case artist(SpotifyItem, shuffle: Bool)
    /// A Sonos Radio station, which plays instead of the queue.
    case station(RadioItem)

    /// The request for a tap on `item`.
    ///
    /// - Parameters:
    ///   - list: The songs shown with it. A song plays with the songs of its list.
    ///   - collection: The playlist or album the list belongs to. A song then
    ///     plays inside it, so the rest of the playlist follows.
    /// - Returns: nil for items Sonos can't play, such as a station or a podcast.
    static func tap(_ item: SpotifyItem, in list: [SpotifyItem] = [], collection: SpotifyItem? = nil,
                    shuffle: Bool = false) -> PlayRequest? {
        switch item.kind {
        case .track:
            if let collection, collection.kind == .playlist || collection.kind == .album {
                return .collection(collection.uri, start: item.uri, shuffle: shuffle)
            }
            let songs = list.filter(\.isTrack).map(\.uri)
            guard let start = songs.firstIndex(of: item.uri) else {
                return .songs([item.uri], start: 0, shuffle: shuffle)
            }
            return .songs(songs, start: start, shuffle: shuffle)
        case .playlist, .album:
            return .collection(item.uri, start: nil, shuffle: shuffle)
        case .artist:
            return .artist(item, shuffle: shuffle)
        case .other:
            return nil
        }
    }
}
