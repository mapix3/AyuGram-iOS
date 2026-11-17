import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SGSimpleSettings

final class AyuGramParticlesNode: ASDisplayNode {
    struct Configuration: Equatable {
        var style: AyuGramEffectsSettings.Particles
        var density: CGFloat
        var speed: CGFloat
    }

    private struct Spec {
        var birthRate: Float
        var lifetime: Float
        var lifetimeRange: Float
        var velocity: CGFloat
        var velocityRange: CGFloat
        var xAcceleration: CGFloat
        var yAcceleration: CGFloat
        var emissionLongitude: CGFloat
        var emissionRange: CGFloat
        var scale: CGFloat
        var scaleRange: CGFloat
        var spin: CGFloat
        var spinRange: CGFloat
        var fadeInSpeed: Float
        var twinkles: Bool
        var additive: Bool
        var opacity: Float
        var color: UIColor
        var direction: CGFloat
    }

    private static let referenceArea: CGFloat = 390.0 * 844.0

    private let emitterLayer = CAEmitterLayer()
    private let burstLayer = CAEmitterLayer()

    private var configuration: Configuration?
    private var cellsHeight: CGFloat = 0.0
    private var validSize: CGSize?
    private var isPaused = false
    private var burstGeneration = 0

    override init() {
        super.init()

        self.isLayerBacked = true
        self.isUserInteractionEnabled = false
    }

    override func didLoad() {
        super.didLoad()

        self.layer.masksToBounds = true

        self.emitterLayer.emitterShape = .rectangle
        self.emitterLayer.emitterMode = .surface
        self.layer.addSublayer(self.emitterLayer)

        self.burstLayer.emitterShape = .circle
        self.burstLayer.emitterMode = .outline
        self.burstLayer.emitterSize = CGSize(width: 28.0, height: 28.0)
        self.burstLayer.birthRate = 0.0
        self.layer.addSublayer(self.burstLayer)
    }

    private static func spec(for style: AyuGramEffectsSettings.Particles) -> Spec? {
        switch style {
        case .off:
            return nil
        case .snow:
            return Spec(birthRate: 8.0, lifetime: 0.0, lifetimeRange: 0.0, velocity: 40.0, velocityRange: 15.0, xAcceleration: 2.0, yAcceleration: 5.0, emissionLongitude: .pi / 2.0, emissionRange: .pi / 6.0, scale: 0.55, scaleRange: 0.3, spin: 0.0, spinRange: 1.0, fadeInSpeed: 0.8, twinkles: false, additive: false, opacity: 0.8, color: .white, direction: 1.0)
        case .stars:
            return Spec(birthRate: 6.0, lifetime: 4.0, lifetimeRange: 1.5, velocity: 4.0, velocityRange: 3.0, xAcceleration: 0.0, yAcceleration: 0.0, emissionLongitude: 0.0, emissionRange: .pi * 2.0, scale: 0.6, scaleRange: 0.2, spin: 0.0, spinRange: 0.6, fadeInSpeed: 0.7, twinkles: true, additive: true, opacity: 0.85, color: .white, direction: 0.0)
        case .fireflies:
            return Spec(birthRate: 2.5, lifetime: 7.0, lifetimeRange: 2.0, velocity: 12.0, velocityRange: 8.0, xAcceleration: 0.0, yAcceleration: -1.0, emissionLongitude: 0.0, emissionRange: .pi * 2.0, scale: 0.6, scaleRange: 0.2, spin: 0.0, spinRange: 0.0, fadeInSpeed: 0.5, twinkles: true, additive: true, opacity: 0.9, color: .white, direction: 0.0)
        case .petals:
            return Spec(birthRate: 3.0, lifetime: 0.0, lifetimeRange: 0.0, velocity: 45.0, velocityRange: 15.0, xAcceleration: 6.0, yAcceleration: 4.0, emissionLongitude: .pi / 2.0, emissionRange: .pi / 5.0, scale: 0.8, scaleRange: 0.35, spin: 1.2, spinRange: 3.0, fadeInSpeed: 0.8, twinkles: false, additive: false, opacity: 0.9, color: UIColor(red: 1.0, green: 0.95, blue: 0.97, alpha: 1.0), direction: 1.0)
        case .bubbles:
            return Spec(birthRate: 3.0, lifetime: 0.0, lifetimeRange: 0.0, velocity: 35.0, velocityRange: 12.0, xAcceleration: 0.0, yAcceleration: -4.0, emissionLongitude: -.pi / 2.0, emissionRange: .pi / 10.0, scale: 0.6, scaleRange: 0.4, spin: 0.0, spinRange: 0.0, fadeInSpeed: 0.8, twinkles: false, additive: false, opacity: 0.85, color: .white, direction: -1.0)
        }
    }

