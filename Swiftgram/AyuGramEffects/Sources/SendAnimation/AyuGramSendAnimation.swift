import Foundation
import UIKit
import Display
import SGSimpleSettings

public enum AyuGramSendAnimationStyle: Equatable {
    case standard
    case spring
    case sparkles
    case warp
}

public struct AyuGramSendFlight {
    public let targetFrame: CGRect
    public let startOffset: CGPoint
    public let verticalDuration: Double
    public let verticalCurve: ContainedViewLayoutTransitionCurve
    public let horizontalDuration: Double
    public let horizontalCurve: ContainedViewLayoutTransitionCurve

    public init(targetFrame: CGRect, startOffset: CGPoint, verticalDuration: Double, verticalCurve: ContainedViewLayoutTransitionCurve, horizontalDuration: Double, horizontalCurve: ContainedViewLayoutTransitionCurve) {
        self.targetFrame = targetFrame
        self.startOffset = startOffset
        self.verticalDuration = verticalDuration
        self.verticalCurve = verticalCurve
        self.horizontalDuration = horizontalDuration
        self.horizontalCurve = horizontalCurve
    }

    var totalDuration: Double {
        return max(self.verticalDuration, self.horizontalDuration)
    }

    func offset(at time: Double) -> CGPoint {
        let verticalProgress: CGFloat = self.verticalDuration > 0.0 ? CGFloat(min(1.0, max(0.0, time / self.verticalDuration))) : 1.0
        let horizontalProgress: CGFloat = self.horizontalDuration > 0.0 ? CGFloat(min(1.0, max(0.0, time / self.horizontalDuration))) : 1.0
        let fy = self.verticalCurve.solve(at: verticalProgress)
        let fx = self.horizontalCurve.solve(at: horizontalProgress)
        return CGPoint(x: self.startOffset.x * (1.0 - fx), y: self.startOffset.y * (1.0 - fy))
    }
}

public enum AyuGramSendAnimation {
    public static var currentStyle: AyuGramSendAnimationStyle {
        guard AyuGramEffectsRuntime.motionAllowed else {
            return .standard
        }
        switch AyuGramEffectsRuntime.settings.activeSendStyle {
        case .standard:
            return .standard
        case .spring:
            return .spring
        case .sparkles:
            return .sparkles
        case .warp:
            return .warp
        }
    }

    public static func addSparkles(hostLayer: CALayer, flight: AyuGramSendFlight, color: UIColor, accentColor: UIColor) {
        guard let image = sparkleImage else {
            return
        }
        let duration = flight.totalDuration
        let now = hostLayer.convertTime(CACurrentMediaTime(), from: nil)
        let targetCenter = CGPoint(x: flight.targetFrame.midX, y: flight.targetFrame.midY)
        let emitterSize = CGSize(width: max(4.0, flight.targetFrame.width * 0.85), height: max(4.0, flight.targetFrame.height * 0.85))

        let trailLayer = CAEmitterLayer()
        trailLayer.frame = CGRect(origin: CGPoint(), size: hostLayer.bounds.size)
        trailLayer.emitterShape = .rectangle
        trailLayer.emitterMode = .outline
        trailLayer.emitterSize = emitterSize
        trailLayer.emitterPosition = targetCenter
        trailLayer.beginTime = now
        trailLayer.emitterCells = [
            makeSparkleCell(image: image, color: color, birthRate: 70.0, velocity: 28.0, lifetime: 0.45),
            makeSparkleCell(image: image, color: accentColor, birthRate: 50.0, velocity: 22.0, lifetime: 0.4)
        ]
        hostLayer.addSublayer(trailLayer)

        let sampleCount = 24
        var values: [NSValue] = []
        var keyTimes: [NSNumber] = []
        for i in 0 ... sampleCount {
            let fraction = Double(i) / Double(sampleCount)
            let offset = flight.offset(at: fraction * duration)
            values.append(NSValue(cgPoint: CGPoint(x: targetCenter.x + offset.x, y: targetCenter.y + offset.y)))
            keyTimes.append(NSNumber(value: fraction))
        }
        let pathAnimation = CAKeyframeAnimation(keyPath: "emitterPosition")
        pathAnimation.values = values
        pathAnimation.keyTimes = keyTimes
        pathAnimation.calculationMode = .linear
        pathAnimation.duration = max(0.01, duration)
        pathAnimation.fillMode = .both
        pathAnimation.isRemovedOnCompletion = false
        trailLayer.add(pathAnimation, forKey: "ayuGramSendSparklesPath")

        let burstLayer = CAEmitterLayer()
        burstLayer.frame = CGRect(origin: CGPoint(), size: hostLayer.bounds.size)
        burstLayer.emitterShape = .rectangle
        burstLayer.emitterMode = .outline
        burstLayer.emitterSize = CGSize(width: max(4.0, flight.targetFrame.width), height: max(4.0, flight.targetFrame.height))
        burstLayer.emitterPosition = targetCenter
        burstLayer.beginTime = now
        burstLayer.birthRate = 0.0
        burstLayer.emitterCells = [
            makeSparkleCell(image: image, color: color, birthRate: 520.0, velocity: 85.0, lifetime: 0.5),
            makeSparkleCell(image: image, color: accentColor, birthRate: 360.0, velocity: 65.0, lifetime: 0.45),
            makeSparkleCell(image: image, color: .white, birthRate: 160.0, velocity: 45.0, lifetime: 0.35)
        ]
        hostLayer.addSublayer(burstLayer)

        let landingDelay = duration * 0.85
        let burstLength = 0.06
        let particleLifetime = 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + landingDelay, execute: { [weak trailLayer, weak burstLayer] in
            trailLayer?.birthRate = 0.0
            burstLayer?.birthRate = 1.0
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + landingDelay + burstLength, execute: { [weak burstLayer] in
            burstLayer?.birthRate = 0.0
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + landingDelay + burstLength + particleLifetime, execute: { [weak trailLayer, weak burstLayer] in
            trailLayer?.removeFromSuperlayer()
            burstLayer?.removeFromSuperlayer()
        })
    }

    private static func makeSparkleCell(image: CGImage, color: UIColor, birthRate: Float, velocity: CGFloat, lifetime: Float) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        cell.color = color.cgColor
        cell.birthRate = birthRate
        cell.lifetime = lifetime
        cell.lifetimeRange = lifetime * 0.35
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.6
        cell.emissionRange = .pi * 2.0
        cell.yAcceleration = 40.0
        cell.scale = 0.34
        cell.scaleRange = 0.16
        cell.scaleSpeed = -0.45
        cell.alphaSpeed = -1.0 / max(0.1, lifetime)
        cell.spin = 2.0
        cell.spinRange = 5.0
        return cell
    }

