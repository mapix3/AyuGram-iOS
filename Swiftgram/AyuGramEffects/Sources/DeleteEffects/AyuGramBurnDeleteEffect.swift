import Foundation
import UIKit
import QuartzCore

enum AyuGramBurnDeleteEffect {
    private static let burnDuration: Double = 1.05
    private static let frameCount = 34
    private static let maxCellCount: CGFloat = 36000.0
    static let collapseDelay: Double = burnDuration * 0.82

    static func run(in container: CALayer, image: CGImage, imageScale: CGFloat) -> Double {
        let size = container.bounds.size
        let gridScale = min(0.5, sqrt(maxCellCount / max(1.0, size.width * size.height)))
        let gridWidth = max(4, Int(ceil(size.width * gridScale)))
        let gridHeight = max(4, Int(ceil(size.height * gridScale)))
        let cellCount = gridWidth * gridHeight
        let cellWidth = Float(size.width) / Float(gridWidth)
        let cellHeight = Float(size.height) / Float(gridHeight)

        var coverage = [Float](repeating: 1.0, count: cellCount)
        if let bytes = AyuGramDeleteEffectSupport.rgbaBytes(image: image, width: gridWidth, height: gridHeight) {
            for i in 0 ..< cellCount {
                coverage[i] = Float(bytes[i * 4 + 3]) / 255.0
            }
        }

        let seed = Int.random(in: 0 ..< 1_000_000)
        let width = Float(size.width)
        let height = Float(size.height)
        let originX: Float
        let originY: Float
        switch Int.random(in: 0 ..< 4) {
        case 0:
            originX = Float.random(in: 0.0 ... 1.0) * width
            originY = 0.0
        case 1:
            originX = Float.random(in: 0.0 ... 1.0) * width
            originY = height
        case 2:
            originX = 0.0
            originY = Float.random(in: 0.0 ... 1.0) * height
        default:
            originX = width
            originY = Float.random(in: 0.0 ... 1.0) * height
        }
        let farX: Float = max(originX, width - originX)
        let farY: Float = max(originY, height - originY)
        let maxDistance: Float = max(1.0, (farX * farX + farY * farY).squareRoot())

        var order = [Float](repeating: 0.0, count: cellCount)
        var minValue = Float.greatestFiniteMagnitude
        var maxValue = -Float.greatestFiniteMagnitude
        for y in 0 ..< gridHeight {
            for x in 0 ..< gridWidth {
                let px = (Float(x) + 0.5) * cellWidth
                let py = (Float(y) + 0.5) * cellHeight
                let noise = fractalNoise(x: px / 22.0, y: py / 22.0, seed: seed)
                let dx = px - originX
                let dy = py - originY
                let distance: Float = (dx * dx + dy * dy).squareRoot() / maxDistance
                let value: Float = 0.5 * noise + 0.5 * distance
                order[y * gridWidth + x] = value
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }
        }
        let range = max(0.0001, maxValue - minValue)
        for i in 0 ..< cellCount {
            order[i] = (order[i] - minValue) / range
        }

        let maskSoftness: Float = 0.03
        let fireInner: Float = 0.03
        let fireOuter: Float = 0.05
        let charWidth: Float = 0.14

        var maskFrames: [CGImage] = []
        var glowFrames: [CGImage] = []
        var edgePositions: [NSValue] = []
        var edgeSizes: [NSValue] = []
        var lastEdgePosition = CGPoint(x: size.width / 2.0, y: size.height / 2.0)

        var maskBytes = [UInt8](repeating: 0, count: cellCount * 4)
        var glowBytes = [UInt8](repeating: 0, count: cellCount * 4)

        for frame in 0 ..< frameCount {
            let linear = Float(frame) / Float(frameCount - 1)
            let progress = linear * linear * (3.0 - 2.0 * linear) * 0.7 + linear * 0.3
            let threshold = -0.06 + progress * 1.2

            var edgeMinX = Int.max
            var edgeMinY = Int.max
            var edgeMaxX = -1
            var edgeMaxY = -1

            for y in 0 ..< gridHeight {
                for x in 0 ..< gridWidth {
                    let i = y * gridWidth + x
                    let d = order[i] - threshold
                    let visible = min(1.0, max(0.0, d / maskSoftness))

                    var fire: Float = 0.0
                    if d > -fireInner && d < fireOuter {
                        fire = d < 0.0 ? (1.0 + d / fireInner) : (1.0 - d / fireOuter)
                    }
                    let char: Float = (d >= 0.0 && d < charWidth) ? 0.7 * (1.0 - d / charWidth) * (1.0 - d / charWidth) : 0.0
                    let charVisible = char * (1.0 - fire)

                    let a = coverage[i]
                    let red: Float = (1.0 * fire + 0.12 * charVisible) * a
                    let green: Float = ((0.35 + 0.55 * fire) * fire + 0.04 * charVisible) * a
                    let blue: Float = ((0.05 + 0.35 * fire * fire) * fire) * a
                    let alpha: Float = (fire + charVisible) * a

                    let offset = i * 4
                    glowBytes[offset] = AyuGramDeleteEffectSupport.byte(red)
                    glowBytes[offset + 1] = AyuGramDeleteEffectSupport.byte(green)
                    glowBytes[offset + 2] = AyuGramDeleteEffectSupport.byte(blue)
                    glowBytes[offset + 3] = AyuGramDeleteEffectSupport.byte(alpha)

                    let maskValue = AyuGramDeleteEffectSupport.byte(visible)
                    maskBytes[offset] = maskValue
                    maskBytes[offset + 1] = maskValue
                    maskBytes[offset + 2] = maskValue
                    maskBytes[offset + 3] = maskValue

                    if fire * a > 0.5 {
                        edgeMinX = min(edgeMinX, x)
                        edgeMinY = min(edgeMinY, y)
                        edgeMaxX = max(edgeMaxX, x)
                        edgeMaxY = max(edgeMaxY, y)
                    }
                }
            }

            guard let maskImage = AyuGramDeleteEffectSupport.makeImage(width: gridWidth, height: gridHeight, bytes: maskBytes), let glowImage = AyuGramDeleteEffectSupport.makeImage(width: gridWidth, height: gridHeight, bytes: glowBytes) else {
                return fallback(in: container, image: image, imageScale: imageScale)
            }
            maskFrames.append(maskImage)
            glowFrames.append(glowImage)

            if edgeMaxX >= 0 {
                let minX = CGFloat(Float(edgeMinX) * cellWidth)
                let minY = CGFloat(Float(edgeMinY) * cellHeight)
                let maxX = CGFloat(Float(edgeMaxX + 1) * cellWidth)
                let maxY = CGFloat(Float(edgeMaxY + 1) * cellHeight)
                lastEdgePosition = CGPoint(x: (minX + maxX) / 2.0, y: (minY + maxY) / 2.0)
                edgePositions.append(NSValue(cgPoint: lastEdgePosition))
                edgeSizes.append(NSValue(cgSize: CGSize(width: maxX - minX, height: maxY - minY)))
            } else {
                edgePositions.append(NSValue(cgPoint: lastEdgePosition))
                edgeSizes.append(NSValue(cgSize: CGSize(width: 1.0, height: 1.0)))
            }
        }

        guard let finalMask = maskFrames.last, let finalGlow = glowFrames.last else {
            return fallback(in: container, image: image, imageScale: imageScale)
        }

        let snapshotLayer = CALayer()
        snapshotLayer.frame = container.bounds
        snapshotLayer.contents = image
        snapshotLayer.contentsScale = imageScale

        let maskLayer = CALayer()
        maskLayer.frame = snapshotLayer.bounds
        maskLayer.contents = finalMask
        snapshotLayer.mask = maskLayer
        container.addSublayer(snapshotLayer)

        let glowLayer = CALayer()
        glowLayer.frame = container.bounds
        glowLayer.contents = finalGlow
        container.addSublayer(glowLayer)

        maskLayer.add(contentsAnimation(values: maskFrames), forKey: "ayuBurn")
        glowLayer.add(contentsAnimation(values: glowFrames), forKey: "ayuBurn")

        if let smokeImage = AyuGramDeleteEffectSupport.radialGlowImage(diameter: 32, inner: UIColor(white: 0.55, alpha: 0.5), outer: UIColor(white: 0.4, alpha: 0.22)) {
            let smoke = CAEmitterCell()
            smoke.contents = smokeImage
            smoke.birthRate = Float(min(36.0, max(10.0, (size.width + size.height) / 14.0)))
            smoke.lifetime = 0.9
            smoke.lifetimeRange = 0.25
            smoke.velocity = 16.0
            smoke.velocityRange = 8.0
            smoke.emissionLongitude = -CGFloat.pi / 2.0
            smoke.emissionRange = CGFloat.pi / 5.0
            smoke.yAcceleration = -18.0
            smoke.scale = 0.35
            smoke.scaleRange = 0.12
            smoke.scaleSpeed = 0.45
            smoke.alphaSpeed = -0.75
            smoke.spinRange = 1.2

            let smokeEmitter = CAEmitterLayer()
            smokeEmitter.frame = container.bounds
            smokeEmitter.emitterShape = .rectangle
            smokeEmitter.emitterMode = .surface
            smokeEmitter.emitterPosition = lastEdgePosition
            smokeEmitter.emitterSize = CGSize(width: 1.0, height: 1.0)
            smokeEmitter.emitterCells = [smoke]
            container.insertSublayer(smokeEmitter, at: 0)

            let smokePosition = CAKeyframeAnimation(keyPath: "emitterPosition")
            smokePosition.values = edgePositions
            smokePosition.duration = burnDuration
            smokeEmitter.add(smokePosition, forKey: "ayuBurnSmokePosition")

            let smokeSize = CAKeyframeAnimation(keyPath: "emitterSize")
            smokeSize.values = edgeSizes
            smokeSize.duration = burnDuration
            smokeEmitter.add(smokeSize, forKey: "ayuBurnSmokeSize")

            DispatchQueue.main.asyncAfter(deadline: .now() + burnDuration * 0.8, execute: { [weak smokeEmitter] in
                smokeEmitter?.birthRate = 0.0
            })
        }

        var emberLifetime: Double = 0.0
        if let emberImage = AyuGramDeleteEffectSupport.radialGlowImage(diameter: 16, inner: UIColor(white: 1.0, alpha: 1.0), outer: UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 0.9)) {
            let cell = CAEmitterCell()
            cell.contents = emberImage
            cell.birthRate = Float(min(140.0, max(36.0, (size.width + size.height) / 2.5)))
            cell.lifetime = 0.7
            cell.lifetimeRange = 0.3
            cell.velocity = 34.0
            cell.velocityRange = 24.0
            cell.emissionLongitude = -CGFloat.pi / 2.0
            cell.emissionRange = CGFloat.pi / 2.5
            cell.yAcceleration = -40.0
            cell.scale = 0.26
            cell.scaleRange = 0.14
            cell.scaleSpeed = -0.3
            cell.alphaSpeed = -1.3
            cell.alphaRange = 0.3
            cell.color = UIColor(red: 1.0, green: 0.62, blue: 0.22, alpha: 1.0).cgColor
            cell.greenRange = 0.2

            let emitter = CAEmitterLayer()
            emitter.frame = container.bounds
            emitter.emitterShape = .rectangle
            emitter.emitterMode = .surface
            emitter.renderMode = .additive
            emitter.emitterPosition = lastEdgePosition
            emitter.emitterSize = CGSize(width: 1.0, height: 1.0)
            emitter.emitterCells = [cell]
            container.addSublayer(emitter)

            let positionAnimation = CAKeyframeAnimation(keyPath: "emitterPosition")
            positionAnimation.values = edgePositions
            positionAnimation.duration = burnDuration
            emitter.add(positionAnimation, forKey: "ayuBurnPosition")

            let sizeAnimation = CAKeyframeAnimation(keyPath: "emitterSize")
            sizeAnimation.values = edgeSizes
            sizeAnimation.duration = burnDuration
            emitter.add(sizeAnimation, forKey: "ayuBurnSize")

            DispatchQueue.main.asyncAfter(deadline: .now() + burnDuration * 0.9, execute: { [weak emitter] in
                emitter?.birthRate = 0.0
            })
            emberLifetime = 1.0
        }

