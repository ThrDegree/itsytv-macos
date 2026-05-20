import Testing
import Foundation

// Raw modifier flag values (NSEvent.ModifierFlags):
//   control  = 262144  (0x40000)
//   option   = 524288  (0x80000)
//   shift    = 131072  (0x20000)
//   command  = 1048576 (0x100000)
//
// Special key codes (Carbon kVK_*):
//   Return = 36, Tab = 48, Space = 49, Delete = 51, Escape = 53
//   F1 = 122, F12 = 111
//   Up = 126, Down = 125, Left = 123, Right = 124

private let cmd: UInt    = 1048576
private let opt: UInt    = 524288
private let shift: UInt  = 131072
private let ctrl: UInt   = 262144

struct ShortcutKeysDisplayTests {

    // MARK: - Individual modifiers

    @Test func commandPrefix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 36).displayString.hasPrefix("⌘"))
    }

    @Test func optionPrefix() {
        #expect(ShortcutKeys(modifiers: opt, keyCode: 36).displayString.hasPrefix("⌥"))
    }

    @Test func shiftPrefix() {
        #expect(ShortcutKeys(modifiers: shift, keyCode: 36).displayString.hasPrefix("⇧"))
    }

    @Test func controlPrefix() {
        #expect(ShortcutKeys(modifiers: ctrl, keyCode: 36).displayString.hasPrefix("⌃"))
    }

    // MARK: - Modifier ordering (⌃⌥⇧⌘)

    @Test func allModifiersOrder() {
        let all = ctrl | opt | shift | cmd
        #expect(ShortcutKeys(modifiers: all, keyCode: 53).displayString == "⌃⌥⇧⌘⎋")
    }

    @Test func controlOptionOrder() {
        #expect(ShortcutKeys(modifiers: ctrl | opt, keyCode: 53).displayString == "⌃⌥⎋")
    }

    @Test func shiftCommandOrder() {
        #expect(ShortcutKeys(modifiers: shift | cmd, keyCode: 53).displayString == "⇧⌘⎋")
    }

    // MARK: - Special key suffix (no TIS lookup)

    @Test func returnSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 36).displayString.hasSuffix("↩"))
    }

    @Test func tabSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 48).displayString.hasSuffix("⇥"))
    }

    @Test func spaceSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 49).displayString.hasSuffix("Space"))
    }

    @Test func deleteSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 51).displayString.hasSuffix("⌫"))
    }

    @Test func escapeSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 53).displayString.hasSuffix("⎋"))
    }

    @Test func upArrowSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 126).displayString.hasSuffix("↑"))
    }

    @Test func downArrowSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 125).displayString.hasSuffix("↓"))
    }

    @Test func leftArrowSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 123).displayString.hasSuffix("←"))
    }

    @Test func rightArrowSuffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 124).displayString.hasSuffix("→"))
    }

    @Test func f1Suffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 122).displayString.hasSuffix("F1"))
    }

    @Test func f12Suffix() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 111).displayString.hasSuffix("F12"))
    }

    // MARK: - Codable round-trip

    @Test func codableRoundTrip() throws {
        let original = ShortcutKeys(modifiers: cmd | shift, keyCode: 36)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortcutKeys.self, from: data)
        #expect(decoded == original)
    }

    @Test func codablePreservesAllFields() throws {
        let modifiers = ctrl | opt | shift | cmd
        let original = ShortcutKeys(modifiers: modifiers, keyCode: 53)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShortcutKeys.self, from: data)
        #expect(decoded.modifiers == modifiers)
        #expect(decoded.keyCode == 53)
    }

    // MARK: - Equatable

    @Test func equalValues() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 36) == ShortcutKeys(modifiers: cmd, keyCode: 36))
    }

    @Test func differentKeyCode() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 36) != ShortcutKeys(modifiers: cmd, keyCode: 48))
    }

    @Test func differentModifiers() {
        #expect(ShortcutKeys(modifiers: cmd, keyCode: 36) != ShortcutKeys(modifiers: opt, keyCode: 36))
    }
}

