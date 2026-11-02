import AVFoundation
import MediaPlayer
import OSLog
import SwiftUI

/// The rules of ADR 0003 for reading a press from the iPhone output volume.
enum VolumePress {
    /// +1 or -1 for a change of one step of 1/16, nil for anything else: the app
    /// moving the volume to the middle, iOS changing it, or a route change.
    static func direction(from old: Float, to new: Float) -> Int? {
        let step = abs(new - old)
        guard step > 0.03, step < 0.1 else { return nil }
        return new > old ? 1 : -1
    }

    /// Near the top or bottom a press can't move the volume further.
    static func needsMiddle(_ volume: Float) -> Bool {
        volume < 0.15 || volume > 0.85
    }

    static let middle: Float = 0.5
}

/// Turns presses of the iPhone volume buttons into +1 / -1 events.
///
/// iOS has no API for the buttons, so this watches the system output volume
/// while `NowPlayingSession` keeps the audio session active. Near either end it moves the
/// volume to the middle once, through the slider of a hidden `MPVolumeView`,
/// which also keeps the iOS volume overlay away. If iOS moves it back, the
/// watcher accepts that.
@MainActor
final class VolumeButtonWatcher {
    var onPress: (Int) -> Void = { _ in }

    let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private let session = AVAudioSession.sharedInstance()
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sonifine", category: "VolumeButtons")
    private var observation: NSKeyValueObservation?

    func start() {
        if observation == nil {
            observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                guard let old = change.oldValue, let new = change.newValue else { return }
                Task { @MainActor in self?.volumeChanged(from: old, to: new) }
            }
        }
        moveToMiddleIfNeeded(session.outputVolume)
    }

    private func volumeChanged(from old: Float, to new: Float) {
        guard let direction = VolumePress.direction(from: old, to: new) else {
            log.info("volume \(old) → \(new): not a press")
            return
        }
        log.info("volume \(old) → \(new): press \(direction)")
        onPress(direction)
        moveToMiddleIfNeeded(new)
    }

    private func moveToMiddleIfNeeded(_ volume: Float) {
        guard VolumePress.needsMiddle(volume) else { return }
        DispatchQueue.main.async { [self] in
            volumeView.subviews.compactMap { $0 as? UISlider }.first?.value = VolumePress.middle
        }
    }
}

/// Puts the watcher's `MPVolumeView` on screen, nearly invisible.
struct HiddenVolumeView: UIViewRepresentable {
    let watcher: VolumeButtonWatcher

    func makeUIView(context: Context) -> MPVolumeView {
        watcher.volumeView.alpha = 0.01
        return watcher.volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
