import SwiftUI
import Combine
import ServiceManagement
import ItsytvCore

enum RemoteTab: String, CaseIterable {
    case remote = "Remote"
    case apps = "Apps"
}

struct RemoteControlView: View {
    @Environment(AppleTVManager.self) private var manager
    @Environment(PairingCache.self) private var pairingCache
    @Environment(\.switchDeviceAction) private var switchDeviceAction
    @Environment(\.dismissAction) private var dismissAction
    @State private var selectedTab: RemoteTab = .remote
    @State private var showingKeyboard = false
    @State private var keyboardText = ""
    @State private var appSearchText = ""
    @State private var showUnpairHint = false
    @AppStorage("showAppsSearch") private var showAppsSearch = false

    private var isConnected: Bool {
        manager.connectionStatus == .connected
    }

    var body: some View {
        VStack(spacing: 10) {
            // Header — always interactive
            HStack(spacing: 8) {
                DeviceSwitcher(
                    currentName: manager.connectedDeviceName ?? "Apple TV",
                    currentID: manager.connectedDeviceID,
                    discoveredDevices: manager.discoveredDevices,
                    onSwitch: switchDeviceAction
                )
                Spacer()
                PanelMenuButton(deviceID: manager.connectedDeviceID ?? "") {
                    if let deviceID = manager.connectedDeviceID {
                        KeychainStorage.delete(for: deviceID)
                    }
                    dismissAction?()
                }
                PanelCloseButton { dismissAction?() }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // "Taking too long?" unpair hint
            if showUnpairHint && !isConnected {
                VStack(spacing: 4) {
                    Text("Taking too long?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Unpair this Apple TV") {
                        if let deviceID = manager.connectedDeviceID {
                            KeychainStorage.delete(for: deviceID)
                        }
                        dismissAction?()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }
                .transition(.opacity)
                .padding(.bottom, 4)
            }

            // Controls — dimmed while connecting
            VStack(spacing: 10) {
                // Tab picker
                CapsuleSegmentPicker(
                    selection: $selectedTab,
                    options: RemoteTab.allCases.map { ($0, $0.rawValue) }
                )
                .padding(.horizontal, 8)

                // Keyboard text input (pushes content down when visible)
                if showingKeyboard && selectedTab == .remote {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ComposeAwareTextField(
                            text: $keyboardText,
                            placeholder: "Type to search...",
                            onCommittedTextChange: { committed in
                                manager.updateRemoteText(committed)
                            },
                            onSubmit: {
                                keyboardText = ""
                                showingKeyboard = false
                                manager.resetTextInputState()
                            }
                        )
                        .font(.caption)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(Color(nsColor: DS.Colors.muted)))
                    .padding(.horizontal, 8)
                }

                // Content — remote is always rendered to maintain size
                ZStack(alignment: .top) {
                    ZStack {
                        // Remote always rendered (hidden when on apps to keep size)
                        VStack(spacing: 10) {
                            RemoteTabContent()
                            NowPlayingBar()
                        }
                        .opacity(selectedTab == .remote ? 1 : 0)
                        .allowsHitTesting(selectedTab == .remote)

                        // Apps overlaid on top when selected
                        if selectedTab == .apps {
                            AppGridView(searchText: $appSearchText)
                                .transition(.identity)
                        }
                    }
                    .animation(nil, value: selectedTab)

                    // Floating buttons over remote content
                    if selectedTab == .remote {
                        HStack {
                            // Keyboard button
                            Button {
                                showingKeyboard.toggle()
                                if !showingKeyboard {
                                    keyboardText = ""
                                    manager.resetTextInputState()
                                }
                            } label: {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.secondary.opacity(0.12)))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            // Power button (Control Center)
                            PowerButton {
                                manager.pressButton(.pageDown)
                            } onLongPress: {
                                manager.pressButton(.pageDown, action: .hold)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .opacity(isConnected ? 1 : 0.4)
            .allowsHitTesting(isConnected)
        }
        .onChange(of: manager.keyboardToggleCounter) { _, _ in
            showingKeyboard.toggle()
            if !showingKeyboard {
                keyboardText = ""
                manager.resetTextInputState()
            }
        }
        .onChange(of: showAppsSearch) { _, show in
            if show {
                selectedTab = .apps
            }
        }
        .onChange(of: manager.connectionStatus) { _, status in
            if status == .connected {
                withAnimation { showUnpairHint = false }
            } else if case .connecting = status {
                showUnpairHint = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if !isConnected {
                        withAnimation { showUnpairHint = true }
                    }
                }
            }
        }
    }
}

// MARK: - Device switcher

private struct DeviceSwitcher: View {
    let currentName: String
    let currentID: String?
    let discoveredDevices: [AppleTVDevice]
    let onSwitch: ((String) -> Void)?
    @Environment(PairingCache.self) private var pairingCache

    private var sorted: [AppleTVDevice] {
        discoveredDevices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var hasAlternativeDevices: Bool {
        sorted.contains(where: { $0.id != currentID })
    }

    var body: some View {
        if hasAlternativeDevices {
            Menu {
                let paired   = sorted.filter {  pairingCache.pairedIDs.contains($0.id) }
                let unpaired = sorted.filter { !pairingCache.pairedIDs.contains($0.id) }

                ForEach(paired, id: \.id) { device in
                    Button {
                        if device.id != currentID { onSwitch?(device.id) }
                    } label: {
                        if device.id == currentID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                    .disabled(device.id == currentID)
                }

                if !unpaired.isEmpty {
                    Divider()
                    ForEach(unpaired, id: \.id) { device in
                        Button {
                            onSwitch?(device.id)
                        } label: {
                            Label("Pair \(device.name)", systemImage: "plus.circle")
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(currentName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        } else {
            Text(currentName)
                .font(.subheadline)
                .lineLimit(1)
        }
    }
}

struct NowPlayingBar: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        let mrp = manager.mrpManager
        let np = mrp.nowPlaying
        let hasContent = np != nil

        VStack(spacing: 6) {
            // Artwork — full width, square
            if let data = np?.artworkData, let image = NSImage(data: data) {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
            }

            // Title + artist
            VStack(spacing: 2) {
                Text(np?.title ?? " ")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(np.flatMap { [$0.artist, $0.album].compactMap { $0 }.joined(separator: " — ") } ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(hasContent ? 1 : 0)

            // Controls — use HID button presses (not MRP commands) for play/pause
            // because apps like YouTube ignore MRP SendCommandMessage.
            HStack(spacing: 28) {
                Button {
                    mrp.sendCommand(.previousTrack)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!hasContent || !mrp.supportedCommands.contains(.previousTrack))

                Button {
                    manager.pressButton(.playPause)
                } label: {
                    Image(systemName: np?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .disabled(!hasContent)

                Button {
                    mrp.sendCommand(.nextTrack)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(!hasContent || !mrp.supportedCommands.contains(.nextTrack))
            }
            .foregroundStyle(.secondary)

            // Progress bar
            NowPlayingProgress(
                nowPlaying: np,
                duration: np?.duration ?? 0,
                onSeek: { position in mrp.seekToPosition(position) }
            )
            .opacity(hasContent && (np?.duration ?? 0) > 0 ? 1 : 0.3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

struct NowPlayingProgress: View {
    let nowPlaying: NowPlayingState?
    let duration: TimeInterval
    var onSeek: ((Double) -> Void)?

    @AppStorage("showRemainingTime") private var showRemainingTime = false
    @State private var currentTime: TimeInterval = 0
    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0
    /// After seeking, hold the seeked position until the server catches up.
    @State private var pendingSeekTarget: TimeInterval?
    private let timer = Timer.publish(every: 1, on: .main, in: .common)
    @State private var timerConnection: (any Cancellable)?

    private var displayTime: TimeInterval {
        if isSeeking { return seekTime }
        if let target = pendingSeekTarget { return target }
        return currentTime
    }

    private var progress: Double {
        seekProgress(time: displayTime, duration: duration)
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.quaternary)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.secondary)
                        .frame(width: max(0, geo.size.width * progress), height: 3)
                }
                .frame(height: 12)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isSeeking = true
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            seekTime = fraction * duration
                        }
                        .onEnded { value in
                            guard duration > 0 else { return }
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            let position = fraction * duration
                            onSeek?(position)
                            currentTime = position
                            pendingSeekTarget = position
                            isSeeking = false
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(formatTime(displayTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(showRemainingTime ? "-\(formatTime(duration - displayTime))" : formatTime(duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .onTapGesture { showRemainingTime.toggle() }
            }
        }
        .onAppear {
            currentTime = nowPlaying?.currentPosition ?? 0
            timerConnection = timer.connect()
        }
        .onDisappear {
            timerConnection?.cancel()
            timerConnection = nil
        }
        .onReceive(timer) { _ in
            if !isSeeking {
                let serverTime = nowPlaying?.currentPosition ?? 0
                if let target = pendingSeekTarget {
                    // Clear hold once the server reports a position near the seek target
                    if abs(serverTime - target) < 3 {
                        pendingSeekTarget = nil
                        currentTime = serverTime
                    }
                } else {
                    currentTime = serverTime
                }
            }
        }
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        formatPlaybackTime(seconds)
    }
}

struct RemoteTabContent: View {
    @Environment(AppleTVManager.self) private var manager
    private let padding: CGFloat = 8
    private let buttonSize: CGFloat = 60
    private let buttonGap: CGFloat = 12

    var body: some View {
        let dpadSize: CGFloat = 150

        VStack(spacing: 4) {
            // D-pad
            DPadView(onPress: { button, action in manager.pressButton(button, action: action) }, size: dpadSize)
                .padding(.top, 15)

            // Buttons matching Apple TV remote layout
            VStack(spacing: buttonGap) {
                // Row 1: Back + TV/Home
                HStack(spacing: buttonGap) {
                    RemoteCircleButton(imageName: "btnBack", button: .menu, shortcut: "Esc", size: buttonSize) { action in
                        if action == .hold {
                            manager.pressButton(.home)
                        } else {
                            manager.pressButton(.menu, action: action)
                        }
                    }
                    RemoteCircleButton(imageName: "btnHome", button: .home, shortcut: "⌫", size: buttonSize) { action in
                        manager.pressButton(.home, action: action)
                    }
                }

                // Rows 2-3: Play/Pause + Mute left, Volume pill right
                HStack(alignment: .top, spacing: buttonGap) {
                    VStack(spacing: buttonGap) {
                        RemoteCircleButton(imageName: "btnPlayPause", button: .playPause, shortcut: "Space", size: buttonSize) { action in
                            manager.pressButton(.playPause, action: action)
                        }
                        RemoteCircleButton(imageName: "btnMute", button: .siri, shortcut: "⌘⇧M", size: buttonSize) { action in
                            guard action == .click else { return }
                            manager.toggleMute()
                        }
                    }

                    VolumePill(
                        width: buttonSize,
                        height: buttonSize * 2 + buttonGap,
                        onUp: { manager.pressButton(.volumeUp) },
                        onDown: { manager.pressButton(.volumeDown) }
                    )
                }
            }

        }
        .padding(.horizontal, padding)
        .padding(.bottom, 12)
    }
}


struct AppGridView: View {
    @Binding var searchText: String
    @AppStorage("showAppsSearch") private var showAppsSearch = false
    @Environment(AppleTVManager.self) private var manager
    @Environment(AppIconLoader.self) private var iconLoader
    @State private var apps: [(bundleID: String, name: String)] = []
    @State private var draggingBundleID: String?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    private var filteredApps: [(bundleID: String, name: String)] {
        guard !searchText.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        if manager.installedApps.isEmpty {
            if manager.osVersion?.hasPrefix("26.5") == true {
                VStack(spacing: 8) {
                    Text("Apps unavailable in tvOS 26.5")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                    Text("We are working on the fix for tvOS 26.5")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading apps...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                if showAppsSearch {
                    // Search bar
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ComposeAwareTextField(
                            text: $searchText,
                            placeholder: "Search apps...",
                            onCommittedTextChange: { _ in },
                            onSubmit: { }
                        )
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(Color(nsColor: DS.Colors.muted)))
                    .padding(.horizontal, 16)
                }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredApps, id: \.bundleID) { app in
                        appView(for: app)
                            .opacity(draggingBundleID == app.bundleID ? 0.5 : 1)
                            .onDrag {
                                draggingBundleID = app.bundleID
                                return NSItemProvider(object: app.bundleID as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: AppReorderDropDelegate(
                                    targetBundleID: app.bundleID,
                                    apps: $apps,
                                    draggingBundleID: $draggingBundleID,
                                    onReorder: { manager.saveAppOrder($0.map(\.bundleID)) }
                                )
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .onAppear {
                apps = manager.orderedApps
                iconLoader.loadIcons(for: manager.installedApps)
            }
            .onChange(of: manager.installedApps.map(\.bundleID)) {
                apps = manager.orderedApps
                iconLoader.loadIcons(for: manager.installedApps)
            }
            .onChange(of: showAppsSearch) { _, show in
                if !show { searchText = "" }
            }
            } // VStack
        }
    }

    @ViewBuilder
    private func appView(for app: (bundleID: String, name: String)) -> some View {
        if let symbolName = AppIconFetcher.builtInSymbols[app.bundleID] {
            AppleAppButton(name: app.name, symbolName: symbolName) {
                manager.launchApp(bundleID: app.bundleID)
            }
        } else {
            AppButton(name: app.name, icon: iconLoader.icons[app.bundleID]) {
                manager.launchApp(bundleID: app.bundleID)
            }
        }
    }
}

private struct AppReorderDropDelegate: DropDelegate {
    let targetBundleID: String
    @Binding var apps: [(bundleID: String, name: String)]
    @Binding var draggingBundleID: String?
    let onReorder: ([(bundleID: String, name: String)]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging = draggingBundleID,
              dragging != targetBundleID,
              let fromIndex = apps.firstIndex(where: { $0.bundleID == dragging }),
              let toIndex = apps.firstIndex(where: { $0.bundleID == targetBundleID }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            apps.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        onReorder(apps)
        draggingBundleID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {}
}

struct AppButton: View {
    let name: String
    let icon: NSImage?
    let action: () -> Void

    private let iconHeight: CGFloat = 42
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let icon {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: iconHeight)
                        .overlay {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.quaternary)
                        .frame(maxWidth: .infinity)
                        .frame(height: iconHeight)
                        .overlay {
                            Image(systemName: "app.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
    }
}

struct AppleAppButton: View {
    let name: String
    let symbolName: String?
    let action: () -> Void

    private let iconHeight: CGFloat = 42
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.quaternary)
                    .frame(maxWidth: .infinity)
                    .frame(height: iconHeight)
                    .overlay {
                        Image(systemName: symbolName ?? "app.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Native gesture handler (no 300ms SwiftUI tap disambiguation delay)

private struct RemoteButtonGesture: NSViewRepresentable {
    let onInput: (InputAction) -> Void

    func makeNSView(context: Context) -> RemoteButtonGestureNSView {
        let view = RemoteButtonGestureNSView()
        view.onInput = onInput
        return view
    }

    func updateNSView(_ nsView: RemoteButtonGestureNSView, context: Context) {
        nsView.onInput = onInput
    }
}

private class RemoteButtonGestureNSView: NSView {
    var onInput: ((InputAction) -> Void)?
    private var holdTimer: Timer?
    private var holdFired = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        holdFired = false
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.holdFired = true
            self.onInput?(.hold)
        }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        guard !holdFired else { return }
        onInput?(.click)
    }
}

struct DPadView: View {
    @Environment(AppleTVManager.self) private var manager
    let onPress: (CompanionButton, InputAction) -> Void
    let size: CGFloat
    @State private var blinkOpacity: Double = 0

    private static let dpadButtons: Set<CompanionButton> = [.up, .down, .left, .right, .select]

    private func press(_ button: CompanionButton, _ action: InputAction) {
        blink()
        onPress(button, action)
    }

    private func blink() {
        blinkOpacity = 0.25
        withAnimation(.easeOut(duration: 0.2)) { blinkOpacity = 0 }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: DS.Colors.remoteButton))
                .frame(width: size, height: size)

            // Center select button — larger, subtly distinct from outer ring
            Circle()
                .fill(Color(nsColor: DS.Colors.remoteButtonForeground).opacity(0.08))
                .frame(width: size * 0.5, height: size * 0.5)
                .overlay(RemoteButtonGesture { action in press(.select, action) })
                .help("Return")

            // Direction dots
            VStack {
                DPadDot(shortcut: "↑") { action in press(.up, action) }
                Spacer()
                DPadDot(shortcut: "↓") { action in press(.down, action) }
            }
            .frame(height: size)
            .padding(.vertical, 12)

            HStack {
                DPadDot(shortcut: "←") { action in press(.left, action) }
                Spacer()
                DPadDot(shortcut: "→") { action in press(.right, action) }
            }
            .frame(width: size)
            .padding(.horizontal, 12)

            Circle()
                .fill(.white.opacity(blinkOpacity))
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
        .onChange(of: manager.keyboardBlinkCounter) { _, _ in
            if Self.dpadButtons.contains(manager.keyboardBlinkButton) { blink() }
        }
    }
}

struct DPadDot: View {
    let shortcut: String
    let action: (InputAction) -> Void

    var body: some View {
        Circle()
            .fill(Color(nsColor: DS.Colors.remoteButtonForeground))
            .frame(width: 5, height: 5)
            .frame(width: 30, height: 30)
            .overlay(RemoteButtonGesture(onInput: action))
            .help(shortcut)
    }
}

struct RemoteCircleButton: View {
    @Environment(AppleTVManager.self) private var manager
    let imageName: String
    let button: CompanionButton
    let shortcut: String
    let size: CGFloat
    let action: (InputAction) -> Void
    @State private var blinkOpacity: Double = 0

    private func press(_ input: InputAction) {
        blink()
        action(input)
    }

    private func blink() {
        blinkOpacity = 0.25
        withAnimation(.easeOut(duration: 0.2)) { blinkOpacity = 0 }
    }

    var body: some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size * 0.33, height: size * 0.33)
            .frame(width: size, height: size)
            .background(Circle().fill(Color(nsColor: DS.Colors.remoteButton)))
            .overlay(Circle().fill(.white.opacity(blinkOpacity)).allowsHitTesting(false))
            .overlay(RemoteButtonGesture { input in press(input) })
            .help(shortcut)
            .onChange(of: manager.keyboardBlinkCounter) { _, _ in
                if manager.keyboardBlinkButton == button { blink() }
            }
    }
}

struct VolumePill: View {
    @Environment(AppleTVManager.self) private var manager
    let width: CGFloat
    let height: CGFloat
    let onUp: () -> Void
    let onDown: () -> Void
    @State private var blinkOpacity: Double = 0

    private func blink() {
        blinkOpacity = 0.25
        withAnimation(.easeOut(duration: 0.2)) { blinkOpacity = 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { blink(); onUp() }) {
                Image(systemName: "plus")
                    .font(.system(size: width * 0.3, weight: .medium))
                    .foregroundStyle(Color(nsColor: DS.Colors.remoteButtonForeground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("+")

            Button(action: { blink(); onDown() }) {
                Image(systemName: "minus")
                    .font(.system(size: width * 0.3, weight: .medium))
                    .foregroundStyle(Color(nsColor: DS.Colors.remoteButtonForeground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("−")
        }
        .frame(width: width, height: height)
        .background(Capsule().fill(Color(nsColor: DS.Colors.remoteButton)))
        .overlay(Capsule().fill(.white.opacity(blinkOpacity)).allowsHitTesting(false))
        .clipShape(Capsule())
        .onChange(of: manager.keyboardBlinkCounter) { _, _ in
            if manager.keyboardBlinkButton == .volumeUp || manager.keyboardBlinkButton == .volumeDown {
                blink()
            }
        }
    }
}

private struct PowerButton: View {
    let onTap: () -> Void
    let onLongPress: () -> Void
    @State private var didLongPress = false

    init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    var body: some View {
        Image(systemName: "power")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.secondary.opacity(0.12)))
            .onTapGesture {
                guard !didLongPress else {
                    didLongPress = false
                    return
                }
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                didLongPress = true
                onLongPress()
            }
    }
}

// MARK: - Pairing view

struct PairingView: View {
    @Environment(AppleTVManager.self) private var manager
    @Environment(\.dismissAction) private var dismissAction
    @State private var digits: [Int?] = [nil, nil, nil, nil]

    private var currentIndex: Int {
        digits.firstIndex(where: { $0 == nil }) ?? 4
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Enter PIN from your Apple TV")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                PanelCloseButton { dismissAction?() }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    PairingDigitCell(digit: digits[i], isFocused: i == currentIndex)
                }
            }
            .padding(.bottom, 20)
        }
        .background(
            PairingKeyCapture(
                onDigit: { digit in
                    guard currentIndex < 4 else { return }
                    digits[currentIndex] = digit
                    if digits.allSatisfy({ $0 != nil }) {
                        let pin = digits.compactMap { $0 }.map(String.init).joined()
                        manager.submitPIN(pin)
                    }
                },
                onBackspace: {
                    let idx = currentIndex - 1
                    guard idx >= 0 else { return }
                    digits[idx] = nil
                }
            )
        )
    }
}

private struct PairingDigitCell: View {
    let digit: Int?
    let isFocused: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.md)
            .fill(Color(nsColor: DS.Colors.muted))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(
                        isFocused
                            ? Color(nsColor: DS.Colors.foreground).opacity(0.5)
                            : Color(nsColor: DS.Colors.border),
                        lineWidth: 2
                    )
            )
            .overlay(
                Text(digit.map(String.init) ?? "")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: DS.Colors.foreground))
            )
            .frame(width: 36, height: 44)
    }
}

private struct PairingKeyCapture: NSViewRepresentable {
    let onDigit: (Int) -> Void
    let onBackspace: () -> Void

    func makeNSView(context: Context) -> PairingKeyNSView {
        let view = PairingKeyNSView()
        view.onDigit = onDigit
        view.onBackspace = onBackspace
        return view
    }

    func updateNSView(_ nsView: PairingKeyNSView, context: Context) {
        nsView.onDigit = onDigit
        nsView.onBackspace = onBackspace
    }
}

private final class PairingKeyNSView: NSView {
    var onDigit: ((Int) -> Void)?
    var onBackspace: (() -> Void)?
    private var monitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupMonitor()
            DispatchQueue.main.async { self.window?.makeFirstResponder(self) }
        } else {
            removeMonitor()
        }
    }

    private func setupMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard let chars = event.characters else { return event }
            for ch in chars {
                if let digit = ch.wholeNumberValue {
                    self.onDigit?(digit)
                    return nil
                } else if ch == "\u{7F}" || ch == "\u{08}" {
                    self.onBackspace?()
                    return nil
                }
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit { removeMonitor() }
}

struct ErrorView: View {
    @Environment(\.dismissAction) private var dismissAction
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Dismiss") {
                dismissAction?()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}

// MARK: - Setup view (first-time / no paired devices)

struct SetupView: View {
    @Environment(AppleTVManager.self) private var manager
    @Environment(\.dismissAction) private var dismissAction

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Apple TV")
                    .font(.subheadline.weight(.medium))
                Spacer()
                PanelCloseButton { dismissAction?() }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if manager.discoveredDevices.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Scanning for Apple TVs...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                VStack(spacing: 2) {
                    ForEach(
                        manager.discoveredDevices.sorted {
                            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                        },
                        id: \.id
                    ) { device in
                        SetupDeviceRow(device: device)
                    }
                }
                .padding(.horizontal, 4)
                Spacer()
            }
        }
    }
}

private struct SetupDeviceRow: View {
    @Environment(AppleTVManager.self) private var manager
    let device: AppleTVDevice

    var body: some View {
        Button {
            manager.connect(to: device)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "appletv.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(device.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("Pair")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @Environment(AppleTVManager.self) private var manager

    var body: some View {
        Form {
            Section("Paired devices") {
                let deviceIDs = KeychainStorage.allPairedDeviceIDs()
                if deviceIDs.isEmpty {
                    Text("No paired devices")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(deviceIDs, id: \.self) { id in
                        HStack {
                            Image(systemName: "appletv.fill")
                            Text(id)
                            Spacer()
                            Button("Remove") {
                                KeychainStorage.delete(for: id)
                            }
                            .foregroundStyle(.red)
                        }
                    }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}