        return burnDuration + emberLifetime
    }

    private static func contentsAnimation(values: [CGImage]) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = values
        animation.duration = burnDuration
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return animation
    }

    private static func fallback(in container: CALayer, image: CGImage, imageScale: CGFloat) -> Double {
        let snapshotLayer = CALayer()
        snapshotLayer.frame = container.bounds
        snapshotLayer.contents = image
        snapshotLayer.contentsScale = imageScale
        snapshotLayer.opacity = 0.0
        container.addSublayer(snapshotLayer)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0 as NSNumber
        animation.toValue = 0.0 as NSNumber
        animation.duration = 0.4
        snapshotLayer.add(animation, forKey: "ayuBurnFallback")
        return 0.4
    }

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ seed &* 1442695041)
        h = (h ^ (h >> 13)) &* 1274126177
        h = h ^ (h >> 16)
        return Float(h & 0xffff) / 65535.0
    }

    private static func valueNoise(x: Float, y: Float, seed: Int) -> Float {
        let fx = x.rounded(.down)
        let fy = y.rounded(.down)
        let ix = Int(fx)
        let iy = Int(fy)
        let tx = x - fx
        let ty = y - fy
        let u = tx * tx * (3.0 - 2.0 * tx)
        let v = ty * ty * (3.0 - 2.0 * ty)
        let a = hash(ix, iy, seed)
        let b = hash(ix + 1, iy, seed)
        let c = hash(ix, iy + 1, seed)
        let d = hash(ix + 1, iy + 1, seed)
        let top = a + (b - a) * u
        let bottom = c + (d - c) * u
        return top + (bottom - top) * v
    }

    private static func fractalNoise(x: Float, y: Float, seed: Int) -> Float {
        var result: Float = 0.0
        var amplitude: Float = 0.5
        var frequency: Float = 1.0
        var total: Float = 0.0
        for octave in 0 ..< 3 {
            result += amplitude * valueNoise(x: x * frequency, y: y * frequency, seed: seed &+ octave &* 7919)
            total += amplitude
            amplitude *= 0.5
            frequency *= 2.0
        }
        return result / total
    }
}
