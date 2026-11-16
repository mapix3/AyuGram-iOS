import Foundation

public struct AyuGramCustomBadge: Codable, Equatable {
    public var enabled: Bool = false
    public var symbol: String = "sparkles"
    public var emoji: String = ""
    public var shape: Int32 = 0
    public var top: String = "8E61F2"
    public var bottom: String = "C9B3FF"
    public var darkGlyph: Bool = false

    public init() {}
}

public struct AyuGramPersonalizationSettings: Codable, Equatable {
    public var fontFamily: String = ""
    public var customFontFile: String = ""
    public var customFontFamily: String = ""
    public var badge = AyuGramCustomBadge()

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AyuGramPersonalizationSettings()
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? defaults.fontFamily
        self.customFontFile = try container.decodeIfPresent(String.self, forKey: .customFontFile) ?? defaults.customFontFile
        self.customFontFamily = try container.decodeIfPresent(String.self, forKey: .customFontFamily) ?? defaults.customFontFamily
        self.badge = try container.decodeIfPresent(AyuGramCustomBadge.self, forKey: .badge) ?? defaults.badge
    }
}

public final class AyuGramPersonalization {
    public static let shared = AyuGramPersonalization()
    public static let didChange = Notification.Name("AyuGram.Personalization.didChange")

    private let key = "swiftgram.ayuGram.personalization.v1"
    private let lock = NSLock()
    private var cache: AyuGramPersonalizationSettings?

    public var settings: AyuGramPersonalizationSettings {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let cache = self.cache {
            return cache
        }
        let value = UserDefaults.standard.data(forKey: self.key).flatMap { try? JSONDecoder().decode(AyuGramPersonalizationSettings.self, from: $0) } ?? AyuGramPersonalizationSettings()
        self.cache = value
        return value
    }

    public func update(_ f: (inout AyuGramPersonalizationSettings) -> Void) {
        self.lock.lock()
        var value = self.cache ?? UserDefaults.standard.data(forKey: self.key).flatMap { try? JSONDecoder().decode(AyuGramPersonalizationSettings.self, from: $0) } ?? AyuGramPersonalizationSettings()
        f(&value)
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: self.key)
        }
        self.cache = value
        self.lock.unlock()
        NotificationCenter.default.post(name: AyuGramPersonalization.didChange, object: self)
    }

    public static var fontsDirectory: URL? {
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("AyuFonts", isDirectory: true)
    }

    public var customFontURL: URL? {
        let file = self.settings.customFontFile
        guard !file.isEmpty, let directory = AyuGramPersonalization.fontsDirectory else {
            return nil
        }
        let url = directory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
