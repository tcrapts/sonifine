import AVFoundation
import MediaPlayer
import OSLog
import UIKit

/// When the app may let its silent audio stop: in the background, once the
/// Sonos has been paused for ten minutes. Until then the buttons and the lock
/// screen keep working.
enum KeepAwake {
    static let pausedGrace: TimeInterval = 10 * 60

    static func isNeeded(isAppActive: Bool, isPlaying: Bool, pausedSince: Date, now: Date) -> Bool {
        isAppActive || isPlaying || now.timeIntervalSince(pausedSince) < pausedGrace
    }
}

/// Makes Sonifine the app that iOS considers to be playing, as ADR 0004 explains.
///
/// It plays silence through a non-mixable playback session. iOS then gives the
/// volume buttons to this app, also in the background and on the lock screen,
/// instead of to an app such as Spotify that steers the Sonos itself. The lock
/// screen shows what the Sonos plays and sends its buttons back here.
@MainActor
final class NowPlayingSession {
    struct Commands {
        var play: () -> Void
        var pause: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (TimeInterval) -> Void
    }

    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let silence: AVAudioPCMBuffer
    private let log = Logger(subsystem: "com.example.sonifine", category: "NowPlaying")
    private var isRunning = false
    /// When the silence was last started or tried.
    private var lastStart = Date.distantPast
    private var pausedSince = Date.now
    private var artwork: (url: URL, item: MPMediaItemArtwork?)?

    init(commands: Commands) {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        silence.frameLength = silence.frameCapacity
        memset(silence.floatChannelData![0], 0, Int(silence.frameLength) * MemoryLayout<Float>.size)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        handle(commands)
        observeInterruptions()
    }

    /// Starts the silence. iOS may refuse, for instance while another app holds the
    /// audio; `update` then tries again every half minute.
    func start() {
        guard !isRunning else { return }
        lastStart = .now
        do {
            try session.setCategory(.playback)
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(silence, at: nil, options: .loops)
            player.play()
            isRunning = true
            log.info("silent audio started")
        } catch {
            log.error("silent audio failed: \(error.localizedDescription)")
        }
    }

    private func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        log.info("silent audio stopped")
    }

    /// Shows the selected group on the lock screen, and stops the silence when it is no longer needed.
    func update(group: SonosGroup?, status: GroupStatus) {
        let now = Date.now
        if status.isPlaying { pausedSince = now }
        let isAppActive = UIApplication.shared.applicationState == .active
        guard KeepAwake.isNeeded(isAppActive: isAppActive, isPlaying: status.isPlaying,
                                 pausedSince: pausedSince, now: now) else {
            stop()
            return
        }
        // Without the silence the lock screen and the buttons are lost: a refused or
        // interrupted start is tried again, not left for the next launch.
        if !isRunning, now.timeIntervalSince(lastStart) >= 30 { start() }
        guard let group else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: status.displayTitle,
            MPMediaItemPropertyArtist: status.artist,
            MPMediaItemPropertyAlbumTitle: status.album.isEmpty ? group.name : status.album,
            MPMediaItemPropertyPlaybackDuration: status.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: status.position(at: now),
            MPNowPlayingInfoPropertyPlaybackRate: status.isPlaying ? 1.0 : 0.0,
        ]
        if let item = artwork(for: status.artworkURL) { info[MPMediaItemPropertyArtwork] = item }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The cover of the current song, loaded once per URL.
    private func artwork(for url: URL?) -> MPMediaItemArtwork? {
        guard let url else { return nil }
        if let artwork, artwork.url == url { return artwork.item }
        artwork = (url, nil)
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), artwork?.url == url else { return }
            let item = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            artwork = (url, item)
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] = item
        }
        return nil
    }

    private func handle(_ commands: Commands) {
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping () -> Void) {
            command.addTarget { _ in
                action()
                return .success
            }
        }
        on(center.playCommand, commands.play)
        on(center.pauseCommand, commands.pause)
        on(center.nextTrackCommand, commands.next)
        on(center.previousTrackCommand, commands.previous)
        on(center.togglePlayPauseCommand) {
            let rate = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double
            (rate ?? 0) > 0 ? commands.pause() : commands.play()
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            commands.seek(event.positionTime)
            return .success
        }
    }

    /// A phone call or another app's audio interrupts the silence; take the buttons back afterwards.
    private func observeInterruptions() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began {
                    self.log.info("silent audio interrupted")
                    self.isRunning = false
                } else if type == .ended {
                    self.log.info("interruption ended")
                    self.lastStart = .distantPast
                    self.start()
                }
            }
        }
        // iOS restarted its audio service: everything must be set up again.
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.log.info("audio services were reset")
                self.isRunning = false
                self.lastStart = .distantPast
                self.start()
            }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                // A route change stops the engine; start it again.
                self.isRunning = false
                self.start()
            }
        }
    }
}
