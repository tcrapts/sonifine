import Foundation
import Network
import Observation

/// Finds the Sonos groups on the network, keeps the status of each, and
/// controls them. The selected group is the one the volume buttons, the
/// mini-player and Now Playing control.
@MainActor
@Observable
final class SonosController {
    private(set) var groups: [SonosGroup] = []
    private(set) var statuses: [String: GroupStatus] = [:]
    /// Counts presses of the volume buttons, so the volume overlay can show each one.
    private(set) var volumeButtonPresses = 0
    /// True while a playlist, album or songs are being put in the queue.
    private(set) var isStartingPlayback = false
    /// A short confirmation, such as "Added to the queue", for two seconds.
    private(set) var notice: String?
    /// True while a volume change is on its way to Sonos.
    private(set) var isSendingVolume = false

    /// The failure of the last action until the next one succeeds, or else a lost connection.
    var errorMessage: String? { actionError ?? connectionError }
    private var actionError: String?
    private var connectionError: String?

    /// The room the user picked. The selected group is the group that holds it,
    /// so the choice survives regrouping.
    private(set) var selectedRoomID: String? {
        didSet { defaults.set(selectedRoomID, forKey: "selectedRoomID") }
    }

    /// Sonos volume points (0–100) per press of a volume button.
    var stepSize: Int {
        didSet { defaults.set(stepSize, forKey: "stepSize") }
    }

    var selectedGroup: SonosGroup? {
        guard let selectedRoomID else { return nil }
        return groups.first { $0.roomIDs.contains(selectedRoomID) }
    }

    var selectedStatus: GroupStatus { selectedGroup.flatMap { statuses[$0.id] } ?? GroupStatus() }

    private let makePlayer: @MainActor (URL) -> SonosPlayer
    private let defaults: UserDefaults
    private var browser: NWBrowser?
    /// Every player seen on the network; the one that answered last comes first.
    private var knownPlayers: [URL] = []
    private var householdID: String?
    private var account: SpotifyAccount
    /// When the user last changed a group. Polls that started earlier are stale for it.
    private var lastAction: [String: Date] = [:]
    private var pendingVolume: (groupID: String, adjustment: Int)?
    private var playback: Task<Void, Never>?
    private var polls = 0

    init(makePlayer: @escaping @MainActor (URL) -> SonosPlayer = { SOAPSonosPlayer(address: $0) },
         defaults: UserDefaults = .standard) {
        self.makePlayer = makePlayer
        self.defaults = defaults
        let savedStep = defaults.integer(forKey: "stepSize")
        stepSize = savedStep == 0 ? 1 : savedStep
        // Earlier versions stored the coordinator, which is also a room.
        selectedRoomID = defaults.string(forKey: "selectedRoomID") ?? defaults.string(forKey: "selectedGroupID")
        account = SpotifyAccount(serviceID: defaults.string(forKey: "spotifyServiceID") ?? "9",
                                 accountNumber: defaults.string(forKey: "spotifySerialNumber") ?? "1")
    }

    func select(_ group: SonosGroup) {
        selectedRoomID = group.id
    }

    /// Shows a failure that happened outside this controller, such as a Spotify lookup.
    func report(_ message: String) {
        actionError = message
    }

    // MARK: Discovery

