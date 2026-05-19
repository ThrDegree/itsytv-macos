import AppKit
import SwiftUI
import Combine
import ServiceManagement
import os.log
import ObjectiveC
import ItsytvCore

// MARK: - Environment keys

private struct SwitchDeviceActionKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

private struct DismissActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var switchDeviceAction: ((String) -> Void)? {
        get { self[SwitchDeviceActionKey.self] }
        set { self[SwitchDeviceActionKey.self] = newValue }
    }
    var dismissAction: (() -> Void)? {
        get { self[DismissActionKey.self] }
        set { self[DismissActionKey.self] = newValue }
    }
}

// MARK: - Pairing cache

@Observable
final class PairingCache {
    private(set) var pairedIDs: Set<String> = []

    func refresh() {
        pairedIDs = Set(KeychainStorage.allPairedDeviceIDs())
    }
}

private let log = Logger(subsystem: "com.itsytv.app", category: "Panel")

final class AppController: NSObject {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let manager: AppleTVManager
    private let iconLoader: AppIconLoader
    private let pairingCache = PairingCache()
    private var observation: AnyCancellable?
    private var popover: NSPopover?
    private var panelDeviceID: String?
    private var keyboardMonitor: Any?
    private var clickOutsideMonitor: Any?

    init(manager: AppleTVManager, iconLoader: AppIconLoader) {
        self.manager = manager
        self.iconLoader = iconLoader
        super.init()
        pairingCache.refresh()
        setupStatusItem()
        startObserving()
        setupHotkeyHandler()
        setupSleepWakeObserver()
        manager.startScanning()
    }

    func cleanup() {
        removeKeyboardMonitor()
        removeClickOutsideMonitor()
        observation?.cancel()
        observation = nil
        HotkeyManager.shared.unregisterAll()
        popover?.close()
        popover = nil
        panelDeviceID = nil
    }

