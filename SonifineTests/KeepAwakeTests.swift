import Foundation
import Testing
@testable import Sonifine

/// When the silent audio may stop, so the app stops using battery in the background.
struct KeepAwakeTests {
    private let pausedAt = Date(timeIntervalSince1970: 0)

    @Test func backgroundAppStopsTenMinutesAfterThePause() {
        let nineMinutes = pausedAt.addingTimeInterval(9 * 60)
        let elevenMinutes = pausedAt.addingTimeInterval(11 * 60)

        #expect(KeepAwake.isNeeded(isAppActive: false, isPlaying: false, pausedSince: pausedAt, now: nineMinutes))
        #expect(!KeepAwake.isNeeded(isAppActive: false, isPlaying: false, pausedSince: pausedAt, now: elevenMinutes))
    }

    @Test func playingSonosOrOpenAppKeepsTheButtons() {
        let anHourLater = pausedAt.addingTimeInterval(60 * 60)

        #expect(KeepAwake.isNeeded(isAppActive: false, isPlaying: true, pausedSince: pausedAt, now: anHourLater))
        #expect(KeepAwake.isNeeded(isAppActive: true, isPlaying: false, pausedSince: pausedAt, now: anHourLater))
    }
}