    /// Sonos players advertise `_sonos._tcp` with their address in the TXT record.
    func startDiscovery() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_sonos._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let players = results.compactMap { result -> URL? in
                guard case .bonjour(let txt) = result.metadata else { return nil }
                return txt["location"].flatMap(URL.init(string:))?.sonosPlayerURL
            }
            Task { @MainActor in self?.found(players) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func found(_ players: [URL]) {
        let new = players.filter { !knownPlayers.contains($0) }
        guard !new.isEmpty else { return }
        knownPlayers += new
        if groups.isEmpty { Task { await loadGroups() } }
    }

    /// Reads the groups from the first player that answers.
    func loadGroups() async {
        for address in knownPlayers {
            guard let groups = try? await makePlayer(address).zoneGroups(), !groups.isEmpty else { continue }
            knownPlayers.removeAll { $0 == address }
            knownPlayers.insert(address, at: 0)
            self.groups = groups
            statuses = statuses.filter { id, _ in groups.contains { $0.id == id } }
            if selectedGroup == nil { selectedRoomID = groups.first?.id }
            connectionError = nil
            await refresh()
            return
        }
        if !knownPlayers.isEmpty { connectionError = "Can't reach your Sonos. Is this iPhone on the same Wi-Fi?" }
    }

    /// The household of the speakers, for Sonos's Spotify service.
    func household() async -> Household? {
        guard let group = selectedGroup ?? groups.first else { return nil }
        if householdID == nil { householdID = try? await player(group).householdID() }
        return householdID.map { Household(id: $0, deviceID: group.id) }
    }

    // MARK: Status

    /// The app calls this every three seconds: the selected group each time,
    /// every group every third time, and the groups themselves every tenth.
    func poll() async {
        polls += 1
        if polls % 10 == 0 {
            await loadGroups()
        } else if polls % 3 == 0 {
            await refresh()
        } else if let group = selectedGroup {
            await refresh([group])
        }
    }

    /// Reads the status of `groups`, all groups by default.
    func refresh(_ groups: [SonosGroup]? = nil) async {
        let started = Date.now
        let groups = groups ?? self.groups
        var regrouped = false
        await withTaskGroup(of: (String, GroupStatus?).self) { tasks in
            for group in groups {
                tasks.addTask { @MainActor in (group.id, try? await self.player(group).status()) }
            }
            for await (id, status) in tasks {
                // A change the user made while this poll ran is newer than its answer.
                if let last = lastAction[id], last > started { continue }
                guard var status else {
                    if statuses[id]?.isReachable == true { statuses[id]?.isReachable = false }
                    continue
                }
                if id == pendingVolume?.groupID || (isSendingVolume && id == selectedGroup?.id) {
                    status.volume = statuses[id]?.volume ?? status.volume
                }
                remember(status.spotifyAccount)
                regrouped = regrouped || status.followsAnotherGroup
                if statuses[id].map(status.differs(from:)) ?? true { statuses[id] = status }
            }
        }
        if regrouped { await loadGroups() }
    }

    // MARK: Volume

    /// One press of a volume button, or of a speaker icon: `direction` is +1 or -1.
    /// Presses that come while a change is on its way are summed into the next one.
    func nudgeVolume(_ direction: Int) {
        guard let group = selectedGroup else { return }
        volumeButtonPresses += 1
        let adjustment = direction * stepSize
        statuses[group.id, default: GroupStatus()].volume = min(100, max(0, selectedStatus.volume + adjustment))
        lastAction[group.id] = .now
        if let pending = pendingVolume, pending.groupID == group.id {
            pendingVolume = (group.id, pending.adjustment + adjustment)
        } else {
            pendingVolume = (group.id, adjustment)
        }
        guard !isSendingVolume else { return }
        isSendingVolume = true
        Task { await sendPendingVolume() }
    }

    private func sendPendingVolume() async {
        defer { isSendingVolume = false }
        while let pending = pendingVolume {
            pendingVolume = nil
            guard let group = groups.first(where: { $0.id == pending.groupID }) else { continue }
            do {
                let volume = try await player(group).adjustVolume(by: pending.adjustment)
                lastAction[group.id] = .now
                if pendingVolume == nil { statuses[group.id]?.volume = volume }
                actionError = nil
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func setVolume(_ volume: Int, of group: SonosGroup) async {
        statuses[group.id, default: GroupStatus()].volume = volume
        await perform(on: group) { try await $0.setVolume(volume) }
    }

    // MARK: Playback

    func togglePlayPause(_ group: SonosGroup) async {
        let isPlaying = statuses[group.id]?.isPlaying ?? false
        statuses[group.id]?.isPlaying = !isPlaying
        await perform(on: group) { isPlaying ? try await $0.pause() : try await $0.play() }
    }

    func pauseAll() async {
        let playing = groups.filter { statuses[$0.id]?.isPlaying == true }
        await withTaskGroup(of: Void.self) { tasks in
            for group in playing {
                statuses[group.id]?.isPlaying = false
                tasks.addTask { @MainActor in await self.perform(on: group) { try await $0.pause() } }
            }
        }
    }

    func next() async { await performOnSelected { try await $0.next() } }
    func previous() async { await performOnSelected { try await $0.previous() } }

    /// Jumps to a moment in the current song.
    func seek(to seconds: TimeInterval) async {
        guard let group = selectedGroup else { return }
        statuses[group.id]?.position = seconds
        statuses[group.id]?.positionDate = .now
        await perform(on: group) { try await $0.seek(to: seconds) }
    }

    func setPlayMode(_ mode: PlayMode) async {
        guard let group = selectedGroup else { return }
        statuses[group.id]?.playMode = mode
        await perform(on: group) { try await $0.setPlayMode(mode) }
    }

    /// The songs in the queue of the selected group, up to 200.
    func queue() async -> [QueueEntry] {
        guard let group = selectedGroup else { return [] }
        return (try? await player(group).queue()) ?? []
    }

    /// The covers of the next `count` songs, to load before they play.
    func upcomingArtwork(count: Int = 3) async -> [URL] {
        guard let group = selectedGroup else { return [] }
        // `queuePosition` counts from 1, so it is also the place of the next song counted from 0.
        let next = (try? await player(group).queue(from: selectedStatus.queuePosition, count: count)) ?? []
        return next.compactMap(\.artworkURL)
    }

    /// Plays the song at `index` in the queue, counted from 0.
    func playFromQueue(_ index: Int) async {
        await performOnSelected {
            try await $0.seek(toTrack: index + 1)
            try await $0.play()
        }
    }

    /// Adds a song, album or playlist to the queue of the selected group:
    /// right after the current song with `next`, else at the end.
    func addToQueue(_ uri: SpotifyURI, next: Bool) async {
        guard let group = selectedGroup else { return }
        guard let item = uri.queueItem(account: account) else {
            actionError = "Sonos can't queue this."
            return
        }
        let current = statuses[group.id]?.queuePosition ?? 0
        do {
            let added = try await player(group).addToQueue([item], after: next && current > 0 ? current : nil)
            actionError = nil
            show(added == 1 ? (next ? "Plays next" : "Added to the queue")
                 : "\(added) songs \(next ? "play next" : "added to the queue")")
        } catch {
            actionError = (error as? AppError)?.code == 804
                ? "Sonos can't queue this. Is it empty?"
                : error.localizedDescription
        }
    }

    private func show(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if notice == message { notice = nil }
        }
    }

    /// Replaces the queue of the selected group and plays it. A new request
    /// waits for the one before it, so two taps never mix their queues.
    func play(_ request: PlayRequest) async {
        let previous = playback
        previous?.cancel()
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await run(request)
        }
        playback = task
        await task.value
    }

    private func run(_ request: PlayRequest) async {
        guard let group = selectedGroup else { return }
        let uris: [SpotifyURI], shuffle: Bool
        switch request {
        case .songs(let songs, _, let random): (uris, shuffle) = (songs, random)
        case .collection(let collection, _, let random): (uris, shuffle) = ([collection], random)
        case .artist: return // The catalog turns an artist into songs first.
        }
        let items = uris.compactMap { $0.queueItem(account: account) }
        guard !items.isEmpty else {
            actionError = "Sonos can't play this."
            return
        }

        isStartingPlayback = true
        defer { isStartingPlayback = false }
        lastAction[group.id] = .now
        let player = player(group)
        do {
            let added = try await player.replaceQueue(with: items, groupID: group.id)
            guard added > 0 else {
                actionError = "There is nothing to play in this list."
                return
            }
            try Task.checkCancellation()
            try await player.setPlayMode(PlayMode(shuffle: shuffle, repeatMode: .off))
            if !shuffle, let number = try await startNumber(of: request, in: player) {
                try await player.seek(toTrack: number)
            }
            try await player.play()
            statuses[group.id]?.isPlaying = true
            actionError = nil
        } catch {
            guard !HTTP.isCancellation(error) else { return }
            // 804: Sonos can't open the item, such as an empty playlist or one with only podcasts.
            actionError = (error as? AppError)?.code == 804
                ? "Sonos can't play this. Is it empty, or does it hold only podcasts or local files?"
                : "Couldn't play this on \(group.name): \(error.localizedDescription)"
        }
        lastAction[group.id] = .now
        await refresh([group])
    }

    /// The song to begin with, counted from 1 in the queue, or nil for the first.
    /// A song inside a playlist is found in the queue Sonos built, because the
    /// Web API leaves out podcasts and local files that Sonos keeps.
    private func startNumber(of request: PlayRequest, in player: SonosPlayer) async throws -> Int? {
        switch request {
        case .songs(_, let start, _):
            return start > 0 ? start + 1 : nil
        case .collection(_, let start?, _):
            return try await player.queue().first { $0.spotifyTrack == start }.map { $0.id + 1 }
        case .collection, .artist:
            return nil
        }
    }

    // MARK: Rooms

    /// Every room of every group, in the order of the groups.
    var rooms: [SonosRoom] { groups.flatMap(\.rooms) }

    /// The sound settings of a room, read from its own player.
    func soundSettings(of room: SonosRoom) async -> SoundSettings? {
        do {
            let settings = try await makePlayer(room.address).soundSettings()
            actionError = nil
            return settings
        } catch {
            actionError = "Couldn't read the sound of \(room.name): \(error.localizedDescription)"
            return nil
        }
    }

    /// Sends sound settings to a room, in order. Returns false when the player refused one.
    @discardableResult
    func change(_ settings: [SoundSetting], of room: SonosRoom) async -> Bool {
        let player = makePlayer(room.address)
        do {
            for setting in settings { try await player.change(setting) }
            actionError = nil
            return true
        } catch {
            actionError = "Couldn't change the sound of \(room.name): \(error.localizedDescription)"
            return false
        }
    }

    /// The players in a room, as they describe themselves. A player that doesn't answer is left out.
    func devices(in room: SonosRoom) async -> [SonosDevice] {
        var devices: [SonosDevice] = []
        for address in room.devices {
            if let device = try? await makePlayer(address).device() { devices.append(device) }
        }
        return devices
    }

    // MARK: Helpers

    private func player(_ group: SonosGroup) -> SonosPlayer { makePlayer(group.coordinator) }

    private func performOnSelected(_ action: (SonosPlayer) async throws -> Void) async {
        guard let group = selectedGroup else { return }
        await perform(on: group, action)
    }

    /// Runs an action on a group, keeps polls from undoing it, then reads the result.
    private func perform(on group: SonosGroup, _ action: (SonosPlayer) async throws -> Void) async {
        lastAction[group.id] = .now
        do {
            try await action(player(group))
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
        lastAction[group.id] = .now
        await refresh([group])
    }

    private func remember(_ found: SpotifyAccount?) {
        guard let found, found != account else { return }
        account = found
        defaults.set(found.serviceID, forKey: "spotifyServiceID")
        defaults.set(found.accountNumber, forKey: "spotifySerialNumber")
    }
}