    private func setupSleepWakeObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.manager.disconnect()
        }
        nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.manager.startScanning()
        }
    }

    private func setupHotkeyHandler() {
        HotkeyManager.shared.reregisterAll()
        HotkeyManager.shared.onHotkeyPressed = { [weak self] deviceID in
            guard let self else { return }
            if self.popover?.isShown == true && self.panelDeviceID == deviceID {
                self.dismissPanel()
            } else {
                self.openRemote(for: deviceID)
            }
        }
    }

    private var pendingOpenDeviceID: String?

    func openRemote(for deviceID: String? = nil) {
        let targetID: String?
        if let deviceID {
            targetID = deviceID
        } else {
            let lastID = UserDefaults.standard.string(forKey: "lastConnectedDeviceID")
            if let lastID, pairingCache.pairedIDs.contains(lastID) {
                targetID = lastID
            } else {
                targetID = manager.discoveredDevices.first(where: { pairingCache.pairedIDs.contains($0.id) })?.id
            }
        }
        let discoveredCount = manager.discoveredDevices.count
        log.error("openRemote: targetID=\(targetID ?? "nil", privacy: .public) discoveredCount=\(discoveredCount, privacy: .public)")
        guard let targetID else {
            log.error("openRemote: no targetID, returning")
            return
        }

        if let device = manager.discoveredDevices.first(where: { $0.id == targetID }) {
            log.error("openRemote: device found, connecting")
            connectAndShow(device)
        } else {
            log.error("openRemote: device not discovered yet, setting pendingOpenDeviceID")
            pendingOpenDeviceID = targetID
        }
    }

    private func connectAndShow(_ device: AppleTVDevice) {
        manager.connect(to: device)
        if pairingCache.pairedIDs.contains(device.id) {
            UserDefaults.standard.set(device.id, forKey: "lastConnectedDeviceID")
        }
        showPanel()
    }

    func switchDevice(to deviceID: String) {
        manager.disconnect()
        openRemote(for: deviceID)
    }

    // MARK: - Setup

    private func setupStatusItem() {
        if let button = statusItem.button {
            if let icon = Bundle.main.image(forResource: "MenuBarIcon") {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseDown])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if popover?.isShown == true {
            dismissPanel()
            return
        }

        manager.refreshScanning()
        if !pairingCache.pairedIDs.isEmpty {
            openRemote()
        } else {
            showPanel()
        }
    }

    private func startObserving() {
        observation = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleStateChange()
            }
    }

    private var lastKnownStatus: ConnectionStatus = .disconnected
    private var lastKnownDeviceCount: Int = 0

    private func handleStateChange() {
        let currentStatus = manager.connectionStatus
        let currentDeviceCount = manager.discoveredDevices.count

        if let pendingID = pendingOpenDeviceID,
           let device = manager.discoveredDevices.first(where: { $0.id == pendingID }) {
            pendingOpenDeviceID = nil
            connectAndShow(device)
            return
        }

        guard currentStatus != lastKnownStatus || currentDeviceCount != lastKnownDeviceCount else { return }
        let previousStatus = lastKnownStatus
        lastKnownStatus = currentStatus
        lastKnownDeviceCount = currentDeviceCount

        switch currentStatus {
        case .disconnected:
            pairingCache.refresh()
            if previousStatus != .disconnected {
                dismissPanel()
            }
        case .connected:
            if case .pairing = previousStatus { pairingCache.refresh() }
            showPanel()
        default:
            break
        }
    }

    // MARK: - Popover

    private func showPanel() {
        if popover != nil { return }

        let content = PanelContentView()
            .environment(manager)
            .environment(iconLoader)
            .environment(pairingCache)
            .environment(\.switchDeviceAction, { [weak self] deviceID in
                self?.switchDevice(to: deviceID)
            })
            .environment(\.dismissAction, { [weak self] in
                self?.dismissPanel()
            })

        let vc = NSViewController()
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = .preferredContentSize
        vc.view = hostingView

        let popover = NSPopover()
        popover.contentViewController = vc
        // Set explicit initial size so NSPopover positions the arrow correctly on show().
        // Without this, sizingOptions may not have reported a size yet, causing NSPopover
        // to anchor from the wrong edge and land the arrow at the right side of the body.
        popover.contentSize = NSSize(width: 176, height: 500)
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self

        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        self.popover = popover
        self.panelDeviceID = manager.connectedDeviceID
        installKeyboardMonitor()
        installClickOutsideMonitor()
    }

    private func dismissPanel() {
        removeKeyboardMonitor()
        removeClickOutsideMonitor()
        popover?.close()
        panelDeviceID = nil
        // popover is nilled in popoverDidClose
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover?.isShown == true else { return event }
            if self.handleRemoteKeyDown(event) { return nil }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let popover = self.popover, popover.isShown else { return }
            let loc = NSEvent.mouseLocation
            if popover.contentViewController?.view.window?.frame.contains(loc) == false {
                self.dismissPanel()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    private func handleRemoteKeyDown(_ event: NSEvent) -> Bool {
        if case .pairing = manager.connectionStatus { return false }

        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 13, 4: // Cmd+W, Cmd+H
                dismissPanel()
                return true
            case 40: // Cmd+K
                manager.keyboardToggleCounter &+= 1
                manager.triggerKeyboardBlink(.siri)
                return true
            case 3: // Cmd+F
                let key = "showAppsSearch"
                UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
                return true
            default:
                break
            }
        }

        if event.modifierFlags.contains([.command, .shift]) {
            switch event.keyCode {
            case 46: // Cmd+Shift+M
                manager.toggleMute()
                manager.triggerKeyboardBlink(.siri)
                return true
            default:
                break
            }
        }

        let window = popover?.contentViewController?.view.window
        if let responder = window?.firstResponder {
            var r: NSResponder? = responder
            while let current = r {
                if current is NSText || current is NSTextField { return false }
                r = current.nextResponder
            }
        }

        let button: CompanionButton? = switch event.keyCode {
        case 126: .up
        case 125: .down
        case 123: .left
        case 124: .right
        case 36:  .select
        case 51:  .home
        case 53:  .menu
        case 49:  .playPause
        case 24:  .volumeUp
        case 27:  .volumeDown
        default:  nil
        }
        guard let button else { return false }
        manager.pressButton(button)
        manager.triggerKeyboardBlink(button)
        return true
    }

}

// MARK: - NSPopoverDelegate

