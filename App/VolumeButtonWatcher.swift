import AVFoundation
import MediaPlayer
import OSLog
import SwiftUI

/// Turns presses of the iPhone volume buttons into +1 / -1 events.
///
/// iOS has no API for the buttons themselves, so this watches the system output
/// volume: each press moves it one step of 1/16 up or down. When the volume
/// nears the top or bottom, where a press would no longer change it, the app
/// moves it back to the middle once. If iOS moves it away again, the app accepts
/// that instead of fighting it. The hidden `MPVolumeView` in the view hierarchy
/// allows that move and keeps the system volume overlay away.
@MainActor
final class VolumeButtonWatcher {
    var onPress: ((Int) -> Void)?

    let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    private let session = AVAudioSession.sharedInstance()
    private let middle: Float = 0.5
    private let log = Logger(subsystem: "com.example.sonifine", category: "VolumeButtons")
    private var observation: NSKeyValueObservation?

    func start() {
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        if observation == nil {
            observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                guard let old = change.oldValue, let new = change.newValue else { return }
                Task { @MainActor in self?.volumeChanged(from: old, to: new) }
            }
        }
        moveAwayFromEdge(session.outputVolume)
    }

    private func volumeChanged(from old: Float, to new: Float) {
        let step = abs(new - old)
        // One press is one step of 1/16. Bigger jumps come from the app moving the
        // volume to the middle, or from iOS itself.
        guard step > 0.03, step < 0.1 else {
            log.info("volume \(old) → \(new): not a press")
            return
        }
        let direction = new > old ? 1 : -1
        log.info("volume \(old) → \(new): press \(direction)")
        onPress?(direction)
        moveAwayFromEdge(new)
    }

    /// Near the top or bottom a press can't move the volume further, so move it
    /// to the middle. This happens once; there is no retry.
    private func moveAwayFromEdge(_ volume: Float) {
        guard volume < 0.15 || volume > 0.85 else { return }
        DispatchQueue.main.async { [self] in
            volumeView.subviews.compactMap { $0 as? UISlider }.first?.value = middle
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
