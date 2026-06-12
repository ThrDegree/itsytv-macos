# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Itsytv is a native macOS menu bar app for controlling Apple TVs. It is a thin SwiftUI layer over [itsytv-core](https://github.com/nickustinov/itsytv-core), a separate Swift package that implements the Apple TV Companion Link, AirPlay, and MRP protocols. Both repos must be cloned as siblings — the project references `../itsytv-core` as a local Swift package.

## Commands

### Setup (first time)
```bash
brew install xcodegen
xcodegen generate          # creates itsytv.xcodeproj from project.yml
open itsytv.xcodeproj
```

Re-run `xcodegen generate` any time `project.yml` changes (adding files, changing build settings, etc.).

### Build and test from the command line
```bash
xcodebuild -scheme itsytv -destination "platform=macOS" build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

xcodebuild -scheme itsytv -destination "platform=macOS" test \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

### Run a single test
Tests use Swift Testing (`@Test`, `#expect`). Run a specific test struct from the command line by filtering on its name, or use the Xcode test navigator.

### Release build
```bash
bash scripts/build-release.sh
```

## Architecture

### Thin UI over ItsytvCore
All protocol, crypto, discovery, and device-management logic lives in `../itsytv-core`. This repo only contains:
- The SwiftUI panel and menu bar glue
- Design system tokens
- Local utilities (hotkeys, launch-at-login, playback math, update checker)
- App Intents

### App lifecycle
`itsytvApp.swift` → `AppDelegate` creates `AppleTVManager` (from ItsytvCore) and `AppController`. There is no window — `AppController` owns the `NSStatusItem` and an `NSPopover` that is created fresh on each open and torn down on close (including disconnecting from the Apple TV).

### Connection and panel state machine
`AppController` observes `AppleTVManager.connectionStatus`. The `panelTransition(from:to:)` function in `PanelTransition.swift` maps status changes to `.show`, `.dismiss`, or `.none`. The panel is shown when status reaches `.connected` and dismissed when it returns to `.disconnected`.

### Panel content routing
`PanelContentView` switches between four views based on `connectionStatus`:
- `.connecting` / `.connected` → `RemoteControlView`
- `.pairing` → `PairingView`
- `.error` → `ErrorView`
- `.disconnected` → `SetupView`

### NowPlayingBar and MRP state
`NowPlayingBar` (inside `MenuBarView.swift`) reads `manager.mrpManager.nowPlaying: NowPlayingState?`. The MRP now-playing state is populated from Apple TV `setStateMessage` protobuf messages — the Apple TV sends a burst of these on connect, including stale content from previously-paused apps. `nowPlaying` is set to `nil` in `disconnect()` and when `supportedCommands` is reported as empty.

### Two targets / two entitlement files
- `Debug` / `Release` use `itsytv-direct.entitlements` (direct distribution, Hardened Runtime)
- `Debug-AppStore` / `Release-AppStore` use `itsytv.entitlements` and set `SWIFT_ACTIVE_COMPILATION_CONDITIONS = APPSTORE` — gates `#if !APPSTORE` blocks (update checker, iOS promo)

### Project generation
`project.yml` is the source of truth for build settings, targets, and schemes. `project.local.yml` (gitignored) holds per-machine overrides (team ID, code signing identity). Never edit `itsytv.xcodeproj` directly.

## Key ItsytvCore types (imported everywhere)
- `AppleTVManager` — `@Observable` top-level controller; owns discovery, connection, MRP, Companion protocol
- `MRPManager` — handles MRP protobuf messages, exposes `nowPlaying`, `supportedCommands`, `activeAppBundleID`
- `NowPlayingState` — value type; `isPlaying` is `playbackRate > 0`; `currentPosition` extrapolates from `elapsedTime + Δt × rate`
- `ConnectionStatus` — `.disconnected`, `.connecting`, `.pairing`, `.connected`, `.error(String)`
- `AppleTVDevice` — discovered device; `id` is the stable identifier used for pairing/keychain storage
