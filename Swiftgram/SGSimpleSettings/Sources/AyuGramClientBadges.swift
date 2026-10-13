import Foundation

/// AyuGram badges, decided on the device: the owner's seal and your own member
/// badge on the account you are signed in with. Nothing is sent over the network.
public final class AyuGramClientBadges {
    public static let shared = AyuGramClientBadges()
    public static let didChange = Notification.Name("AyuGram.ClientBadges.didChange")
    private static let ownerId: Int64 = 1272887902
    private let lock = NSLock()
    private var activeAccount: Int64?
    private var generations: [Int64: Int64] = [:]

    public init() {}

    private static func valid(_ id: Int64) -> Bool { id > 0 && id <= 4503599627370495 }

    public func badge(peerId: Int64) -> String? {
        guard Self.valid(peerId) else { return nil }
        if peerId == Self.ownerId { return "owner" }
        lock.lock(); defer { lock.unlock() }
        return activeAccount == peerId ? "member" : nil
    }

    /// Bumped whenever a peer's badge changes, so cached user models re-render.
    public func generation(peerId: Int64) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return generations[peerId] ?? 0
    }

    public func observe(peerId: Int64, accountId: Int64) {}

    public func setActiveAccount(_ id: Int64?) {
        let id = id.flatMap { Self.valid($0) ? $0 : nil }
        lock.lock()
        guard activeAccount != id else { lock.unlock(); return }
        let changed = [activeAccount, id].compactMap { $0 }
        activeAccount = id
        for peerId in changed { generations[peerId, default: 0] += 1 }
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["peerIds": changed])
        }
    }

    public func setForeground(_ value: Bool) {}

    public func refresh() {}
}
