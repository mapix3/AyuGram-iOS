import Foundation

@main
struct ClientBadgeTests {
    static func expect(_ value: @autoclosure () -> Bool, _ text: String) { precondition(value(), text) }

    static func main() {
        let badges = AyuGramClientBadges()
        expect(badges.badge(peerId: 1272887902) == "owner", "The owner seal is decided on the device")
        expect(badges.badge(peerId: 42) == nil, "Other users get no badge")
        expect(badges.badge(peerId: -1) == nil && badges.badge(peerId: 0) == nil, "Invalid IDs get no badge")

        let before = badges.generation(peerId: 42)
        badges.setActiveAccount(42)
        expect(badges.badge(peerId: 42) == nil, "The signed-in account gets no badge by itself")
        expect(badges.generation(peerId: 42) == before + 1, "Switching accounts re-renders the account's badge")

        badges.setActiveAccount(7)
        expect(badges.badge(peerId: 42) == nil && badges.badge(peerId: 7) == nil, "Switching accounts grants nothing")
        var custom = AyuGramCustomBadge()
        custom.symbol = "star.fill"
        badges.setSupporter(8914323197, badge: custom)
        let packed: Int64 = (2 << 35) | (8914323197 & 0xffffffff)
        expect(badges.badge(peerId: packed) == "supporter" && badges.supporterBadge(peerId: packed)?.symbol == "star.fill", "A supporter with a large ID is found by its packed peer ID")
        expect(badges.badge(peerId: 1272887902) == "owner", "The owner seal wins over a supporter badge")

        badges.observe(peerId: 99, accountId: 7)
        badges.setForeground(true)
        badges.refresh()
        expect(badges.badge(peerId: 99) == nil, "Seeing a user never makes a request or grants a badge")
        print("Local badges: owner seal and own account only, no network")
    }
}
