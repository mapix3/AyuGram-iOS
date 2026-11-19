import Foundation

public struct AyuGramEffectsSettings: Codable, Equatable {
    public enum DeleteStyle: Int32, Codable, CaseIterable {
        case standard = 0
        case dust = 1
        case burn = 2
        case shatter = 3
        case implode = 4
    }

    public enum SendStyle: Int32, Codable, CaseIterable {
        case standard = 0
        case spring = 1
        case sparkles = 2
        case warp = 3
    }

    public enum RingColor: Int32, Codable, CaseIterable {
        case accent = 0
        case blue = 1
        case teal = 2
        case green = 3
        case gold = 4
        case orange = 5
        case red = 6
        case pink = 7
        case purple = 8
        case white = 9
        case aurora = 100
        case sunset = 101
        case ocean = 102
        case neon = 103
        case fire = 104
        case rainbow = 105
    }

    public var enabled = true

    public var auroraGradient = false
    public var gradientGrain: Double = 0
    public var deepParallax = false
    public var backgroundRipple = false

    public var bubbleGlow = false
    public var glassBubbles = false

    public var deleteStyle: DeleteStyle = .standard
    public var sendStyle: SendStyle = .standard
    public var incomingTextReveal = false

    public var avatarRings = false
    public var avatarRingColor: RingColor = .accent

    public var profileBubbles = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AyuGramEffectsSettings()
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        self.auroraGradient = try container.decodeIfPresent(Bool.self, forKey: .auroraGradient) ?? defaults.auroraGradient
        self.gradientGrain = try container.decodeIfPresent(Double.self, forKey: .gradientGrain) ?? defaults.gradientGrain
        self.deepParallax = try container.decodeIfPresent(Bool.self, forKey: .deepParallax) ?? defaults.deepParallax
        self.backgroundRipple = try container.decodeIfPresent(Bool.self, forKey: .backgroundRipple) ?? defaults.backgroundRipple
        self.bubbleGlow = try container.decodeIfPresent(Bool.self, forKey: .bubbleGlow) ?? defaults.bubbleGlow
        self.glassBubbles = try container.decodeIfPresent(Bool.self, forKey: .glassBubbles) ?? defaults.glassBubbles
        self.deleteStyle = (try? container.decodeIfPresent(DeleteStyle.self, forKey: .deleteStyle)) ?? defaults.deleteStyle
        self.sendStyle = (try? container.decodeIfPresent(SendStyle.self, forKey: .sendStyle)) ?? defaults.sendStyle
        self.incomingTextReveal = try container.decodeIfPresent(Bool.self, forKey: .incomingTextReveal) ?? defaults.incomingTextReveal
        self.avatarRings = try container.decodeIfPresent(Bool.self, forKey: .avatarRings) ?? defaults.avatarRings
        self.avatarRingColor = (try? container.decodeIfPresent(RingColor.self, forKey: .avatarRingColor)) ?? defaults.avatarRingColor
        self.profileBubbles = try container.decodeIfPresent(Bool.self, forKey: .profileBubbles) ?? defaults.profileBubbles
    }

    public var activeAuroraGradient: Bool { enabled && auroraGradient }
    public var activeGradientGrain: Double { enabled ? gradientGrain : 0 }
    public var activeDeepParallax: Bool { enabled && deepParallax }
    public var activeBackgroundRipple: Bool { enabled && backgroundRipple }
    public var activeBubbleGlow: Bool { enabled && bubbleGlow }
    public var activeGlassBubbles: Bool { enabled && glassBubbles }
    public var activeDeleteStyle: DeleteStyle { enabled ? deleteStyle : .standard }
    public var activeSendStyle: SendStyle { enabled ? sendStyle : .standard }
    public var activeIncomingTextReveal: Bool { enabled && incomingTextReveal }
    public var activeAvatarRings: Bool { enabled && avatarRings }
    public var activeProfileBubbles: Bool { enabled && profileBubbles }
}

public extension AyuGramSettings {
    static let effectsDidChange = Notification.Name("Swiftgram.AyuGramSettings.effectsDidChange")

    var effects: AyuGramEffectsSettings {
        return AyuGramEffectsStore.shared.read()
    }

    func updateEffects(_ transform: (inout AyuGramEffectsSettings) -> Void) {
        AyuGramEffectsStore.shared.update(transform)
        let post = {
            NotificationCenter.default.post(name: AyuGramSettings.effectsDidChange, object: self)
            NotificationCenter.default.post(name: AyuGramSettings.didChange, object: self)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}

final class AyuGramEffectsStore {
    static let shared = AyuGramEffectsStore()

    private let defaults = UserDefaults.standard
    private let key = "swiftgram.ayuGram.effects.v1"
    private let lock = NSLock()
    private var cache: AyuGramEffectsSettings?

    func read() -> AyuGramEffectsSettings {
        lock.lock()
        defer { lock.unlock() }
        return readLocked()
    }

    func update(_ transform: (inout AyuGramEffectsSettings) -> Void) {
        lock.lock()
        var value = readLocked()
        transform(&value)
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
        cache = value
        lock.unlock()
    }

    private func readLocked() -> AyuGramEffectsSettings {
        if let cache = cache {
            return cache
        }
        let value = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AyuGramEffectsSettings.self, from: $0) } ?? AyuGramEffectsSettings()
        cache = value
        return value
    }
}
