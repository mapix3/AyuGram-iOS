import Foundation

public enum AyuLegacyUILaunch {
    private static let pendingLaunchesKey = "ayu.legacyUI.pendingLaunches.v1"
    private static let crashThreshold = 3
    public private(set) static var wasDisabledByCrashGuard = false
    private static var hasCountedUserLaunch = false

    private static var isAppExtension: Bool {
        return Bundle.main.bundleURL.pathExtension == "appex"
    }

    public static let isEnabled: Bool = {
        if isAppExtension {
            return false
        }
        return AyuGramSettings.shared.extra.disableLiquidGlass
    }()

    public static var isEnabledOnNextLaunch: Bool {
        return AyuGramSettings.shared.extra.disableLiquidGlass
    }

    public static func prime(countsAsUserLaunch: Bool) {
        if !isAppExtension && AyuGramSettings.shared.extra.disableLiquidGlass {
            let defaults = UserDefaults.standard
            if defaults.integer(forKey: pendingLaunchesKey) >= crashThreshold {
                defaults.set(0, forKey: pendingLaunchesKey)
                AyuGramSettings.shared.updateExtra { $0.disableLiquidGlass = false }
                wasDisabledByCrashGuard = true
            }
        }
        let _ = isEnabled
        if countsAsUserLaunch {
            countUserLaunch()
        }
    }

    public static func countUserLaunch() {
        if isAppExtension || !isEnabled || hasCountedUserLaunch {
            return
        }
        hasCountedUserLaunch = true
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: pendingLaunchesKey) + 1, forKey: pendingLaunchesKey)
    }

    public static func markLaunchSucceeded() {
        UserDefaults.standard.set(0, forKey: pendingLaunchesKey)
    }
}
