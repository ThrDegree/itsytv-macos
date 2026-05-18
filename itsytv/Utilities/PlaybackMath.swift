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
