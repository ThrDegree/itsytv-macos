func isNewerVersion(_ remote: String, than current: String) -> Bool {
    let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
    let currentParts = current.split(separator: ".").compactMap { Int($0) }
    let count = max(remoteParts.count, currentParts.count)
    for i in 0..<count {
        let r = i < remoteParts.count ? remoteParts[i] : 0
        let c = i < currentParts.count ? currentParts[i] : 0
        if r > c { return true }
        if r < c { return false }
    }
    return false
}
