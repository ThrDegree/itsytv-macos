import Foundation

func seekProgress(time: TimeInterval, duration: TimeInterval) -> Double {
    guard duration > 0 else { return 0 }
    return min(1, time / duration)
}

func formatPlaybackTime(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

/// One-second local interpolation step for the progress bar.
/// Returns the advanced `currentTime`, or `nil` to skip (paused, buffering, or seek pending).
/// Only advances when `isPlaying` — a non-zero position alone must not advance during pause.
func localProgressionTick(
    currentTime: TimeInterval,
    duration: TimeInterval,
    isPlaying: Bool,
    pendingSeekTarget: TimeInterval?
) -> TimeInterval? {
    guard pendingSeekTarget == nil, duration > 0, isPlaying else { return nil }
    return min(duration, currentTime + 1)
}
