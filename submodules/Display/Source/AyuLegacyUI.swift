import Foundation
import SGSimpleSettings

public enum AyuLegacyUI {
    @inline(__always)
    public static var isEnabled: Bool {
        return AyuLegacyUILaunch.isEnabled
    }
}
