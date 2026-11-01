import Foundation

/// Rooms that play together. Playback, the queue and the group volume go to
/// the coordinator.
struct SonosGroup: Identifiable, Hashable {
    /// The coordinator's UUID, such as `RINCON_000E58A0B1C201400`.
    let id: String
    /// The coordinator's room, plus the count of the other rooms: `Kitchen + 2`.
    let name: String
    let coordinator: URL
    /// Every visible room in the group, the coordinator first.
    let rooms: [SonosRoom]

    var roomIDs: [String] { rooms.map(\.id) }
}

/// One room of a group. Its sound settings go to its own player, never to the coordinator.
struct SonosRoom: Identifiable, Hashable {
    /// The UUID of the room's player, such as `RINCON_000E58A0B1C201400`.
    let id: String
    let name: String
    /// The room's player, which holds its sound settings.
    let address: URL
    /// Every player in the room: the room's own, a stereo partner, a Sub and surrounds.
    let devices: [URL]
}

/// The sound of one room, from its `RenderingControl`.
struct SoundSettings: Equatable {
    /// −10…10, 0 is flat.
    var bass = 0
    /// −10…10, 0 is flat.
    var treble = 0
    var loudness = true
    /// Whether Trueplay tuning is on; nil when the player doesn't say.
    var trueplay: Bool?

    static let range = -10...10
    /// What "Reset to default" sends, as the Sonos app does.
    static let defaults: [SoundSetting] = [.bass(0), .treble(0), .loudness(true)]

    mutating func apply(_ setting: SoundSetting) {
        switch setting {
        case .bass(let value): bass = value
        case .treble(let value): treble = value
        case .loudness(let on): loudness = on
        }
    }
}

/// One change to the sound of a room.
enum SoundSetting: Equatable {
    case bass(Int)
    case treble(Int)
    case loudness(Bool)
}

/// What a player says about itself in `/xml/device_description.xml`.
struct SonosDevice: Identifiable, Equatable {
    /// The UUID, such as `RINCON_000E58A0B1C201400`.
    let id: String
    /// The product, such as `Bookshelf`.
    let name: String
    /// The model number, such as `S21`.
    let model: String
    let serialNumber: String
    let softwareVersion: String
    let hardwareVersion: String
    let ipAddress: String
}

/// What a group plays, and how loud.
struct GroupStatus: Equatable {
    var volume = 0
    var isPlaying = false
    /// Seconds into the song when Sonos reported it, at `positionDate`.
    var position: TimeInterval = 0
    /// The length of the song in seconds; 0 for radio.
    var duration: TimeInterval = 0
    var positionDate = Date.distantPast
    var title = ""
    var artist = ""
    var album = ""
    var artworkURL: URL?
    /// The song, when it comes from Spotify.
    var spotifyTrack: SpotifyURI?
    /// The Spotify account Sonos plays it with.
    var spotifyAccount: SpotifyAccount?
    /// The song's place in the queue, counted from 1.
    var queuePosition = 0
    var playMode = PlayMode.normal
    /// False once a status request failed; the next answer sets it back.
    var isReachable = true
    /// True when this player plays along with another coordinator: the groups changed.
    var followsAnotherGroup = false

    var displayTitle: String { title.isEmpty ? "Not playing" : title }

    /// Where the song is at `date`: the reported position plus the time since, while playing.
    func position(at date: Date) -> TimeInterval {
        let played = isPlaying ? date.timeIntervalSince(positionDate) : 0
        return min(duration, max(0, position + played))
    }

    /// Whether the screen would show something else. A position that only moved
    /// on with the clock is no change.
    func differs(from other: GroupStatus) -> Bool {
        var a = self, b = other
        let drift = abs(a.position(at: .now) - b.position(at: .now))
        (a.position, a.positionDate, b.position, b.positionDate) = (0, .distantPast, 0, .distantPast)
        return a != b || drift > 2
    }
}

enum RepeatMode {
    case off, all, one

    var next: RepeatMode { self == .off ? .all : self == .all ? .one : .off }
}

/// Shuffle and repeat. Sonos names every combination, such as `SHUFFLE_NOREPEAT`.
struct PlayMode: Equatable {
    var shuffle: Bool
    var repeatMode: RepeatMode

    static let normal = PlayMode(shuffle: false, repeatMode: .off)

    init(shuffle: Bool, repeatMode: RepeatMode) {
        self.shuffle = shuffle
        self.repeatMode = repeatMode
    }

    init(sonos value: String) {
        shuffle = value.hasPrefix("SHUFFLE")
        repeatMode = value.hasSuffix("REPEAT_ONE") ? .one
            : value == "REPEAT_ALL" || value == "SHUFFLE" ? .all : .off
    }

    var sonosValue: String {
        switch (shuffle, repeatMode) {
        case (false, .off): "NORMAL"
        case (false, .all): "REPEAT_ALL"
        case (false, .one): "REPEAT_ONE"
        case (true, .off): "SHUFFLE_NOREPEAT"
        case (true, .all): "SHUFFLE"
        case (true, .one): "SHUFFLE_REPEAT_ONE"
        }
    }
}

/// Sonos writes times as `H:MM:SS`, and `NOT_IMPLEMENTED` for radio.
enum SonosTime {
    static func seconds(_ time: String?) -> TimeInterval {
        let parts = (time ?? "").split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return 0 }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    static func string(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

/// A song in the queue of a group.
struct QueueEntry: Identifiable, Equatable {
    /// The place in the queue, counted from 0.
    let id: Int
    let title: String
    let artist: String
    let artworkURL: URL?
    let spotifyTrack: SpotifyURI?
}

/// The Sonos household and a player in it, which Sonos's Spotify service needs.
struct Household: Equatable {
    let id: String
    let deviceID: String
}
