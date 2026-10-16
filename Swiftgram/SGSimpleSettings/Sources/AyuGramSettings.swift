import Foundation

public struct AyuGramPrivacySettings: Codable, Equatable {
    public var ghostMode = false
    public var antiRead = false
    public var antiOnline = false
    public var antiTyping = false
    public var antiRecording = false
    public var antiUploading = false
    public var storyPrivacy = false
    public var messageHistory = false

    public init() {}

    public var suppressRead: Bool { ghostMode || antiRead }
    public var suppressOnline: Bool { ghostMode || antiOnline }
    public var suppressTyping: Bool { ghostMode || antiTyping }
    public var suppressRecording: Bool { ghostMode || antiRecording }
    public var suppressUploading: Bool { ghostMode || antiUploading }
    public var suppressStoryViews: Bool { ghostMode || storyPrivacy }
}

/// Device-wide preferences, owned by Swiftgram's existing settings store.
/// A single encoded snapshot makes updates atomic across networking queues.
public final class AyuGramSettings {
    public static var shared: AyuGramSettings { SGSimpleSettings.shared.ayuGram }
    public static let didChange = Notification.Name("Swiftgram.AyuGramSettings.didChange")
    private let defaults: UserDefaults
    /// App group copy of the privacy snapshot. App extensions cannot read the app's
    /// standard defaults; the notification service needs Save Deleted Messages.
    private let shared: UserDefaults?
    private let lock = NSLock()
    private let key = "swiftgram.ayuGram.privacy.v1"
    private let extraKey = "swiftgram.ayuGram.extra.v1"
    // Read on hot rendering paths (copy protection checks per message, every peer's
    // emoji status), so decoded values stay in memory until this store changes them.
    private var extraCache: AyuGramExtraSettings?
    private var privacyCache: AyuGramPrivacySettings?
    private var clientCache: AyuGramClientSettings?
    private var statusCache: [Int64: AyuGramLocalStatus?] = [:]

    public init(defaults: UserDefaults = .standard, shared: UserDefaults? = nil) {
        self.defaults = defaults
        self.shared = shared
    }

    public var snapshot: AyuGramPrivacySettings {
        lock.lock()
        defer { lock.unlock() }
        return readSnapshot()
    }

    /// Caller holds the lock.
    private func readSnapshot() -> AyuGramPrivacySettings {
        if let cached = privacyCache {
            return cached
        }
        guard let data = defaults.data(forKey: key) else {
            // An app extension has only the app group copy. It is read again every
            // time: the extension process outlives changes made in the app.
            return shared?.data(forKey: key).flatMap { try? JSONDecoder().decode(AyuGramPrivacySettings.self, from: $0) } ?? AyuGramPrivacySettings()
        }
        // Settings saved before the copy existed reach the app group on first read.
        if let shared, shared.data(forKey: key) != data {
            shared.set(data, forKey: key)
        }
        let value = (try? JSONDecoder().decode(AyuGramPrivacySettings.self, from: data)) ?? AyuGramPrivacySettings()
        privacyCache = value
        return value
    }