    private static let sparkleImage: CGImage? = {
        let side: CGFloat = 24.0
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let image = renderer.image { context in
            let center = CGPoint(x: side * 0.5, y: side * 0.5)
            let glowColors = [UIColor(white: 1.0, alpha: 0.55).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
            let glowLocations: [CGFloat] = [0.0, 1.0]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: glowLocations) {
                context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: side * 0.3, options: [])
            }
            let radius = side * 0.5 - 1.0
            let pinch: CGFloat = 2.0
            let path = UIBezierPath()
            path.move(to: CGPoint(x: center.x, y: center.y - radius))
            path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), controlPoint: CGPoint(x: center.x + pinch, y: center.y - pinch))
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), controlPoint: CGPoint(x: center.x + pinch, y: center.y + pinch))
            path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), controlPoint: CGPoint(x: center.x - pinch, y: center.y + pinch))
            path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), controlPoint: CGPoint(x: center.x - pinch, y: center.y - pinch))
            path.close()
            UIColor.white.setFill()
            path.fill()
        }
        return image.cgImage
    }()

    public static func addWarp(bubbleLayer: CALayer, bubbleRect: CGRect, hostLayer: CALayer, flight: AyuGramSendFlight, color: UIColor, accentColor: UIColor) {
        let duration = max(0.05, flight.totalDuration)
        let delta = flight.startOffset
        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)

        if distance > 1.0 && bubbleRect.width > 1.0 && bubbleRect.height > 1.0 {
            let direction = CGPoint(x: delta.x / distance, y: delta.y / distance)
            let alongY = abs(direction.y)
            let alongX = abs(direction.x)

            let sizeFactor = min(1.0, 90.0 / max(40.0, bubbleRect.height))
            let stretch = 0.24 * sizeFactor
            let thin = 0.1 * sizeFactor
            let squash = 0.06 * sizeFactor
            let along: [CGFloat] = [0.0, stretch, stretch * 0.7, -squash, 0.0]
            let across: [CGFloat] = [0.0, -thin, -thin * 0.7, squash * 0.6, 0.0]
            let keyTimes: [NSNumber] = [0.0, 0.18, 0.6, 0.86, 1.0]

            let anchor = CGPoint(x: bubbleLayer.bounds.minX + bubbleLayer.anchorPoint.x * bubbleLayer.bounds.width, y: bubbleLayer.bounds.minY + bubbleLayer.anchorPoint.y * bubbleLayer.bounds.height)
            let bubbleCenter = CGPoint(x: bubbleRect.midX, y: bubbleRect.midY)

            var scaleXValues: [Any] = []
            var scaleYValues: [Any] = []
            var positionValues: [Any] = []
            for i in 0 ..< along.count {
                let dx = along[i] * alongX + across[i] * alongY
                let dy = along[i] * alongY + across[i] * alongX
                scaleXValues.append(NSNumber(value: Double(dx)))
                scaleYValues.append(NSNumber(value: Double(dy)))
                positionValues.append(NSValue(cgPoint: CGPoint(x: -dx * (bubbleCenter.x - anchor.x), y: -dy * (bubbleCenter.y - anchor.y))))
            }
            let timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .linear),
                CAMediaTimingFunction(name: .easeIn),
                CAMediaTimingFunction(name: .easeOut)
            ]

            let now = bubbleLayer.convertTime(CACurrentMediaTime(), from: nil)
            let animations: [(String, String, [Any])] = [
                ("transform.scale.x", "ayuGramWarpScaleX", scaleXValues),
                ("transform.scale.y", "ayuGramWarpScaleY", scaleYValues),
                ("position", "ayuGramWarpPosition", positionValues)
            ]
            for (keyPath, key, values) in animations {
                let animation = CAKeyframeAnimation(keyPath: keyPath)
                animation.values = values
                animation.keyTimes = keyTimes
                animation.timingFunctions = timingFunctions
                animation.duration = duration
                animation.beginTime = now
                animation.isAdditive = true
                animation.fillMode = .backwards
                bubbleLayer.add(animation, forKey: key)
            }

            let streakWidth = max(6.0, (alongY * bubbleRect.width + alongX * bubbleRect.height) * 0.7)
            let streakLength = min(240.0, distance * 0.65)
            let streakLayer = CAGradientLayer()
            streakLayer.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0.0).cgColor]
            streakLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
            streakLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
            streakLayer.anchorPoint = CGPoint(x: 0.5, y: 0.0)
            streakLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: streakWidth, height: 0.0))
            streakLayer.position = bubbleCenter
            streakLayer.cornerRadius = streakWidth * 0.5
            streakLayer.transform = CATransform3DMakeRotation(atan2(-direction.x, direction.y), 0.0, 0.0, 1.0)
            bubbleLayer.insertSublayer(streakLayer, at: 0)

            let streakAnimation = CAKeyframeAnimation(keyPath: "bounds.size.height")
            streakAnimation.values = [0.0, streakLength, streakLength * 0.55, 0.0, 0.0].map { NSNumber(value: Double($0)) }
            streakAnimation.keyTimes = [0.0, 0.2, 0.55, 0.8, 1.0]
            streakAnimation.duration = duration
            streakAnimation.beginTime = now
            streakAnimation.fillMode = .both
            streakAnimation.isRemovedOnCompletion = false
            streakLayer.add(streakAnimation, forKey: "ayuGramWarpStreak")

            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: { [weak streakLayer] in
                streakLayer?.removeFromSuperlayer()
            })
        }

        addLandingFlash(hostLayer: hostLayer, frame: flight.targetFrame, delay: duration * 0.82, accentColor: accentColor)
    }

    private static func addLandingFlash(hostLayer: CALayer, frame: CGRect, delay: Double, accentColor: UIColor) {
        guard frame.width > 1.0 && frame.height > 1.0 else {
            return
        }
        let cornerRadius = min(16.0, min(frame.width, frame.height) * 0.5)
        let beginTime = hostLayer.convertTime(CACurrentMediaTime(), from: nil) + delay
        let flashDuration = 0.3

        let flashLayer = CALayer()
        flashLayer.frame = frame
        flashLayer.cornerRadius = cornerRadius
        flashLayer.backgroundColor = UIColor.white.cgColor
        flashLayer.opacity = 0.0
        hostLayer.addSublayer(flashLayer)

        let flashAnimation = CAKeyframeAnimation(keyPath: "opacity")
        flashAnimation.values = [0.0, 0.5, 0.0] as [NSNumber]
        flashAnimation.keyTimes = [0.0, 0.25, 1.0]
        flashAnimation.duration = flashDuration
        flashAnimation.beginTime = beginTime
        flashLayer.add(flashAnimation, forKey: "ayuGramWarpFlash")

        let ringLayer = CAShapeLayer()
        ringLayer.frame = frame
        ringLayer.path = UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: frame.size), cornerRadius: cornerRadius).cgPath
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.strokeColor = accentColor.cgColor
        ringLayer.lineWidth = 2.0
        ringLayer.opacity = 0.0
        hostLayer.addSublayer(ringLayer)

        let ringOpacity = CAKeyframeAnimation(keyPath: "opacity")
        ringOpacity.values = [0.0, 0.85, 0.0] as [NSNumber]
        ringOpacity.keyTimes = [0.0, 0.2, 1.0]
        let ringScale = CABasicAnimation(keyPath: "transform.scale")
        ringScale.fromValue = NSNumber(value: 1.0)
        ringScale.toValue = NSNumber(value: Double(1.0 + min(0.2, 24.0 / max(frame.width, frame.height))))
        ringScale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let ringGroup = CAAnimationGroup()
        ringGroup.animations = [ringOpacity, ringScale]
        ringGroup.duration = flashDuration + 0.1
        ringGroup.beginTime = beginTime
        ringLayer.add(ringGroup, forKey: "ayuGramWarpRing")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + flashDuration + 0.15, execute: { [weak flashLayer, weak ringLayer] in
            flashLayer?.removeFromSuperlayer()
            ringLayer?.removeFromSuperlayer()
        })
    }
}
