import Foundation

public struct AyuGramVideoSettings: Codable, Equatable {
    public var roundQuality: Int32 = 0
    public var roundFrameRate: Int32 = 30
    public var roundFromGallery = true
    public var videoBestQuality = false
    public var videoHighBitrate = false
    public var roundHEVC = false
    public var roundBitrateMbps: Int32 = 0
    public var roundLargeAs640 = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AyuGramVideoSettings()
        self.roundQuality = try container.decodeIfPresent(Int32.self, forKey: .roundQuality) ?? defaults.roundQuality
        self.roundFrameRate = try container.decodeIfPresent(Int32.self, forKey: .roundFrameRate) ?? defaults.roundFrameRate
        self.roundFromGallery = try container.decodeIfPresent(Bool.self, forKey: .roundFromGallery) ?? defaults.roundFromGallery
        self.videoBestQuality = try container.decodeIfPresent(Bool.self, forKey: .videoBestQuality) ?? defaults.videoBestQuality
        self.videoHighBitrate = try container.decodeIfPresent(Bool.self, forKey: .videoHighBitrate) ?? defaults.videoHighBitrate
        self.roundHEVC = try container.decodeIfPresent(Bool.self, forKey: .roundHEVC) ?? defaults.roundHEVC
        self.roundBitrateMbps = try container.decodeIfPresent(Int32.self, forKey: .roundBitrateMbps) ?? defaults.roundBitrateMbps
        self.roundLargeAs640 = try container.decodeIfPresent(Bool.self, forKey: .roundLargeAs640) ?? defaults.roundLargeAs640
    }

    public static let roundSides: [Int] = [480, 640, 720, 1072]
    public static let roundStandardSideCount: Int = 2
    public static let roundFrameRates: [Int32] = [30, 60, 120]
    public static let roundBitrateChoices: [Int32] = [0, 2, 4, 6, 8, 10]
    public static let roundDeclaredMaximumSide: Int = 640

    public var roundAvailableQualityCount: Int {
        return self.roundLargeAs640 ? AyuGramVideoSettings.roundSides.count : AyuGramVideoSettings.roundStandardSideCount
    }

    public var roundQualityIndex: Int32 {
        return max(0, min(Int32(self.roundAvailableQualityCount - 1), self.roundQuality))
    }

    public var roundSide: Int {
        return AyuGramVideoSettings.roundSides[Int(self.roundQualityIndex)]
    }

    public var roundBitrateOverride: Int? {
        guard self.roundBitrateMbps > 0, AyuGramVideoSettings.roundBitrateChoices.contains(self.roundBitrateMbps) else {
            return nil
        }
        return Int(self.roundBitrateMbps) * 1_000_000
    }

    public static func roundDeclaredSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let side = max(width, height)
        guard side > roundDeclaredMaximumSide, width > 0, height > 0 else {
            return (width, height)
        }
        let scale = Double(roundDeclaredMaximumSide) / Double(side)
        let declaredWidth = min(roundDeclaredMaximumSide, max(1, Int((Double(width) * scale).rounded())))
        let declaredHeight = min(roundDeclaredMaximumSide, max(1, Int((Double(height) * scale).rounded())))
        return (declaredWidth, declaredHeight)
    }

    public var roundFps: Double {
        return Double(AyuGramVideoSettings.roundFrameRates.contains(self.roundFrameRate) ? self.roundFrameRate : 30)
    }

    public var roundIsOverridden: Bool {
        return self.roundSide != 480 || self.roundFps > 30.0
    }

    public func roundBitrate(side: Int, fps: Double) -> Int {
        if let roundBitrateOverride = self.roundBitrateOverride {
            return roundBitrateOverride
        }
        let area = Double(side * side) / Double(480 * 480)
        let motion = fps > 30.0 ? pow(fps / 30.0, 0.6) : 1.0
        let value = 1_200_000.0 * area * motion
        return Int(min(16_000_000.0, max(1_200_000.0, value)))
    }
}

public final class AyuGramVideoSettingsStore {
    public static let shared = AyuGramVideoSettingsStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let key = "swiftgram.ayuGram.video.v1"
    private var cache: AyuGramVideoSettings?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var value: AyuGramVideoSettings {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.readValue()
    }

    private func readValue() -> AyuGramVideoSettings {
        if let cache = self.cache {
            return cache
        }
        let value = self.defaults.data(forKey: self.key).flatMap { try? JSONDecoder().decode(AyuGramVideoSettings.self, from: $0) } ?? AyuGramVideoSettings()
        self.cache = value
        return value
    }

    public func update(_ transform: (inout AyuGramVideoSettings) -> Void) {
        self.lock.lock()
        var value = self.readValue()
        transform(&value)
        if let data = try? JSONEncoder().encode(value) {
            self.defaults.set(data, forKey: self.key)
        }
        self.cache = value
        self.lock.unlock()
        NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
    }
}

public extension AyuGramSettings {
    var video: AyuGramVideoSettings {
        return AyuGramVideoSettingsStore.shared.value
    }

    func updateVideo(_ transform: (inout AyuGramVideoSettings) -> Void) {
        AyuGramVideoSettingsStore.shared.update(transform)
    }
}
