import Foundation

/// A Spotify URI such as `spotify:album:6ZG5lRT77aJ3btmArcykra`, parsed once.
/// Every form the app meets converts through it: the Web API's URIs, the Sonos
/// track URIs and the Sonos queue encoding.
struct SpotifyURI: Hashable, CustomStringConvertible {
    enum Kind: String {
        case playlist, album, track, artist
        /// A podcast, and one of its episodes.
        case show, episode
        /// Anything else Spotify offers, such as a station.
        case other
    }

    let kind: Kind
    /// The base-62 ID, such as `6ZG5lRT77aJ3btmArcykra`.
    let id: String
    /// The URI as Spotify writes it.
    let description: String

    init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "spotify", let id = parts.last, !id.isEmpty else { return nil }
        kind = parts.count == 3 ? Kind(rawValue: String(parts[1])) ?? .other : .other
        self.id = String(id)
        description = string
    }

    /// The song or podcast episode in a Sonos track URI, such as
    /// `x-sonos-spotify:spotify%3atrack%3a3AJwUDP919kvQ9QcozQPxg?sid=9&flags=8224&sn=1`.
    init?(sonosTrackURI: String) {
        let decoded = sonosTrackURI.removingPercentEncoding ?? sonosTrackURI
        for prefix in ["spotify:track:", "spotify:episode:"] {
            guard let start = decoded.range(of: prefix) else { continue }
            let id = decoded[start.upperBound...].prefix { $0.isLetter || $0.isNumber }
            self.init(prefix + id)
            return
        }
        return nil
    }

    /// How a Sonos player queues this item from its Spotify account, or nil for
    /// the kinds Sonos can't queue.
    func queueItem(account: SpotifyAccount) -> SonosQueueItem? {
        let encoded = description.replacingOccurrences(of: ":", with: "%3a")
        let itemID: String
        let upnpClass: String
        let uri: String
        switch kind {
        case .playlist:
            itemID = "1006206c" + encoded
            upnpClass = "object.container.playlistContainer"
            uri = "x-rincon-cpcontainer:" + itemID
        case .album:
            itemID = "1004206c" + encoded
            upnpClass = "object.container.album.musicAlbum"
            uri = "x-rincon-cpcontainer:" + itemID
        case .track:
            itemID = "10032020" + encoded
            upnpClass = "object.item.audioItem.musicTrack"
            uri = "x-sonos-spotify:\(encoded)?sid=\(account.serviceID)&flags=8224&sn=\(account.accountNumber)"
        case .episode:
            // As SoCo queues an episode; the speaker resolves this URI through the account.
            itemID = "00032020" + encoded
            upnpClass = "object.item.audioItem.musicTrack"
            uri = "x-sonos-spotify:\(encoded)?sid=\(account.serviceID)&flags=8224&sn=\(account.accountNumber)"
        case .artist, .show, .other:
            return nil
        }
        return SonosQueueItem(uri: uri, itemID: itemID, upnpClass: upnpClass, serviceType: account.serviceType)
    }
}

/// The Spotify account in the Sonos app: service `sid` and account number `sn`,
/// as in `x-sonos-spotify:…?sid=9&flags=0&sn=1`.
struct SpotifyAccount: Equatable {
    let serviceID: String
    let accountNumber: String

    static let `default` = SpotifyAccount(serviceID: "9", accountNumber: "1")

    init(serviceID: String, accountNumber: String) {
        self.serviceID = serviceID
        self.accountNumber = accountNumber
    }

    /// Reads the account from a Spotify track URI that Sonos plays.
    init?(sonosTrackURI: String) {
        guard sonosTrackURI.hasPrefix("x-sonos-spotify:"),
              let query = URLComponents(string: sonosTrackURI)?.queryItems,
              let serviceID = query.first(where: { $0.name == "sid" })?.value,
              let accountNumber = query.first(where: { $0.name == "sn" })?.value else { return nil }
        self.init(serviceID: serviceID, accountNumber: accountNumber)
    }

    /// Sonos names a music service by its type: service ID × 256 + 7.
    var serviceType: Int { (Int(serviceID) ?? 9) * 256 + 7 }
}
