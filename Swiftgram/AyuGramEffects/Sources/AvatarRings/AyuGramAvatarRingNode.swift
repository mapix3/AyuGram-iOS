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
    private static let rotationDuration: Double = 6.0

    private let gradientLayer: CAGradientLayer
    private let ringMaskLayer: CAShapeLayer
    private var observer: AyuGramEffectsObserver?

    private var isOnline = false
    private var lineWidth: CGFloat = 2.0
    private var accentColor: UIColor?
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
            self?.updateState()
        })
        self.applyGeometry()
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
        let colorChanged = self.accentColor.flatMap({ $0.isEqual(accentColor) }) != true
        let geometryChanged = self.ringSize != size || self.lineWidth != lineWidth
        self.ringSize = size
        self.lineWidth = lineWidth
        self.accentColor = accentColor
        self.isOnline = isOnline

        if colorChanged {
            self.gradientLayer.colors = AyuGramAvatarRingNode.colors(accent: accentColor).map { $0.cgColor }
        }
        if geometryChanged && self.isNodeLoaded {
            self.applyGeometry()
        }
        if self.isNodeLoaded {
            self.updateState()
        }
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
            self.gradientLayer.add(animation, forKey: AyuGramAvatarRingNode.rotationKey)
        } else if !shouldRotate && isRotating {
            self.gradientLayer.removeAnimation(forKey: AyuGramAvatarRingNode.rotationKey)
        }
    }

    private static func colors(accent: UIColor) -> [UIColor] {
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        guard accent.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return [accent, accent.withAlphaComponent(0.35), accent]
        }
        func shifted(_ delta: CGFloat, brightnessDelta: CGFloat) -> UIColor {
            var value = hue + delta
            value -= floor(value)
            return UIColor(hue: value, saturation: max(0.35, saturation), brightness: max(0.0, min(1.0, brightness + brightnessDelta)), alpha: 1.0)
        }
        return [accent, shifted(0.09, brightnessDelta: 0.12), shifted(-0.09, brightnessDelta: 0.05), accent]
    }
}
