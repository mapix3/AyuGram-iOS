import Foundation

public enum AyuGramAppearanceScope: Equatable { case chatList, conversation }

public struct AyuGramWallpaperAppearanceSettings: Codable, Equatable {
    public var followsChatList: Bool? = nil
    public var fileName: String?
    public var isVideo: Bool
    public var dim: Float
    public var blur: Float
    public var animateVideo: Bool
}

public struct AyuGramAppearanceSettings: Codable, Equatable {
    public var wallpaper: AyuGramWallpaperAppearanceSettings?
    public var fileName: String?
    public var isVideo = false
    public var chatList = true
    public var conversations = true
    public var dim: Float = 0.6
    public var blur: Float = 0.2
    public var rowOpacity: Float = 0.65
    public var animateVideo = true
    public init() {}
}

public final class AyuGramAppearance {
    public static let shared = AyuGramAppearance()
    public static let didChange = Notification.Name("AyuGram.Appearance.didChange")
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let customDirectory: URL?
    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.customDirectory = directory
    }
    private let key = "swiftgram.ayuGram.appearance.v1"
    public var settings: AyuGramAppearanceSettings {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }
    private func read() -> AyuGramAppearanceSettings {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AyuGramAppearanceSettings.self, from: $0) } ?? AyuGramAppearanceSettings()
    }
    public func update(_ f: (inout AyuGramAppearanceSettings) -> Void) {
        lock.lock()
        var value = read()
        f(&value)
        value.dim = min(0.9, max(0.2, value.dim))
        value.blur = min(1, max(0, value.blur))
        value.rowOpacity = min(1, max(0.35, value.rowOpacity))
        if var wallpaper = value.wallpaper {
            wallpaper.dim = min(0.9, max(0.2, wallpaper.dim))
            wallpaper.blur = min(1, max(0, wallpaper.blur))
            value.wallpaper = wallpaper
        }
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
    private static func resolve(_ settings: AyuGramAppearanceSettings, scope: AyuGramAppearanceScope) -> AyuGramAppearanceSettings {
        var result = settings
        if scope == .conversation, let wallpaper = settings.wallpaper, wallpaper.fileName != nil || wallpaper.followsChatList == false {
            result.fileName = wallpaper.fileName
            result.isVideo = wallpaper.isVideo
            result.dim = wallpaper.dim
            result.blur = wallpaper.blur
            result.animateVideo = wallpaper.animateVideo
        }
        return result
    }
    public func effectiveSettings(for scope: AyuGramAppearanceScope) -> AyuGramAppearanceSettings {
        return Self.resolve(settings, scope: scope)
    }
    public func updateForScope(_ scope: AyuGramAppearanceScope, _ f: (inout AyuGramAppearanceSettings) -> Void) {
        update { settings in
            if scope == .chatList {
                if settings.wallpaper == nil {
                    settings.wallpaper = AyuGramWallpaperAppearanceSettings(fileName: settings.fileName, isVideo: settings.isVideo, dim: settings.dim, blur: settings.blur, animateVideo: settings.animateVideo)
                }
                f(&settings)
            } else {
                var value = Self.resolve(settings, scope: scope)
                f(&value)
                settings.conversations = value.conversations
                settings.wallpaper = AyuGramWallpaperAppearanceSettings(fileName: value.fileName, isVideo: value.isVideo, dim: value.dim, blur: value.blur, animateVideo: value.animateVideo)
            }
        }
    }
    public var directory: URL {
        customDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AyuGramAppearance", isDirectory: true)
    }
    public var mediaURL: URL? { mediaURL(for: .chatList) }
    public func mediaURL(for scope: AyuGramAppearanceScope) -> URL? {
        guard let name = effectiveSettings(for: scope).fileName, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("..") else { return nil }
        let url = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    public var showsChatList: Bool { settings.chatList && mediaURL != nil }
    public var showsConversations: Bool { settings.conversations && mediaURL(for: .conversation) != nil }
    public func importMedia(_ url: URL, isVideo: Bool, scope: AyuGramAppearanceScope = .chatList) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0, size <= 100 * 1024 * 1024 else {
            throw CocoaError(.fileReadTooLarge)
        }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, ext.allSatisfy({ $0.isLetter || $0.isNumber }), ext.count <= 8 else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try? excluded.setResourceValues(resources)
        let name = UUID().uuidString + "." + ext
        let target = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: target)
        let old = mediaURL(for: scope)
        updateForScope(scope) { $0.fileName = name; $0.isVideo = isVideo }
        if let old, old != mediaURL(for: scope == .chatList ? .conversation : .chatList) { try? FileManager.default.removeItem(at: old) }
    }
    public func reset(scope: AyuGramAppearanceScope = .chatList) {
        let old = mediaURL(for: scope)
        update { settings in
            if scope == .chatList {
                let wallpaper = settings.wallpaper ?? AyuGramWallpaperAppearanceSettings(fileName: settings.fileName, isVideo: settings.isVideo, dim: settings.dim, blur: settings.blur, animateVideo: settings.animateVideo)
                let conversations = settings.conversations
                settings = AyuGramAppearanceSettings()
                settings.wallpaper = wallpaper
                settings.conversations = conversations
            } else {
                settings.wallpaper = AyuGramWallpaperAppearanceSettings(followsChatList: false, fileName: nil, isVideo: false, dim: 0.6, blur: 0.2, animateVideo: true)
                settings.conversations = true
            }
        }
        if let old, old != mediaURL(for: scope == .chatList ? .conversation : .chatList) { try? FileManager.default.removeItem(at: old) }
    }
}
