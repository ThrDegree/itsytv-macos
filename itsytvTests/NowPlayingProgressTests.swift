import Testing
import Foundation

struct PlaybackMathTests {

    // MARK: - seekProgress

    @Test func progressMidpoint() {
        #expect(seekProgress(time: 30, duration: 60) == 0.5)
    }

    @Test func progressAtStart() {
        #expect(seekProgress(time: 0, duration: 60) == 0)
    }

    @Test func progressAtEnd() {
        #expect(seekProgress(time: 60, duration: 60) == 1.0)
    }

    @Test func progressClampsAboveOne() {
        // Server can report position slightly past duration
        #expect(seekProgress(time: 65, duration: 60) == 1.0)
    }

    @Test func progressZeroDuration() {
        #expect(seekProgress(time: 30, duration: 0) == 0)
    }

    @Test func progressNegativeDuration() {
        #expect(seekProgress(time: 10, duration: -1) == 0)
    }

    @Test func progressQuarter() {
        #expect(seekProgress(time: 15, duration: 60) == 0.25)
    }

    // MARK: - formatPlaybackTime

    @Test func formatZero() {
        #expect(formatPlaybackTime(0) == "0:00")
    }

    @Test func formatUnderTenSeconds() {
        #expect(formatPlaybackTime(9) == "0:09")
    }

    @Test func formatOneMinute() {
        #expect(formatPlaybackTime(60) == "1:00")
    }

    @Test func formatOneHour() {
        #expect(formatPlaybackTime(3600) == "60:00")
    }

    @Test func formatTypicalMovie() {
        // 112 min 30 sec
        #expect(formatPlaybackTime(6750) == "112:30")
    }

    @Test func formatNegativeClampedToZero() {
        #expect(formatPlaybackTime(-10) == "0:00")
    }

    @Test func formatPaddedSeconds() {
        #expect(formatPlaybackTime(65) == "1:05")
    }

    @Test func formatFractionalSecondsTruncated() {
        // Fractional seconds truncated, not rounded
        #expect(formatPlaybackTime(59.9) == "0:59")
    }
}

// MARK: - localProgressionTick

struct LocalProgressionTickTests {

    // MARK: - Pause / play guard (regression: bar drifted when paused)

    @Test func pausedDoesNotAdvance() {
        // The bug: `currentTime > 0` was ORed with `isPlaying`, causing drift.
        #expect(localProgressionTick(currentTime: 30, duration: 60, isPlaying: false, pendingSeekTarget: nil) == nil)
    }

    @Test func pausedAtZeroDoesNotAdvance() {
        #expect(localProgressionTick(currentTime: 0, duration: 60, isPlaying: false, pendingSeekTarget: nil) == nil)
    }

    @Test func playingAdvancesByOne() {
        #expect(localProgressionTick(currentTime: 30, duration: 60, isPlaying: true, pendingSeekTarget: nil) == 31)
    }

    @Test func playingFromZeroAdvances() {
        #expect(localProgressionTick(currentTime: 0, duration: 60, isPlaying: true, pendingSeekTarget: nil) == 1)
    }

    // MARK: - Duration guard

    @Test func zeroDurationSkips() {
        #expect(localProgressionTick(currentTime: 0, duration: 0, isPlaying: true, pendingSeekTarget: nil) == nil)
    }

    @Test func negativeDurationSkips() {
        #expect(localProgressionTick(currentTime: 0, duration: -1, isPlaying: true, pendingSeekTarget: nil) == nil)
    }

    // MARK: - Clamp at duration

    @Test func clampsAtDuration() {
        #expect(localProgressionTick(currentTime: 60, duration: 60, isPlaying: true, pendingSeekTarget: nil) == 60)
    }

    @Test func doesNotExceedDuration() {
        #expect(localProgressionTick(currentTime: 59.5, duration: 60, isPlaying: true, pendingSeekTarget: nil) == 60)
    }

    // MARK: - Pending seek suppresses local fallback

    @Test func pendingSeekSuppressesAdvance() {
        #expect(localProgressionTick(currentTime: 30, duration: 60, isPlaying: true, pendingSeekTarget: 45) == nil)
    }

    @Test func nilSeekTargetAllowsAdvance() {
        #expect(localProgressionTick(currentTime: 30, duration: 60, isPlaying: true, pendingSeekTarget: nil) == 31)
    }
}
