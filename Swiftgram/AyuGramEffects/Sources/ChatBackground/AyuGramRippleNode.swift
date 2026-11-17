import Foundation
import UIKit
import AsyncDisplayKit

final class AyuGramRippleNode: ASDisplayNode {
    private final class Ripple {
        let container = CALayer()
        let crest = CAShapeLayer()
        let trough = CAShapeLayer()
        let inner = CAShapeLayer()
        let lens = CAGradientLayer()

        init() {
            for shape in [self.trough, self.crest, self.inner] {
                shape.fillColor = nil
                shape.lineCap = .round
                self.container.addSublayer(shape)
            }
            self.crest.strokeColor = UIColor(white: 1.0, alpha: 0.55).cgColor
            self.trough.strokeColor = UIColor(white: 0.0, alpha: 0.12).cgColor
            self.inner.strokeColor = UIColor(white: 1.0, alpha: 0.35).cgColor

            self.lens.type = .radial
            self.lens.colors = [UIColor(white: 1.0, alpha: 0.2).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
            self.lens.startPoint = CGPoint(x: 0.5, y: 0.5)
            self.lens.endPoint = CGPoint(x: 1.0, y: 1.0)
            self.container.insertSublayer(self.lens, at: 0)
        }
    }

    private static let maxActiveRipples = 10

    private var pool: [Ripple] = []
    private var activeCount = 0

    override init() {
        super.init()

        self.isLayerBacked = true
        self.isUserInteractionEnabled = false
    }

    private static func circle(radius: CGFloat) -> CGPath {
        return CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2.0, height: radius * 2.0), transform: nil)
    }

    func addRipple(at point: CGPoint, radius: CGFloat, duration: Double) {
        if self.activeCount >= AyuGramRippleNode.maxActiveRipples {
            return
        }
        self.activeCount += 1

        let ripple: Ripple
        if let reused = self.pool.popLast() {
            ripple = reused
        } else {
            ripple = Ripple()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock({ [weak self] in
            ripple.container.isHidden = true
            ripple.container.removeFromSuperlayer()
            guard let strongSelf = self else {
                return
            }
            strongSelf.activeCount -= 1
            strongSelf.pool.append(ripple)
        })

        ripple.container.isHidden = false
        ripple.container.opacity = 1.0
        ripple.container.position = point
        ripple.container.bounds = CGRect()
        if ripple.container.superlayer == nil {
            self.layer.addSublayer(ripple.container)
        }

        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.6, 0.35, 1.0)
        let startRadius: CGFloat = 3.0

        func animateRing(_ shape: CAShapeLayer, to finalRadius: CGFloat, fromWidth: CGFloat, toWidth: CGFloat, delay: Double, ringDuration: Double) {
            let fromPath = AyuGramRippleNode.circle(radius: startRadius)
            let toPath = AyuGramRippleNode.circle(radius: finalRadius)
            shape.path = toPath
            shape.lineWidth = toWidth
            shape.opacity = 0.0

            let beginTime = shape.convertTime(CACurrentMediaTime(), from: nil) + delay

            let path = CABasicAnimation(keyPath: "path")
            path.fromValue = fromPath
            path.toValue = toPath
            path.duration = ringDuration
            path.timingFunction = timing

            let width = CABasicAnimation(keyPath: "lineWidth")
            width.fromValue = fromWidth
            width.toValue = toWidth
            width.duration = ringDuration
            width.timingFunction = timing

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0.0, 1.0, 1.0, 0.0]
            opacity.keyTimes = [0.0, 0.08, 0.35, 1.0]
            opacity.duration = ringDuration

            let group = CAAnimationGroup()
            group.animations = [path, width, opacity]
            group.duration = ringDuration
            group.beginTime = beginTime
            group.fillMode = .backwards
            shape.add(group, forKey: "ripple")
        }

        animateRing(ripple.crest, to: radius, fromWidth: 3.0, toWidth: 0.6, delay: 0.0, ringDuration: duration)
        animateRing(ripple.trough, to: radius * 0.94, fromWidth: 5.0, toWidth: 1.0, delay: 0.0, ringDuration: duration)
        animateRing(ripple.inner, to: radius * 0.6, fromWidth: 2.0, toWidth: 0.5, delay: duration * 0.15, ringDuration: duration * 0.85)

        ripple.lens.bounds = CGRect(x: 0.0, y: 0.0, width: radius * 1.4, height: radius * 1.4)
        ripple.lens.position = CGPoint()
        ripple.lens.opacity = 0.0
        let lensScale = CABasicAnimation(keyPath: "transform.scale")
        lensScale.fromValue = 0.1
        lensScale.toValue = 1.0
        lensScale.duration = duration * 0.55
        lensScale.timingFunction = timing
        let lensOpacity = CABasicAnimation(keyPath: "opacity")
        lensOpacity.fromValue = 1.0
        lensOpacity.toValue = 0.0
        lensOpacity.duration = duration * 0.55
        let lensGroup = CAAnimationGroup()
        lensGroup.animations = [lensScale, lensOpacity]
        lensGroup.duration = duration * 0.55
        ripple.lens.add(lensGroup, forKey: "ripple")

        CATransaction.commit()
    }
}
