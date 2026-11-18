import Foundation
import UIKit
import QuartzCore

enum AyuGramImplodeDeleteEffect {
    private static let collapseDuration: Double = 0.55
    private static let sparkDuration: Double = 0.38
    static let collapseDelay: Double = collapseDuration * 0.9

    static func run(in container: CALayer, image: CGImage, imageScale: CGFloat) -> Double {
        let size = container.bounds.size
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let now = CACurrentMediaTime()

        let body = CALayer()
        body.frame = container.bounds
        body.opacity = 0.0
        container.addSublayer(body)

        let sharpLayer = CALayer()
        sharpLayer.frame = body.bounds
        sharpLayer.contents = image
        sharpLayer.contentsScale = imageScale
        body.addSublayer(sharpLayer)

        if let softImage = downsampled(image: image, size: size) {
            let softLayer = CALayer()
            softLayer.frame = body.bounds
            softLayer.contents = softImage
            softLayer.magnificationFilter = .linear
            softLayer.opacity = 0.0
            body.addSublayer(softLayer)

            let softAnimation = CAKeyframeAnimation(keyPath: "opacity")
            softAnimation.values = [0.0 as NSNumber, 0.9 as NSNumber, 1.0 as NSNumber]
            softAnimation.keyTimes = [0.0 as NSNumber, 0.5 as NSNumber, 1.0 as NSNumber]
            softAnimation.duration = collapseDuration
            softAnimation.fillMode = .forwards
            softAnimation.isRemovedOnCompletion = false
            softLayer.add(softAnimation, forKey: "ayuImplodeSoft")
        }

        let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnimation.values = [1.0 as NSNumber, 1.04 as NSNumber, 0.02 as NSNumber]
        scaleAnimation.keyTimes = [0.0 as NSNumber, 0.15 as NSNumber, 1.0 as NSNumber]
        scaleAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn)
        ]

        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.fromValue = 0.0 as NSNumber
        rotationAnimation.toValue = NSNumber(value: Bool.random() ? 0.8 : -0.8)
        rotationAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = [1.0 as NSNumber, 1.0 as NSNumber, 0.0 as NSNumber]
        opacityAnimation.keyTimes = [0.0 as NSNumber, 0.7 as NSNumber, 1.0 as NSNumber]

        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, rotationAnimation, opacityAnimation]
        group.duration = collapseDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        body.add(group, forKey: "ayuImplode")

        let sparkBegin = now + collapseDuration * 0.85
        if let glowImage = AyuGramDeleteEffectSupport.radialGlowImage(diameter: 64, inner: UIColor(white: 1.0, alpha: 1.0), outer: UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.85)) {
            let flash = CALayer()
            flash.bounds = CGRect(x: 0.0, y: 0.0, width: 36.0, height: 36.0)
            flash.position = center
            flash.contents = glowImage
            flash.opacity = 0.0
            container.addSublayer(flash)

            let flashScale = CABasicAnimation(keyPath: "transform.scale")
            flashScale.fromValue = 0.2 as NSNumber
            flashScale.toValue = 1.3 as NSNumber
            flashScale.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let flashOpacity = CAKeyframeAnimation(keyPath: "opacity")
            flashOpacity.values = [0.0 as NSNumber, 1.0 as NSNumber, 0.0 as NSNumber]
            flashOpacity.keyTimes = [0.0 as NSNumber, 0.3 as NSNumber, 1.0 as NSNumber]

            let flashGroup = CAAnimationGroup()
            flashGroup.animations = [flashScale, flashOpacity]
            flashGroup.duration = sparkDuration
            flashGroup.beginTime = sparkBegin
            flashGroup.fillMode = .forwards
            flashGroup.isRemovedOnCompletion = false
            flash.add(flashGroup, forKey: "ayuImplodeFlash")

            let dotCount = 8
            for index in 0 ..< dotCount {
                let angle = CGFloat(index) / CGFloat(dotCount) * 2.0 * CGFloat.pi + CGFloat.random(in: -0.3 ... 0.3)
                let distance = CGFloat.random(in: 18.0 ... 32.0)
                let target = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)

                let dot = CALayer()
                dot.bounds = CGRect(x: 0.0, y: 0.0, width: 6.0, height: 6.0)
                dot.position = center
                dot.contents = glowImage
                dot.opacity = 0.0
                container.addSublayer(dot)

                let dotPosition = CABasicAnimation(keyPath: "position")
                dotPosition.fromValue = NSValue(cgPoint: center)
                dotPosition.toValue = NSValue(cgPoint: target)
                dotPosition.timingFunction = CAMediaTimingFunction(name: .easeOut)

                let dotOpacity = CABasicAnimation(keyPath: "opacity")
                dotOpacity.fromValue = 1.0 as NSNumber
                dotOpacity.toValue = 0.0 as NSNumber

                let dotScale = CABasicAnimation(keyPath: "transform.scale")
                dotScale.fromValue = 1.0 as NSNumber
                dotScale.toValue = 0.3 as NSNumber

                let dotGroup = CAAnimationGroup()
                dotGroup.animations = [dotPosition, dotOpacity, dotScale]
                dotGroup.duration = sparkDuration
                dotGroup.beginTime = sparkBegin
                dotGroup.fillMode = .forwards
                dotGroup.isRemovedOnCompletion = false
                dot.add(dotGroup, forKey: "ayuImplodeDot")
            }
        }

        return collapseDuration * 0.85 + sparkDuration
    }

    private static func downsampled(image: CGImage, size: CGSize) -> CGImage? {
        let width = max(2, Int(size.width / 10.0))
        let height = max(2, Int(size.height / 10.0))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }
}