extension AppController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        removeKeyboardMonitor()
        removeClickOutsideMonitor()
        if manager.connectionStatus != .disconnected {
            manager.disconnect()
        }
        popover = nil
        panelDeviceID = nil
    }
}

// MARK: - Panel SwiftUI content

struct PanelMenuButton: View {
    let deviceID: String
    let onUnpair: () -> Void
    @AppStorage("showAppsSearch") private var showAppsSearch = false
    @State private var showingHotkeyRecorder = false
    @State private var currentHotkey: ShortcutKeys?

    var body: some View {
        Menu {
            Toggle("Show app search", isOn: $showAppsSearch)
                .keyboardShortcut("f", modifiers: .command)
            Divider()
            Button(hotkeyButtonTitle) {
                showingHotkeyRecorder = true
            }
            if currentHotkey != nil {
                Button("Remove hotkey", role: .destructive) {
                    HotkeyStorage.save(deviceID: deviceID, keys: nil)
                    currentHotkey = nil
                }
            }
            Divider()
            Button("Unpair", role: .destructive, action: onUnpair)
            Divider()
            Toggle("Launch at login", isOn: launchAtLoginBinding)
            #if !APPSTORE
            Button("Check for updates...") { UpdateChecker.check() }
            #endif
            Divider()
            Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showingHotkeyRecorder) {
            ShortcutRecorderView(deviceID: deviceID) { keys in
                currentHotkey = keys
                showingHotkeyRecorder = false
            }
        }
        .onAppear {
            currentHotkey = HotkeyStorage.load(deviceID: deviceID)
        }
    }

    private var hotkeyButtonTitle: String {
        if let keys = currentHotkey {
            return "Change hotkey (\(keys.displayString))"
        }
        return "Assign hotkey..."
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { newValue in
                try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        )
    }
}

struct ShortcutRecorderView: View {
    let deviceID: String
    let onRecorded: (ShortcutKeys?) -> Void
    @State private var isRecording = false
    @State private var recordedKeys: ShortcutKeys?

    var body: some View {
        VStack(spacing: 12) {
            Text(displayText)
                .font(.system(.title2, design: .monospaced))
                .foregroundStyle(isRecording && recordedKeys == nil ? .secondary : .primary)
                .frame(minWidth: 100, minHeight: 30)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)

            Text("Use ⌘, ⌥, ⌃, ⇧ with a key")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onRecorded(HotkeyStorage.load(deviceID: deviceID))
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    if let keys = recordedKeys {
                        HotkeyStorage.save(deviceID: deviceID, keys: keys)
                    }
                    onRecorded(recordedKeys)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(recordedKeys == nil)
            }
        }
        .padding(20)
        .frame(width: 220)
        .background(ShortcutRecorderHelper(isRecording: $isRecording, recordedKeys: $recordedKeys))
        .onAppear {
            isRecording = true
            recordedKeys = HotkeyStorage.load(deviceID: deviceID)
        }
        .onDisappear {
            isRecording = false
        }
    }

    private var displayText: String {
        if let keys = recordedKeys {
            return keys.displayString
        }
        return isRecording ? "Press keys..." : "None"
    }
}

struct ShortcutRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var recordedKeys: ShortcutKeys?

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcutRecorded = { keys in
            recordedKeys = keys
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.isRecording = isRecording
    }
}

final class ShortcutRecorderNSView: NSView {
    var isRecording = false
    var onShortcutRecorded: ((ShortcutKeys) -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupMonitor()
        } else {
            removeMonitor()
        }
    }

    private func setupMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !modifiers.isEmpty else { return event }

            let keyCode = event.keyCode
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            if modifierKeyCodes.contains(keyCode) { return event }

            let keys = ShortcutKeys(modifiers: modifiers.rawValue, keyCode: keyCode)
            DispatchQueue.main.async {
                self.onShortcutRecorded?(keys)
            }
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        removeMonitor()
    }
}

struct PanelCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 20, height: 20)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct PanelContentView: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        VStack(spacing: 0) {
            switch manager.connectionStatus {
            case .connecting, .connected:
                RemoteControlView()
            case .pairing:
                PairingView()
            case .error(let message):
                ErrorView(message: message)
            case .disconnected:
                SetupView()
            }
        }
        .frame(width: 176)
    }
}
