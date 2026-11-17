import Foundation
import UIKit
import SGSimpleSettings

public enum AyuGramEffectsRuntime {
    public static var settings: AyuGramEffectsSettings {
        return AyuGramSettings.shared.effects
    }

    public static var motionAllowed: Bool {
        return !UIAccessibility.isReduceMotionEnabled
    }

    public static var continuousEffectsAllowed: Bool {
        return motionAllowed && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public static func observe(_ handler: @escaping () -> Void) -> AyuGramEffectsObserver {
        return AyuGramEffectsObserver(handler: handler)
    }
}

public final class AyuGramEffectsObserver {
    private var tokens: [NSObjectProtocol] = []

    init(handler: @escaping () -> Void) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            AyuGramSettings.effectsDidChange,
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange
        ]
        for name in names {
            self.tokens.append(center.addObserver(forName: name, object: nil, queue: .main, using: { _ in
                handler()
            }))
        }
    }

    deinit {
        for token in self.tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