    func update(configuration: Configuration, size: CGSize) {
        guard size.width > 0.0, size.height > 0.0, let spec = AyuGramParticlesNode.spec(for: configuration.style), let sprite = AyuGramParticleImages.image(for: configuration.style), let image = sprite.cgImage else {
            return
        }
        let scale = sprite.scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let rebuildCells = self.configuration != configuration || abs(size.height - self.cellsHeight) > self.cellsHeight * 0.25
        self.configuration = configuration

        let speed = 0.35 + max(0.0, min(1.0, configuration.speed)) * 1.3
        let density = 0.2 + max(0.0, min(1.0, configuration.density)) * 1.6

        if rebuildCells {
            self.cellsHeight = size.height

            let cell = CAEmitterCell()
            cell.name = "particle"
            cell.contents = image
            cell.contentsScale = scale
            cell.birthRate = spec.birthRate * Float(density)
            cell.velocity = spec.velocity * speed
            cell.velocityRange = spec.velocityRange * speed
            cell.xAcceleration = spec.xAcceleration * speed
            cell.yAcceleration = spec.yAcceleration * speed
            cell.emissionLongitude = spec.emissionLongitude
            cell.emissionRange = spec.emissionRange
            cell.scale = spec.scale
            cell.scaleRange = spec.scaleRange
            cell.spin = spec.spin * speed
            cell.spinRange = spec.spinRange * speed
            cell.color = spec.color.withAlphaComponent(0.0).cgColor
            cell.alphaSpeed = spec.fadeInSpeed
            if spec.twinkles {
                cell.lifetime = spec.lifetime
                cell.lifetimeRange = spec.lifetimeRange
                cell.scaleSpeed = -(spec.scale - spec.scaleRange) / CGFloat(spec.lifetime + spec.lifetimeRange)
            } else {
                let slowest = max(4.0, (spec.velocity - spec.velocityRange) * speed)
                cell.lifetime = Float(min(60.0, size.height * 1.2 / slowest))
            }
            self.emitterLayer.renderMode = spec.additive ? .additive : .unordered
            self.emitterLayer.emitterCells = [cell]
            self.emitterLayer.opacity = spec.opacity

            let burst = CAEmitterCell()
            burst.name = "burst"
            burst.contents = image
            burst.contentsScale = scale
            burst.birthRate = 70.0
            burst.lifetime = 0.9
            burst.lifetimeRange = 0.3
            burst.velocity = 150.0 * max(speed, 0.7)
            burst.velocityRange = 70.0
            burst.emissionRange = .pi * 2.0
            burst.scale = spec.scale
            burst.scaleRange = spec.scaleRange * 0.5
            burst.scaleSpeed = -spec.scale * 0.4
            burst.spin = spec.spin
            burst.spinRange = max(spec.spinRange, 1.0)
            burst.color = spec.color.cgColor
            burst.alphaSpeed = -1.1
            self.burstLayer.renderMode = spec.additive ? .additive : .unordered
            self.burstLayer.emitterCells = [burst]
            self.burstLayer.opacity = spec.opacity
        }

        if self.validSize != size || rebuildCells {
            self.validSize = size
            let bounds = CGRect(origin: CGPoint(), size: size)
            self.emitterLayer.frame = bounds
            self.burstLayer.frame = bounds

            let emitterRect: CGRect
            if spec.direction > 0.0 {
                emitterRect = CGRect(x: -size.width * 0.1, y: -size.height * 0.15, width: size.width * 1.2, height: size.height * 1.15)
            } else if spec.direction < 0.0 {
                emitterRect = CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height * 1.15)
            } else {
                emitterRect = bounds
            }
            self.emitterLayer.emitterPosition = CGPoint(x: emitterRect.midX, y: emitterRect.midY)
            self.emitterLayer.emitterSize = emitterRect.size
            self.emitterLayer.birthRate = Float(max(0.3, (size.width * size.height) / AyuGramParticlesNode.referenceArea))
        }

        CATransaction.commit()
    }

    func setPaused(_ paused: Bool) {
        if self.isPaused == paused {
            return
        }
        self.isPaused = paused

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let layer = self.layer
        if paused {
            self.burstLayer.birthRate = 0.0
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0.0
            layer.timeOffset = pausedTime
        } else {
            let pausedTime = layer.timeOffset
            layer.speed = 1.0
            layer.timeOffset = 0.0
            layer.beginTime = 0.0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        }
        CATransaction.commit()
    }

    func burst(at point: CGPoint, strength: Float) {
        if self.isPaused || self.configuration == nil || !self.isNodeLoaded {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.burstLayer.emitterPosition = point
        self.burstLayer.birthRate = strength
        CATransaction.commit()

        self.burstGeneration += 1
        let generation = self.burstGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: { [weak self] in
            guard let strongSelf = self, strongSelf.burstGeneration == generation else {
                return
            }
            strongSelf.burstLayer.birthRate = 0.0
        })
    }
}
