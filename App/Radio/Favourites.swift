import Foundation
import Observation

/// A radio station the user keeps at the top of Sonos Radio. It refers to a
/// Sonos Radio station, or it is a custom stream: the station's own address,
/// which plays without TuneIn and its ads. See ADR 0007.
struct Favourite: Identifiable, Codable, Hashable {
    enum Source: Codable, Hashable {
        /// A Sonos Radio station, by its ID, such as `tunein:4345`.
        case sonosRadio(String)
        /// A custom stream: the station's own audio address.
        case stream(URL)
    }

    var id = UUID()
    var name: String
    var logoURL: URL?
    var source: Source

    /// What a tap on the favourite plays.
    var playRequest: PlayRequest? {
        switch source {
        case .sonosRadio(let stationID):
            RadioItem(id: stationID, itemType: nil, name: name, imageURL: logoURL).map(PlayRequest.station)
        case .stream(let url):
            .stream(url, name: name, logo: logoURL)
        }
    }

    /// Where it plays from, under its name.
    var sourceLabel: String {
        switch source {
        case .sonosRadio: "Sonos Radio"
        case .stream(let url): url.host() ?? url.absoluteString
        }
    }
}

/// The user's favourite stations, in the user's order, kept on the iPhone in
/// `UserDefaults` under `radioFavourites`. The first launch fills in `seed`.
@MainActor
@Observable
final class Favourites {
    private(set) var all: [Favourite] {
        didSet { save() }
    }

    private static let key = "radioFavourites"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Favourite].self, from: $0) }
        all = saved ?? Self.seed
        if saved == nil { save() }
    }

    func add(_ favourite: Favourite) {
        all.append(favourite)
    }

    /// Replaces the favourite with the same ID, such as after the user edited it.
    func update(_ favourite: Favourite) {
        guard let index = all.firstIndex(where: { $0.id == favourite.id }) else { return }
        all[index] = favourite
    }

    func remove(_ favourite: Favourite) {
        all.removeAll { $0.id == favourite.id }
    }

    func remove(atOffsets offsets: IndexSet) {
        all.remove(atOffsets: offsets)
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        all.move(fromOffsets: offsets, toOffset: destination)
    }

    func contains(_ station: RadioItem) -> Bool {
        all.contains { $0.source == .sonosRadio(station.id) }
    }

    /// Adds a Sonos Radio station at the end, or removes it when it is a favourite already.
    func toggle(_ station: RadioItem) {
        if contains(station) {
            all.removeAll { $0.source == .sonosRadio(station.id) }
        } else if station.isStation {
            add(Favourite(name: station.name, logoURL: station.imageURL, source: .sonosRadio(station.id)))
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(all), forKey: Self.key)
    }

    /// Dutch stations as custom streams, which start in seconds. Their logos are
    /// those Sonos Radio's search gives the same stations.
    static let seed: [Favourite] = [
        ("NPO Radio 1", "https://icecast.omroep.nl/radio1-bb-mp3",
         "https://cdn-radiotime-logos.tunein.com/s17523g.png"),
        ("NPO Radio 2", "https://icecast.omroep.nl/radio2-bb-mp3",
         "https://cdn-radiotime-logos.tunein.com/s9483g.png"),
        ("BNR Nieuwsradio", "https://stream.bnr.nl/bnr_mp3_128_20",
         "https://cdn-profiles.tunein.com/s1993/images/logog.png?t=1678244726000"),
        ("NPO 3FM", "https://icecast.omroep.nl/3fm-bb-mp3",
         "https://cdn-profiles.tunein.com/s6707/images/logog.png?t=160201"),
        ("NPO Klassiek", "https://icecast.omroep.nl/radio4-bb-mp3",
         "https://cdn-profiles.tunein.com/s25548/images/logog.png?t=1673505466000"),
        ("Qmusic", "https://stream.qmusic.nl/qmusic/mp3",
         "https://cdn-profiles.tunein.com/s87683/images/logog.png?t=1"),
        ("Radio 538", "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO538.mp3",
         "https://cdn-profiles.tunein.com/s6712/images/logog.png?t=1764775854000"),
        ("Sky Radio", "https://playerservices.streamtheworld.com/api/livestream-redirect/SKYRADIO.mp3",
         "https://cdn-profiles.tunein.com/s9067/images/logog.jpg?t=1764775929000"),
        ("Radio Veronica", "https://playerservices.streamtheworld.com/api/livestream-redirect/VERONICA.mp3",
         "https://cdn-profiles.tunein.com/s6717/images/logog.jpg?t=2"),
        ("100% NL", "https://stream.100p.nl/100pctnl.mp3",
         "https://cdn-profiles.tunein.com/s76590/images/logog.jpg?t=2"),
        ("Radio 10", "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO10.mp3",
         "https://cdn-profiles.tunein.com/s16793/images/logog.jpg?t=4"),
        ("KINK", "https://playerservices.streamtheworld.com/api/livestream-redirect/KINK.mp3",
         "https://cdn-profiles.tunein.com/s210430/images/logog.jpg?t=1694089798000"),
        ("SLAM!", "https://stream.slam.nl/slam_mp3",
         "https://cdn-profiles.tunein.com/s67814/images/logog.png?t=1757442135000"),
    ].map { name, stream, logo in
        Favourite(name: name, logoURL: URL(string: logo), source: .stream(URL(string: stream)!))
    }
}
