import Foundation

public struct AyuGramPersonalizationSettings: Codable, Equatable {
    public var fontFamily: String = ""
    public var customFontFile: String = ""
    public var customFontFamily: String = ""
    public var appBadgeEnabled: Bool = false
    public var appBadgeText: String = "AYUGRAM"
    public var appBadgeShowsIcon: Bool = true
    public var appBadgeImageFile: String = ""
    public var appBadgeTop: String = "30264A"
    public var appBadgeBottom: String = "30264A"
    public var appBadgeDarkText: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AyuGramPersonalizationSettings()
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? defaults.fontFamily
        self.customFontFile = try container.decodeIfPresent(String.self, forKey: .customFontFile) ?? defaults.customFontFile
        self.customFontFamily = try container.decodeIfPresent(String.self, forKey: .customFontFamily) ?? defaults.customFontFamily
        self.appBadgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .appBadgeEnabled) ?? defaults.appBadgeEnabled
        self.appBadgeText = try container.decodeIfPresent(String.self, forKey: .appBadgeText) ?? defaults.appBadgeText
        self.appBadgeShowsIcon = try container.decodeIfPresent(Bool.self, forKey: .appBadgeShowsIcon) ?? defaults.appBadgeShowsIcon
        self.appBadgeImageFile = try container.decodeIfPresent(String.self, forKey: .appBadgeImageFile) ?? defaults.appBadgeImageFile
        self.appBadgeTop = try container.decodeIfPresent(String.self, forKey: .appBadgeTop) ?? defaults.appBadgeTop
        self.appBadgeBottom = try container.decodeIfPresent(String.self, forKey: .appBadgeBottom) ?? defaults.appBadgeBottom
        self.appBadgeDarkText = try container.decodeIfPresent(Bool.self, forKey: .appBadgeDarkText) ?? defaults.appBadgeDarkText
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

    public var appBadgeImageURL: URL? {
        let file = self.settings.appBadgeImageFile
        guard !file.isEmpty, let directory = AyuGramPersonalization.fontsDirectory else {
            return nil
        }
        let url = directory.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
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
