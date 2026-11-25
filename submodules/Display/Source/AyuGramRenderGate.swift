import Foundation
import SGSimpleSettings

public enum AyuGramRenderGate {
    public static var isSuspended: Bool {
        return AyuGramBackgroundLean.isActive
    }

    public static func observe(_ f: @escaping (Bool) -> Void) -> NSObjectProtocol {
        return AyuGramBackgroundLean.observe(f)
    }
}
