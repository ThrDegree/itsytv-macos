import Testing
import ItsytvCore

struct PanelTransitionTests {

    // MARK: - Show on connect

    @Test func disconnectedToConnectedShows() {
        #expect(panelTransition(from: .disconnected, to: .connected) == .show)
    }

    @Test func connectingToConnectedShows() {
        #expect(panelTransition(from: .connecting, to: .connected) == .show)
    }

    @Test func pairingToConnectedShows() {
        #expect(panelTransition(from: .pairing, to: .connected) == .show)
    }

    @Test func connectedToConnectedShows() {
        // Reconnection — panel should re-anchor to current device.
        #expect(panelTransition(from: .connected, to: .connected) == .show)
    }

    // MARK: - Dismiss on disconnect

    @Test func connectingToDisconnectedDismisses() {
        #expect(panelTransition(from: .connecting, to: .disconnected) == .dismiss)
    }

    @Test func connectedToDisconnectedDismisses() {
        #expect(panelTransition(from: .connected, to: .disconnected) == .dismiss)
    }

    @Test func pairingToDisconnectedDismisses() {
        #expect(panelTransition(from: .pairing, to: .disconnected) == .dismiss)
    }

    @Test func errorToDisconnectedDismisses() {
        #expect(panelTransition(from: .error("lost"), to: .disconnected) == .dismiss)
    }

    // MARK: - No-op while already disconnected

    @Test func disconnectedToDisconnectedIsNone() {
        // Already closed — avoid double-dismiss.
        #expect(panelTransition(from: .disconnected, to: .disconnected) == .none)
    }

    // MARK: - Intermediate states leave panel as-is

    @Test func disconnectedToConnectingIsNone() {
        #expect(panelTransition(from: .disconnected, to: .connecting) == .none)
    }

    @Test func connectingToPairingIsNone() {
        #expect(panelTransition(from: .connecting, to: .pairing) == .none)
    }

    @Test func connectedToErrorIsNone() {
        // Error view is shown inside the panel; panel stays open.
        #expect(panelTransition(from: .connected, to: .error("timeout")) == .none)
    }

    @Test func disconnectedToErrorIsNone() {
        #expect(panelTransition(from: .disconnected, to: .error("unreachable")) == .none)
    }
}
