import AppKit
import SwiftUI
import Combine
import ServiceManagement
import os.log
import ObjectiveC
import ItsytvCore

// MARK: - Environment key for device switching

private struct SwitchDeviceActionKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var switchDeviceAction: ((String) -> Void)? {
        get { self[SwitchDeviceActionKey.self] }
        set { self[SwitchDeviceActionKey.self] = newValue }
    }
}

// MARK: - Pairing cache
// Caches paired device IDs so Keychain is only hit at quiet moments,
// not during menuWillOpen or SwiftUI renders.

@Observable
final class PairingCache {
    private(set) var pairedIDs: Set<String> = []

    func refresh() {
        pairedIDs = Set(KeychainStorage.allPairedDeviceIDs())
    }
}

private let log = Logger(subsystem: "com.itsytv.app", category: "Panel")

final class AppController: NSObject, NSMenuDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let menu = NSMenu()
    private let manager: AppleTVManager
    private let iconLoader: AppIconLoader
    private let pairingCache = PairingCache()
    private var observation: AnyCancellable?
    private var panel: NSPanel?
    private var panelDeviceID: String?
    private var keyboardMonitor: Any?
    private var clickOutsideMonitor: Any?
    private var alwaysOnTopObserver: NSObjectProtocol?

    init(manager: AppleTVManager, iconLoader: AppIconLoader) {
        self.manager = manager
        self.iconLoader = iconLoader
        super.init()
        pairingCache.refresh()
        setupStatusItem()
        rebuildMenu()
        startObserving()
        setupHotkeyHandler()
        manager.startScanning()
    }

    func cleanup() {
        removeKeyboardMonitor()
        removeClickOutsideMonitor()
        if let observer = alwaysOnTopObserver {
            NotificationCenter.default.removeObserver(observer)
            alwaysOnTopObserver = nil
        }
        observation?.cancel()
        observation = nil
        HotkeyManager.shared.unregisterAll()
        panel?.close()
        panel = nil
        panelDeviceID = nil
    }

    private func setupHotkeyHandler() {
        HotkeyManager.shared.reregisterAll()
        HotkeyManager.shared.onHotkeyPressed = { [weak self] deviceID in
            guard let self else { return }
            if self.panel?.isVisible == true && self.panelDeviceID == deviceID {
                self.manager.disconnect()
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
            // Prefer last-used device; fall back to first paired discovered device
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
        menu.delegate = self
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true {
            manager.disconnect()
            return
        }

        if !pairingCache.pairedIDs.isEmpty {
            openRemote()
        } else {
            // No paired devices yet — show the full menu for first-time pairing.
            showFullMenu()
        }
    }

    private func showFullMenu() {
        rebuildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
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

        // Fulfill pending openRemote when the target device is discovered
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
            dismissPanel()
        case .connected:
            if case .pairing = previousStatus { pairingCache.refresh() }
            menu.cancelTracking()
            showPanel()
        default:
            break
        }
    }

    // MARK: - Menu building

    private func rebuildMenu() {
        menu.removeAllItems()
        buildDeviceList()
    }

    private func buildDeviceList() {
        if manager.discoveredDevices.isEmpty {
            let scanning = NSMenuItem(title: "Scanning for devices...", action: nil, keyEquivalent: "")
            scanning.isEnabled = false
            menu.addItem(scanning)
        } else {
            let sorted = manager.discoveredDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for device in sorted {
                let isPaired = pairingCache.pairedIDs.contains(device.id)
                let item = createDeviceItem(device: device, isPaired: isPaired)
                menu.addItem(item)
            }
        }
    }

    private func createDeviceItem(device: AppleTVDevice, isPaired: Bool) -> NSMenuItem {
        let height = DS.ControlSize.menuItemHeight
        let width = DS.ControlSize.menuItemWidth

        let containerView = HighlightingMenuItemView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        containerView.closesMenuOnAction = isPaired

        // Icon (green for paired devices)
        let iconSize = DS.ControlSize.iconMedium
        let iconY = (height - iconSize) / 2
        let iconView = NSImageView(frame: NSRect(x: DS.Spacing.md, y: iconY, width: iconSize, height: iconSize))
        iconView.image = NSImage(systemSymbolName: "appletv.fill", accessibilityDescription: nil)
        iconView.contentTintColor = isPaired ? .systemGreen : DS.Colors.iconForeground
        iconView.imageScaling = .scaleProportionallyUpOrDown
        containerView.addSubview(iconView)

        // Hotkey (right-aligned, for paired devices with assigned hotkey)
        let rightPadding: CGFloat = 20
        var labelRightEdge = width - rightPadding
        if isPaired, let keys = HotkeyStorage.load(deviceID: device.id) {
            let hotkeyFont = NSFont.menuFont(ofSize: 13)
            let hotkeyStr = keys.displayString
            let hotkeyAttr = NSAttributedString(string: hotkeyStr, attributes: [.font: hotkeyFont])
            let hotkeyTextSize = hotkeyAttr.size()
            let hotkeyW = ceil(hotkeyTextSize.width) + 4
            let hotkeyX = width - rightPadding - hotkeyW
            let hotkeyY = (height - hotkeyTextSize.height) / 2

            let hotkeyLabel = NSTextField(labelWithString: hotkeyStr)
            hotkeyLabel.frame = NSRect(x: hotkeyX, y: hotkeyY, width: hotkeyW, height: hotkeyTextSize.height)
            hotkeyLabel.font = hotkeyFont
            hotkeyLabel.textColor = .tertiaryLabelColor
            containerView.addSubview(hotkeyLabel)
            labelRightEdge = hotkeyX - DS.Spacing.sm
        }

        // Name label
        let labelX = DS.Spacing.md + iconSize + DS.Spacing.sm
        let labelY = (height - 17) / 2
        let labelWidth = labelRightEdge - labelX
        let nameLabel = NSTextField(labelWithString: device.name)
        nameLabel.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: 17)
        nameLabel.font = DS.Typography.label
        nameLabel.textColor = DS.Colors.foreground
        nameLabel.lineBreakMode = .byTruncatingTail
        containerView.addSubview(nameLabel)

        containerView.onAction = { [weak self] in
            self?.openRemote(for: device.id)
        }

        let item = NSMenuItem(title: device.name, action: nil, keyEquivalent: "")
        item.view = containerView
        return item
    }

    // MARK: - Panel

    private func showPanel() {
        if panel != nil {
            return
        }

        let panelContent = PanelContentView()
            .environment(manager)
            .environment(iconLoader)
            .environment(pairingCache)
            .environment(\.switchDeviceAction, { [weak self] deviceID in
                self?.switchDevice(to: deviceID)
            })

        let hostingView = ArrowCursorHostingView(rootView: panelContent)
        hostingView.safeAreaRegions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Vibrancy view as the contentView itself
        let vibrancy = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 176, height: 400))
        vibrancy.material = .menu
        vibrancy.state = .active
        vibrancy.wantsLayer = true
        vibrancy.layer?.cornerRadius = 10
        vibrancy.layer?.masksToBounds = true
        vibrancy.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: vibrancy.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: vibrancy.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: vibrancy.trailingAnchor),
        ])

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 176, height: 400),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = vibrancy
        let alwaysOnTop = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
        panel.isFloatingPanel = alwaysOnTop
        panel.level = alwaysOnTop ? .statusBar : .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        if !alwaysOnTop {
            panel.styleMask.remove(.nonactivatingPanel)
            panel.syncActivationBehavior()
        }
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.hasShadow = true

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Position after makeKeyAndOrderFront — AppKit constrains the
        // frame during ordering for .statusBar level panels, so we must
        // set the origin after the window is on screen.
        if let statusButtonFrame = statusItemButtonFrameInScreen() {
            let x = statusButtonFrame.midX - (panel.frame.width / 2)
            let y = statusButtonFrame.minY - panel.frame.height
            log.info("showPanel: anchoring to status item at (\(x), \(y))")
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main?.visibleFrame {
            let x = screen.midX - (panel.frame.width / 2)
            let y = screen.maxY - panel.frame.height - 8
            log.warning("showPanel: missing status item frame, using screen fallback (\(x), \(y))")
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            log.warning("showPanel: missing status item and screen frames")
        }

        self.panel = panel
        self.panelDeviceID = manager.connectedDeviceID
        installKeyboardMonitor()
        installClickOutsideMonitor()

        // Observe "Always on top" toggle changes while panel is open
        alwaysOnTopObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            let onTop = UserDefaults.standard.object(forKey: "alwaysOnTop") as? Bool ?? true
            panel.isFloatingPanel = onTop
            panel.level = onTop ? .statusBar : .normal
            if onTop {
                panel.styleMask.insert(.nonactivatingPanel)
            } else {
                panel.styleMask.remove(.nonactivatingPanel)
            }
            panel.syncActivationBehavior()
            if !onTop {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func dismissPanel() {
        removeKeyboardMonitor()
        removeClickOutsideMonitor()
        if let observer = alwaysOnTopObserver {
            NotificationCenter.default.removeObserver(observer)
            alwaysOnTopObserver = nil
        }
        panel?.close()
        panel = nil
        panelDeviceID = nil
    }

    private func statusItemButtonFrameInScreen() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isVisible == true else { return event }
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
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let loc = NSEvent.mouseLocation
            if !panel.frame.contains(loc) {
                self.manager.disconnect()
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
        // Let the pairing view handle all keyboard input during pairing.
        if case .pairing = manager.connectionStatus { return false }

        // Cmd shortcuts work even when text input is focused
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 13, 4: // Cmd+W, Cmd+H
                manager.disconnect()
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

        // Cmd+Shift shortcuts
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

        // Ignore when any text input is focused (field editor, NSTextField, or SwiftUI text)
        if let responder = panel?.firstResponder {
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

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        manager.refreshScanning()
        rebuildMenu()
    }
}

// MARK: - Panel SwiftUI content

// MARK: - Key-capable panel

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension NSPanel {
    /// Sync the WindowServer activation tag after changing `.nonactivatingPanel`.
    /// AppKit bug: toggling the style mask flag alone does not update the
    /// underlying `kCGSPreventsActivationTagBit` tag (FB16484811).
    func syncActivationBehavior() {
        #if !APPSTORE
        let prevents = styleMask.contains(.nonactivatingPanel)
        let sel = Selector(("_setPreventsActivation:"))
        guard let method = class_getMethodImplementation(type(of: self), sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        let fn = unsafeBitCast(method, to: Fn.self)
        fn(self, sel, ObjCBool(prevents))
        #endif
    }
}

// MARK: - Arrow cursor hosting view

private final class ArrowCursorHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func addCursorRect(_ rect: NSRect, cursor: NSCursor) {
        super.addCursorRect(rect, cursor: .arrow)
    }
}

struct PanelMenuButton: View {
    let deviceID: String
    let onUnpair: () -> Void
    @AppStorage("alwaysOnTop") private var alwaysOnTop = true
    @AppStorage("showAppsSearch") private var showAppsSearch = false
    @State private var showingHotkeyRecorder = false
    @State private var currentHotkey: ShortcutKeys?

    var body: some View {
        Menu {
            Toggle("Always on top", isOn: $alwaysOnTop)
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

            // Require at least one modifier
            guard !modifiers.isEmpty else { return event }

            // Ignore if only modifier keys pressed (no actual key)
            let keyCode = event.keyCode
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Cmd, Shift, Option, Ctrl variants
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
            default:
                EmptyView()
            }
        }
        .frame(width: 176)
    }
}

// MARK: - NSWindowDelegate

extension AppController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSPanel) === panel {
            if manager.connectionStatus != .disconnected {
                manager.disconnect()
            }
            panel = nil
            panelDeviceID = nil
        }
    }
}

