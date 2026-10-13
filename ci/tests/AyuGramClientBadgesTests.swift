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
        expect(badges.badge(peerId: 42) == "member", "The signed-in account shows its own badge")
        expect(badges.generation(peerId: 42) == before + 1, "Switching accounts re-renders the account's badge")

        badges.setActiveAccount(7)
        expect(badges.badge(peerId: 42) == nil && badges.badge(peerId: 7) == "member", "Only the active account has the member badge")

        badges.observe(peerId: 99, accountId: 7)
        badges.setForeground(true)
        badges.refresh()
        expect(badges.badge(peerId: 99) == nil, "Seeing a user never makes a request or grants a badge")
        print("Local badges: owner seal and own account only, no network")
    }
}
