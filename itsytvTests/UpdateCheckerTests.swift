import Testing

struct VersionComparatorTests {

    // MARK: - Newer version

    @Test func majorVersionBump() {
        #expect(isNewerVersion("2.0.0", than: "1.9.9"))
    }

    @Test func minorVersionBump() {
        #expect(isNewerVersion("1.6.0", than: "1.5.4"))
    }

    @Test func patchVersionBump() {
        #expect(isNewerVersion("1.5.5", than: "1.5.4"))
    }

    @Test func singleComponentNewer() {
        #expect(isNewerVersion("2", than: "1"))
    }

    // MARK: - Same version

    @Test func sameVersion() {
        #expect(!isNewerVersion("1.5.4", than: "1.5.4"))
    }

    @Test func sameVersionSingleComponent() {
        #expect(!isNewerVersion("1", than: "1"))
    }

    // MARK: - Older version

    @Test func majorVersionOlder() {
        #expect(!isNewerVersion("0.9.9", than: "1.0.0"))
    }

    @Test func minorVersionOlder() {
        #expect(!isNewerVersion("1.4.9", than: "1.5.0"))
    }

    @Test func patchVersionOlder() {
        #expect(!isNewerVersion("1.5.3", than: "1.5.4"))
    }

    // MARK: - Unequal component counts

    @Test func remoteHasFewerComponents() {
        // "1.5" vs "1.5.4" — missing patch treated as 0, so older
        #expect(!isNewerVersion("1.5", than: "1.5.4"))
    }

    @Test func remoteHasMoreComponents() {
        // "1.5.4.1" vs "1.5.4" — extra patch component makes it newer
        #expect(isNewerVersion("1.5.4.1", than: "1.5.4"))
    }

    @Test func currentHasFewerComponents() {
        // "1.6" vs "1.5.4" — minor bump wins
        #expect(isNewerVersion("1.6", than: "1.5.4"))
    }

    // MARK: - Edge cases

    @Test func bothEmpty() {
        #expect(!isNewerVersion("", than: ""))
    }

    @Test func remoteEmpty() {
        #expect(!isNewerVersion("", than: "1.5.4"))
    }

    @Test func currentEmpty() {
        #expect(isNewerVersion("1.5.4", than: ""))
    }

    @Test func zeroPadding() {
        #expect(!isNewerVersion("1.05.04", than: "1.5.4"))
    }

    @Test func largeVersionNumbers() {
        #expect(isNewerVersion("10.0.0", than: "9.99.99"))
    }
}
