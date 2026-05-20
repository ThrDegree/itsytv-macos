import Testing

struct DeviceIDFilterTests {

    // MARK: - MAC addresses are removed

    @Test func macAddressIsFiltered() {
        #expect(filterMACAddresses(["AA:BB:CC:DD:EE:FF"]).isEmpty)
    }

    @Test func lowercaseMACIsFiltered() {
        #expect(filterMACAddresses(["aa:bb:cc:dd:ee:ff"]).isEmpty)
    }

    @Test func mixedCaseMACIsFiltered() {
        #expect(filterMACAddresses(["aA:bB:cC:dD:eE:fF"]).isEmpty)
    }

    // MARK: - Non-MAC IDs pass through

    @Test func uuidPassesThrough() {
        let id = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        #expect(filterMACAddresses([id]) == [id])
    }

    @Test func shortIDPassesThrough() {
        let id = "myAppleTV"
        #expect(filterMACAddresses([id]) == [id])
    }

    @Test func emptyStringPassesThrough() {
        #expect(filterMACAddresses([""]) == [""])
    }

    // MARK: - Near-misses are not filtered

    @Test func fiveOctetIsNotFiltered() {
        // Only 5 octets — not a valid MAC
        #expect(filterMACAddresses(["AA:BB:CC:DD:EE"]) == ["AA:BB:CC:DD:EE"])
    }

    @Test func sevenOctetIsNotFiltered() {
        #expect(filterMACAddresses(["AA:BB:CC:DD:EE:FF:00"]) == ["AA:BB:CC:DD:EE:FF:00"])
    }

    @Test func nonHexOctetIsNotFiltered() {
        #expect(filterMACAddresses(["GG:BB:CC:DD:EE:FF"]) == ["GG:BB:CC:DD:EE:FF"])
    }

    @Test func dashSeparatedIsNotFiltered() {
        // Dash-separated — not the expected colon format
        let id = "AA-BB-CC-DD-EE-FF"
        #expect(filterMACAddresses([id]) == [id])
    }

    // MARK: - Mixed lists

    @Test func mixedListFiltersOnlyMACs() {
        let input = ["AA:BB:CC:DD:EE:FF", "myTV", "11:22:33:44:55:66"]
        #expect(filterMACAddresses(input) == ["myTV"])
    }

    @Test func emptyListReturnsEmpty() {
        #expect(filterMACAddresses([]).isEmpty)
    }

    @Test func allNonMACsReturnUnchanged() {
        let input = ["tv-1", "tv-2", "tv-3"]
        #expect(filterMACAddresses(input) == input)
    }
}
