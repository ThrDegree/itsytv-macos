import Foundation

/// Removes MAC-address-format IDs (rpBA) from a device ID list.
/// These are legacy Bonjour peer IDs that no longer correspond to a
/// user-pairable device; keeping them causes ghost entries in the device picker.
func filterMACAddresses(_ ids: [String]) -> [String] {
    let macPattern = /^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/
    return ids.filter { $0.wholeMatch(of: macPattern) == nil }
}
