import Foundation

/// AyuGram badges, decided on the device: the owner's seal and your own member
/// badge on the account you are signed in with. Nothing is sent over the network.
public struct AyuGramCustomBadge: Codable, Equatable {
    public var enabled: Bool = false
    public var symbol: String = "sparkles"
    public var emoji: String = ""
    public var shape: Int32 = 0
    public var top: String = "8E61F2"
    public var bottom: String = "C9B3FF"
    public var darkGlyph: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "sparkles"
        self.emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        self.shape = try container.decodeIfPresent(Int32.self, forKey: .shape) ?? 0
        self.top = try container.decodeIfPresent(String.self, forKey: .top) ?? "8E61F2"
        self.bottom = try container.decodeIfPresent(String.self, forKey: .bottom) ?? "C9B3FF"
        self.darkGlyph = try container.decodeIfPresent(Bool.self, forKey: .darkGlyph) ?? false
    }
}

public enum AyuGramSupporterState: Equatable {
    case unknown
    case none
    case pending(String)
    case granted(AyuGramCustomBadge)
    case failed
}

public final class AyuGramClientBadges {
    public static let shared = AyuGramClientBadges()
    public static let didChange = Notification.Name("AyuGram.ClientBadges.didChange")
    private static let ownerId: Int64 = 1272887902
    private static let channels: [String: String] = ["ayugramiosupdates": "updates", "ayugramiospeek": "peek"]
    private let lock = NSLock()
    private var activeAccount: Int64?
    private var generations: [Int64: Int64] = [:]
    private var supporters: [Int64: AyuGramCustomBadge] = [:]
    private let cacheKey = "ayugram.badges.supporters"

    public init() {
        if let data = UserDefaults.standard.data(forKey: self.cacheKey), let stored = try? JSONDecoder().decode([String: AyuGramCustomBadge].self, from: data) {
            for (key, value) in stored {
                if let id = Int64(key) {
                    self.supporters[id] = value
                }
            }
        }
    }

    public static func valid(_ id: Int64) -> Bool { id > 0 && id <= 4503599627370495 }

    public func badge(peerId: Int64) -> String? {
        guard Self.valid(peerId) else { return nil }
        if peerId == Self.ownerId { return "owner" }
        lock.lock(); defer { lock.unlock() }
        if supporters[peerId] != nil { return "supporter" }
        return activeAccount == peerId ? "member" : nil
    }

    public func badge(peerId: Int64, username: String?) -> String? {
        if let username, let kind = Self.channels[username.lowercased()] {
            return kind
        }
        return self.badge(peerId: peerId)
    }

    public func supporterBadge(peerId: Int64) -> AyuGramCustomBadge? {
        lock.lock(); defer { lock.unlock() }
        return supporters[peerId]
    }

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
        self.refresh()
    }

    public func setForeground(_ value: Bool) {
        if value {
            self.refresh()
        }
    }

    private func apply(_ updated: [Int64: AyuGramCustomBadge]) {
        lock.lock()
        var changed: [Int64] = []
        for id in Set(supporters.keys).union(updated.keys) where supporters[id] != updated[id] {
            changed.append(id)
            generations[id, default: 0] += 1
        }
        supporters = updated
        lock.unlock()
        guard !changed.isEmpty else {
            return
        }
        var stored: [String: AyuGramCustomBadge] = [:]
        for (id, badge) in updated {
            stored[String(id)] = badge
        }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: self.cacheKey)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["peerIds": changed])
        }
    }

    public var refreshHandler: ((Bool) -> Void)?

    public func refresh(force: Bool = false) {
        self.refreshHandler?(force)
    }

    public func replaceSupporters(_ updated: [Int64: AyuGramCustomBadge]) {
        self.apply(updated)
    }

    public func setSupporter(_ id: Int64, badge: AyuGramCustomBadge) {
        lock.lock()
        var updated = supporters
        lock.unlock()
        updated[id] = badge
        self.apply(updated)
    }
}