    public func update(_ transform: (inout AyuGramPrivacySettings) -> Void) {
        lock.lock()
        var value = readSnapshot()
        transform(&value)
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
            shared?.set(data, forKey: key)
        }
        privacyCache = value
        lock.unlock()
        // Notify outside the lock: observers are allowed to read the snapshot.
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

public struct AyuGramClientSettings: Codable, Equatable {
    public var localPremium = false
    public var maxPinnedChats: Int32 = 5
    public init() {}
    public var pinnedChatLimit: Int32 { max(5, min(30, maxPinnedChats)) }
}

public extension AyuGramSettings {
    var client: AyuGramClientSettings {
        lock.lock()
        defer { lock.unlock() }
        return readClient()
    }
    /// Caller holds the lock.
    private func readClient() -> AyuGramClientSettings {
        if let cached = clientCache {
            return cached
        }
        let value = defaults.data(forKey: "swiftgram.ayuGram.client.v1").flatMap { try? JSONDecoder().decode(AyuGramClientSettings.self, from: $0) } ?? AyuGramClientSettings()
        clientCache = value
        return value
    }
    func updateClient(_ transform: (inout AyuGramClientSettings) -> Void) {
        lock.lock()
        var value = readClient()
        transform(&value)
        value.maxPinnedChats = value.pinnedChatLimit
        if let encoded = try? JSONEncoder().encode(value) {
            defaults.set(encoded, forKey: "swiftgram.ayuGram.client.v1")
        }
        clientCache = value
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

public struct AyuGramLocalStatus: Codable, Equatable {
    public var fileId: Int64?
    public var expirationDate: Int32?
    public init(fileId: Int64?, expirationDate: Int32?) {
        self.fileId = fileId
        self.expirationDate = expirationDate
    }
}

public extension AyuGramSettings {
    func localStatus(peerId: Int64) -> AyuGramLocalStatus? {
        lock.lock()
        defer { lock.unlock() }
        guard readClient().localPremium else { return nil }
        let status: AyuGramLocalStatus?
        if let cached = statusCache[peerId] {
            status = cached
        } else {
            status = defaults.data(forKey: "swiftgram.ayuGram.status.v1.\(peerId)").flatMap { try? JSONDecoder().decode(AyuGramLocalStatus.self, from: $0) }
            statusCache[peerId] = .some(status)
        }
        guard let status else { return nil }
        if let expiry = status.expirationDate, Int64(expiry) <= Int64(Date().timeIntervalSince1970) { return nil }
        return status
    }
    func setLocalStatus(peerId: Int64, status: AyuGramLocalStatus?) {
        lock.lock()
        let key = "swiftgram.ayuGram.status.v1.\(peerId)"
        if let status, let data = try? JSONEncoder().encode(status) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
        statusCache[peerId] = .some(status)
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// Options added after the original privacy/client snapshots. Decoding keeps
/// defaults for missing keys, so future fields never reset stored choices.
public struct AyuGramExtraSettings: Codable, Equatable {
    /// Save, copy, share and forward content of protected chats.
    public var ignoreCopyProtection = true
    /// Screenshots and screen recordings of protected and secret content.
    public var allowScreenshots = true
    /// While online status is hidden, report offline after each sent message.
    public var offlineAfterSending = true
    /// While read receipts are hidden, a sent message still reads that chat.
    public var readOnSend = true
    /// Ghost Mode item in the Chats tab long-press menu.
    public var ghostQuickToggle = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AyuGramExtraSettings()
        self.ignoreCopyProtection = try container.decodeIfPresent(Bool.self, forKey: .ignoreCopyProtection) ?? defaults.ignoreCopyProtection
        self.allowScreenshots = try container.decodeIfPresent(Bool.self, forKey: .allowScreenshots) ?? defaults.allowScreenshots
        self.offlineAfterSending = try container.decodeIfPresent(Bool.self, forKey: .offlineAfterSending) ?? defaults.offlineAfterSending
        self.readOnSend = try container.decodeIfPresent(Bool.self, forKey: .readOnSend) ?? defaults.readOnSend
        self.ghostQuickToggle = try container.decodeIfPresent(Bool.self, forKey: .ghostQuickToggle) ?? defaults.ghostQuickToggle
    }
}

public extension AyuGramSettings {
    /// UserDefaults mirror read by the Objective-C screenshot protection helper.
    static let allowScreenshotsDefaultsKey = "AyuGramAllowScreenshots"

    var extra: AyuGramExtraSettings {
        lock.lock()
        defer { lock.unlock() }
        if let cached = extraCache {
            return cached
        }
        let value = defaults.data(forKey: extraKey).flatMap { try? JSONDecoder().decode(AyuGramExtraSettings.self, from: $0) } ?? AyuGramExtraSettings()
        extraCache = value
        return value
    }

    func updateExtra(_ transform: (inout AyuGramExtraSettings) -> Void) {
        lock.lock()
        var value = extraCache ?? defaults.data(forKey: extraKey).flatMap { try? JSONDecoder().decode(AyuGramExtraSettings.self, from: $0) } ?? AyuGramExtraSettings()
        transform(&value)
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: extraKey)
        }
        defaults.set(value.allowScreenshots, forKey: Self.allowScreenshotsDefaultsKey)
        extraCache = value
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// Ghost Mode switch used by quick toggles outside the settings screen.
    func setGhostMode(_ enabled: Bool) {
        update { $0.ghostMode = enabled }
    }
}
