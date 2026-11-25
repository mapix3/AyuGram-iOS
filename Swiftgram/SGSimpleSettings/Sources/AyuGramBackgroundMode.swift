import Foundation

public enum AyuGramBackgroundMode: String, CaseIterable {
    case audio
    case location
    case audioAndLocation
    case off

    public static let didChange = Notification.Name("AyuGram.BackgroundMode.didChange")
    private static let key = "ayuGram.backgroundMode"

    public static var current: AyuGramBackgroundMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: AyuGramBackgroundMode.key), let value = AyuGramBackgroundMode(rawValue: raw) {
                return value
            }
            return .audio
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: AyuGramBackgroundMode.key)
            NotificationCenter.default.post(name: AyuGramBackgroundMode.didChange, object: nil)
        }
    }

    public var usesAudio: Bool {
        switch self {
        case .audio, .audioAndLocation:
            return true
        case .location, .off:
            return false
        }
    }

    public var usesLocation: Bool {
        switch self {
        case .location, .audioAndLocation:
            return true
        case .audio, .off:
            return false
        }
    }

    public var titleKey: String {
        switch self {
        case .audio:
            return "Ayu.BackgroundMode.Audio"
        case .location:
            return "Ayu.BackgroundMode.Location"
        case .audioAndLocation:
            return "Ayu.BackgroundMode.AudioLocation"
        case .off:
            return "Ayu.BackgroundMode.Off"
        }
    }
}

public enum AyuGramBackgroundLean {
    public static let didChange = Notification.Name("AyuGram.BackgroundLean.didChange")

    private static let lock = NSLock()
    private static var value = false

    public static var isActive: Bool {
        AyuGramBackgroundLean.lock.lock()
        defer {
            AyuGramBackgroundLean.lock.unlock()
        }
        return AyuGramBackgroundLean.value
    }

    public static func update(isActive: Bool) {
        AyuGramBackgroundLean.lock.lock()
        let changed = AyuGramBackgroundLean.value != isActive
        AyuGramBackgroundLean.value = isActive
        AyuGramBackgroundLean.lock.unlock()
        if changed {
            NotificationCenter.default.post(name: AyuGramBackgroundLean.didChange, object: nil)
        }
    }

    public static func observe(_ f: @escaping (Bool) -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(forName: AyuGramBackgroundLean.didChange, object: nil, queue: .main, using: { _ in
            f(AyuGramBackgroundLean.isActive)
        })
    }
}
