import Foundation

/// Something from Sonos Radio: a station to play, or a category of stations to open.
struct RadioItem: Identifiable, Hashable {
    enum Kind {
        /// A station Sonos Radio programs itself, with an ID such as `sonos:2997`.
        case program
        /// A live station, with an ID such as `tunein:5668`.
        case stream
        /// A list of stations or more categories, such as a genre or a country.
        case category
    }

    /// The service's object ID, such as `sonos:2997`, `tunein:5668` or `/genres/en-US/NL`.
    let id: String
    let kind: Kind
    let name: String
    let subtitle: String
    let imageURL: URL?

    /// Sonos Radio marks its own stations `sonos:` and the live ones `tunein:`;
    /// anything else with no `itemType` saying so is a category.
    init?(id: String, itemType: String?, name: String, subtitle: String = "", imageURL: URL?) {
        if id.hasPrefix("sonos:") {
            kind = .program
        } else if id.hasPrefix("tunein:") {
            kind = .stream
        } else if itemType == "container" {
            kind = .category
        } else {
            return nil
        }
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.imageURL = imageURL
    }

    var isStation: Bool { kind != .category }

    /// How a Sonos player plays this station from the household's Sonos Radio
    /// account, as the Sonos app stores it in a favourite; nil for a category.
    func stream(account: RadioAccount) -> SonosQueueItem? {
        func query(flags: Int) -> String { "sid=\(RadioAccount.serviceID)&flags=\(flags)&sn=\(account.accountNumber)" }
        switch kind {
        case .program:
            // `sonos:154250` → `x-sonosapi-radio:154250?sid=303&flags=0&sn=7`
            let number = id.dropFirst("sonos:".count)
            return SonosQueueItem(uri: "x-sonosapi-radio:\(number)?\(query(flags: 0))",
                                  itemID: "000c0000\(number)", title: name,
                                  upnpClass: "object.item.audioItem.audioBroadcast", serviceType: RadioAccount.serviceType)
        case .stream:
            // `tunein:4381` → `x-sonosapi-stream:tunein%3a4381?sid=303&flags=8232&sn=7`
            let encoded = id.replacingOccurrences(of: ":", with: "%3a")
            return SonosQueueItem(uri: "x-sonosapi-stream:\(encoded)?\(query(flags: 8232))",
                                  itemID: "10092028\(encoded)", title: name,
                                  upnpClass: "object.item.audioItem.audioBroadcast", serviceType: RadioAccount.serviceType)
        case .category:
            return nil
        }
    }
}

/// A titled row of Sonos Radio, such as "Trending Now" or "Browse Radio".
struct RadioShelf: Identifiable, Equatable {
    let id: String
    let title: String
    let items: [RadioItem]
}

/// The Sonos Radio account of the household: service 303 and its account number
/// `sn`, which differs per household. The app reads it from a station that Sonos
/// plays, as in `x-sonosapi-radio:154250?sid=303&flags=0&sn=7`.
struct RadioAccount: Equatable {
    static let serviceID = "303"
    /// The service ID × 256 + 7, as Sonos names a service in DIDL metadata.
    static let serviceType = 77575

    let accountNumber: String

    /// The numbers to try when the app doesn't know the household's yet. Sonos counts
    /// accounts from 0 as services are added; Spotify is often 1, Sonos Radio 2 (as at the owner's).
    static let likely = ([2, 3, 4, 5, 6, 7, 8, 1, 0] + Array(9...20)).map { RadioAccount(accountNumber: String($0)) }

    init(accountNumber: String) {
        self.accountNumber = accountNumber
    }

    /// Reads the account from any URI Sonos plays from Sonos Radio.
    init?(sonosURI: String) {
        guard let query = URLComponents(string: sonosURI)?.queryItems,
              query.first(where: { $0.name == "sid" })?.value == Self.serviceID,
              let accountNumber = query.first(where: { $0.name == "sn" })?.value else { return nil }
        self.init(accountNumber: accountNumber)
    }
}

extension SonosQueueItem {
    /// A station's own stream, played from its address without a music service or
    /// account: `https://stream.bnr.nl/bnr_mp3_128_20` becomes
    /// `x-rincon-mp3radio://https://stream.bnr.nl/bnr_mp3_128_20`. The metadata is
    /// that of a radio address added by hand (TuneIn's type, 254 × 256 + 7, without
    /// an account). The speaker reports no artwork for such a stream, so the logo
    /// goes along; `GetMediaInfo` gives it back.
    init(directStream url: URL, title: String, logo: URL?) {
        self.init(uri: "x-rincon-mp3radio://\(url.absoluteString)", itemID: "R:0/0/0", parentID: "R:0/0",
                  title: title, upnpClass: "object.item.audioItem.audioBroadcast", artwork: logo,
                  service: "SA_RINCON65031_")
    }
}