@Suite(.serialized)
struct HotkeyStorageTests {

    private static let key = "deviceHotkeys"

    @Test func loadAllEmptyWhenNoData() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        #expect(HotkeyStorage.loadAll().isEmpty)
    }

    @Test func loadAllEmptyOnCorruptData() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: Self.key)
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        #expect(HotkeyStorage.loadAll().isEmpty)
    }

    @Test func loadAllDecodesStoredEntry() throws {
        let keys = ShortcutKeys(modifiers: cmd, keyCode: 36)
        UserDefaults.standard.set(try JSONEncoder().encode(["tv-1": keys]), forKey: Self.key)
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        #expect(HotkeyStorage.loadAll()["tv-1"] == keys)
    }

    @Test func loadReturnsKeyForDevice() throws {
        let keys = ShortcutKeys(modifiers: opt, keyCode: 126)
        UserDefaults.standard.set(try JSONEncoder().encode(["tv-1": keys]), forKey: Self.key)
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        #expect(HotkeyStorage.load(deviceID: "tv-1") == keys)
    }

    @Test func loadReturnsNilForAbsentDevice() throws {
        let keys = ShortcutKeys(modifiers: cmd, keyCode: 53)
        UserDefaults.standard.set(try JSONEncoder().encode(["tv-1": keys]), forKey: Self.key)
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        #expect(HotkeyStorage.load(deviceID: "tv-2") == nil)
    }

    @Test func loadAllMultipleDevices() throws {
        let k1 = ShortcutKeys(modifiers: cmd, keyCode: 36)
        let k2 = ShortcutKeys(modifiers: opt, keyCode: 126)
        UserDefaults.standard.set(try JSONEncoder().encode(["d1": k1, "d2": k2]), forKey: Self.key)
        defer { UserDefaults.standard.removeObject(forKey: Self.key) }
        let all = HotkeyStorage.loadAll()
        #expect(all.count == 2)
        #expect(all["d1"] == k1)
        #expect(all["d2"] == k2)
    }

    // MARK: - Save round-trip

    @Test func saveAndLoadRoundTrip() {
        let keys = ShortcutKeys(modifiers: cmd | shift, keyCode: 36)
        HotkeyStorage.save(deviceID: "tv-rt", keys: keys)
        defer { HotkeyStorage.save(deviceID: "tv-rt", keys: nil) }
        #expect(HotkeyStorage.load(deviceID: "tv-rt") == keys)
    }

    @Test func saveNilRemovesEntry() {
        let keys = ShortcutKeys(modifiers: cmd, keyCode: 53)
        HotkeyStorage.save(deviceID: "tv-del", keys: keys)
        HotkeyStorage.save(deviceID: "tv-del", keys: nil)
        #expect(HotkeyStorage.load(deviceID: "tv-del") == nil)
    }

    @Test func saveOverwritesExistingEntry() {
        let original = ShortcutKeys(modifiers: cmd, keyCode: 36)
        let updated  = ShortcutKeys(modifiers: opt, keyCode: 126)
        HotkeyStorage.save(deviceID: "tv-ow", keys: original)
        HotkeyStorage.save(deviceID: "tv-ow", keys: updated)
        defer { HotkeyStorage.save(deviceID: "tv-ow", keys: nil) }
        #expect(HotkeyStorage.load(deviceID: "tv-ow") == updated)
    }

    @Test func saveDoesNotAffectOtherDevices() {
        let k1 = ShortcutKeys(modifiers: cmd, keyCode: 36)
        let k2 = ShortcutKeys(modifiers: opt, keyCode: 126)
        HotkeyStorage.save(deviceID: "tv-a", keys: k1)
        HotkeyStorage.save(deviceID: "tv-b", keys: k2)
        defer {
            HotkeyStorage.save(deviceID: "tv-a", keys: nil)
            HotkeyStorage.save(deviceID: "tv-b", keys: nil)
        }
        #expect(HotkeyStorage.load(deviceID: "tv-a") == k1)
        #expect(HotkeyStorage.load(deviceID: "tv-b") == k2)
    }
}
