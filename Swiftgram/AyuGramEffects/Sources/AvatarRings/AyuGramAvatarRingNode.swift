import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SGSimpleSettings

public final class AyuGramAvatarRingNode: ASDisplayNode {
    public static var isEnabled: Bool {
        return AyuGramEffectsRuntime.settings.activeAvatarRings
    }

    private static let rotationKey = "ayuRingRotation"
    private static let rotationDuration: Double = 4.0

    private let gradientLayer: CAGradientLayer
    private let ringMaskLayer: CAShapeLayer
    private var observer: AyuGramEffectsObserver?

    private var isOnline = false
    private var lineWidth: CGFloat = 2.0
    private var accentColor: UIColor?
    private var appliedColorKey: String?
    private var ringSize = CGSize()
    private var isInHierarchyValue = false

    override public init() {
        self.gradientLayer = CAGradientLayer()
        self.gradientLayer.type = .conic
        self.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)

        self.ringMaskLayer = CAShapeLayer()
        self.ringMaskLayer.fillColor = UIColor.clear.cgColor
        self.ringMaskLayer.strokeColor = UIColor.black.cgColor
        self.ringMaskLayer.lineCap = .round

        super.init()

        self.isLayerBacked = true
        self.isHidden = true
    }

    override public func didLoad() {
        super.didLoad()

        self.gradientLayer.mask = self.ringMaskLayer
        self.layer.addSublayer(self.gradientLayer)

        self.observer = AyuGramEffectsRuntime.observe({ [weak self] in
            guard let self else {
                return
            }
            self.updateColors()
            self.updateState()
        })
        self.applyGeometry()
        self.updateColors()
        self.updateState()
    }

    override public func didEnterHierarchy() {
        super.didEnterHierarchy()
        self.isInHierarchyValue = true
        self.updateRotation()
    }

    override public func didExitHierarchy() {
        super.didExitHierarchy()
        self.isInHierarchyValue = false
        self.updateRotation()
    }

    public func update(size: CGSize, lineWidth: CGFloat, accentColor: UIColor, isOnline: Bool) {
        let geometryChanged = self.ringSize != size || self.lineWidth != lineWidth
        self.ringSize = size
        self.lineWidth = lineWidth
        self.accentColor = accentColor
        self.isOnline = isOnline

        self.updateColors()
        if geometryChanged && self.isNodeLoaded {
            self.applyGeometry()
        }
        if self.isNodeLoaded {
            self.updateState()
        }
    }

    private func updateColors() {
        let style = AyuGramEffectsRuntime.settings.avatarRingColor
        let accent = self.accentColor ?? UIColor(rgb: 0x007aff)
        let key = "\(style.rawValue):\(AyuGramAvatarRingNode.colorKey(accent))"
        if self.appliedColorKey == key {
            return
        }
        self.appliedColorKey = key
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradientLayer.colors = AyuGramAvatarRingNode.colors(style: style, accent: accent).map { $0.cgColor }
        CATransaction.commit()
    }

    private func applyGeometry() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = CGRect(origin: CGPoint(), size: self.ringSize)
        self.gradientLayer.bounds = bounds
        self.gradientLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        self.ringMaskLayer.frame = bounds
        self.ringMaskLayer.lineWidth = self.lineWidth
        let inset = self.lineWidth / 2.0
        if bounds.width > self.lineWidth * 2.0 {
            self.ringMaskLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
        } else {
            self.ringMaskLayer.path = nil
        }
        CATransaction.commit()
    }

    private func updateState() {
        let visible = self.isOnline && AyuGramAvatarRingNode.isEnabled
        if self.isHidden == visible {
            self.isHidden = !visible
        }
        self.updateRotation()
    }

    private func updateRotation() {
        guard self.isNodeLoaded else {
            return
        }
        let shouldRotate = !self.isHidden && self.isInHierarchyValue && AyuGramEffectsRuntime.continuousEffectsAllowed
        let isRotating = self.gradientLayer.animation(forKey: AyuGramAvatarRingNode.rotationKey) != nil
        if shouldRotate && !isRotating {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0.0 as NSNumber
            animation.toValue = (Double.pi * 2.0) as NSNumber
            animation.duration = AyuGramAvatarRingNode.rotationDuration
            animation.repeatCount = Float.infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.isRemovedOnCompletion = false
            animation.timeOffset = Double.random(in: 0.0 ..< AyuGramAvatarRingNode.rotationDuration)
            self.gradientLayer.add(animation, forKey: AyuGramAvatarRingNode.rotationKey)
        } else if !shouldRotate && isRotating {
            self.gradientLayer.removeAnimation(forKey: AyuGramAvatarRingNode.rotationKey)
        }
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 0.0
        _ = color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "\(Int(r * 255.0)),\(Int(g * 255.0)),\(Int(b * 255.0))"
    }

    private static func colors(style: AyuGramEffectsSettings.RingColor, accent: UIColor) -> [UIColor] {
        switch style {
        case .accent:
            return self.accentGradient(accent)
        case .blue:
            return self.solidGradient(UIColor(rgb: 0x2f8cff))
        case .teal:
            return self.solidGradient(UIColor(rgb: 0x1fc7c1))
        case .green:
            return self.solidGradient(UIColor(rgb: 0x34c759))
        case .gold:
            return self.solidGradient(UIColor(rgb: 0xf5b80f))
        case .orange:
            return self.solidGradient(UIColor(rgb: 0xff8a1f))
        case .red:
            return self.solidGradient(UIColor(rgb: 0xff3b30))
        case .pink:
            return self.solidGradient(UIColor(rgb: 0xff4f9a))
        case .purple:
            return self.solidGradient(UIColor(rgb: 0xa259ff))
        case .white:
            return [UIColor(white: 1.0, alpha: 1.0), UIColor(white: 0.62, alpha: 1.0), UIColor(white: 0.95, alpha: 1.0), UIColor(white: 0.5, alpha: 1.0), UIColor(white: 1.0, alpha: 1.0)]
        case .aurora:
            return self.loop([0x34e89e, 0x0fb5d7, 0x7b5cff, 0x1fd1a5])
        case .sunset:
            return self.loop([0xff5f6d, 0xffc371, 0xff8a5c, 0xc850c0])
        case .ocean:
            return self.loop([0x00c6ff, 0x0052d4, 0x00e0c7, 0x4364f7])
        case .neon:
            return self.loop([0xff00cc, 0x00f0ff, 0x7a00ff, 0x39ff14])
        case .fire:
            return self.loop([0xff2e00, 0xffb300, 0xff5e00, 0xffe259])
        case .rainbow:
            return self.loop([0xff3b30, 0xff9500, 0xffcc00, 0x34c759, 0x00c7be, 0x007aff, 0xaf52de])
        }
    }

    private static func loop(_ values: [UInt32]) -> [UIColor] {
        var colors = values.map { UIColor(rgb: $0) }
        if let first = colors.first {
            colors.append(first)
        }
        return colors
    }

    private static func solidGradient(_ color: UIColor) -> [UIColor] {
        return [
            color,
            self.adjusted(color, hueDelta: 0.0, saturation: 0.55, brightnessDelta: 0.3),
            color,
            self.adjusted(color, hueDelta: 0.0, saturation: 1.0, brightnessDelta: -0.32),
            color
        ]
    }

    private static func accentGradient(_ accent: UIColor) -> [UIColor] {
        return [
            accent,
            self.adjusted(accent, hueDelta: 0.14, saturation: nil, brightnessDelta: 0.18),
            self.adjusted(accent, hueDelta: 0.28, saturation: nil, brightnessDelta: 0.05),
            self.adjusted(accent, hueDelta: -0.12, saturation: nil, brightnessDelta: 0.1),
            accent
        ]
    }

    private static func adjusted(_ color: UIColor, hueDelta: CGFloat, saturation: CGFloat?, brightnessDelta: CGFloat) -> UIColor {
        var hue: CGFloat = 0.0
        var currentSaturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        guard color.getHue(&hue, saturation: &currentSaturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }
        var value = hue + hueDelta
        value -= floor(value)
        let resultSaturation: CGFloat
        if let saturation {
            resultSaturation = max(0.0, min(1.0, currentSaturation * saturation))
        } else {
            resultSaturation = max(0.45, currentSaturation)
        }
        return UIColor(hue: value, saturation: resultSaturation, brightness: max(0.0, min(1.0, brightness + brightnessDelta)), alpha: 1.0)
    }
}
