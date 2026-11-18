import Foundation
import Display

public extension ItemListSystemStyle {
    @inline(__always)
    var resolved: ItemListSystemStyle {
        return AyuLegacyUI.isEnabled ? .legacy : self
    }
}
