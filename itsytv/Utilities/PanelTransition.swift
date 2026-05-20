import ItsytvCore

enum PanelTransition: Equatable {
    case show
    case dismiss
    case none
}

/// Maps a connection-status change to the required panel action.
/// Connecting, pairing, and error states leave the panel as-is.
func panelTransition(from previous: ConnectionStatus, to current: ConnectionStatus) -> PanelTransition {
    switch current {
    case .disconnected where previous != .disconnected:
        return .dismiss
    case .connected:
        return .show
    default:
        return .none
    }
}
