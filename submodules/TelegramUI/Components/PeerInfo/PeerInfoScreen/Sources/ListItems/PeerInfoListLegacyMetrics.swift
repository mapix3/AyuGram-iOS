import Foundation
import UIKit
import Display

enum PeerInfoListMetrics {
    static var verticalPadding: CGFloat {
        return AyuLegacyUI.isEnabled ? 12.0 : 16.0
    }
    static var separatorRightInset: CGFloat {
        return AyuLegacyUI.isEnabled ? 0.0 : 16.0
    }
    static var iconSide: CGFloat {
        return AyuLegacyUI.isEnabled ? 29.0 : 30.0
    }
}
