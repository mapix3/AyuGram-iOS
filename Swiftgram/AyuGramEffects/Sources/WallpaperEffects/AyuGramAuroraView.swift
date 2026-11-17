import Foundation
import UIKit
import Display

final class AyuGramAuroraView: UIView {
    private struct SpotMotion {
        let path: [NSValue]
        let positionDuration: Double
        let scales: [NSNumber]
        let scaleDuration: Double
        let opacities: [NSNumber]
        let opacityDuration: Double
        let phase: Double
    }

    private static let canvasSide: CGFloat = 1000.0
    private static let epoch: Double = CACurrentMediaTime()
    private static let positionKey = "ayuAuroraPosition"
    private static let scaleKey = "ayuAuroraScale"
    private static let opacityKey = "ayuAuroraOpacity"

    private let canvas = SimpleLayer()
    private var spots: [SimpleLayer] = []
    private var motions: [SpotMotion] = []
    private var colors: [UInt32] = []

    var isAnimationAllowed: Bool = false {
        didSet {
            if self.isAnimationAllowed != oldValue {
                self.updateAnimations()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.backgroundColor = nil
        self.isOpaque = false
        self.canvas.bounds = CGRect(origin: CGPoint(), size: CGSize(width: AyuGramAuroraView.canvasSide, height: AyuGramAuroraView.canvasSide))
        self.layer.addSublayer(self.canvas)
        self.updateCanvasGeometry()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.updateCanvasGeometry()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateAnimations()
    }

    func update(colors: [UInt32]) {
        if self.colors == colors && !self.spots.isEmpty {
            return
        }
        self.colors = colors
        self.rebuildSpots()
    }

    private func updateCanvasGeometry() {
        let size = self.bounds.size
        let side = AyuGramAuroraView.canvasSide
        self.canvas.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        self.canvas.transform = CATransform3DMakeScale(max(size.width, 1.0) / side, max(size.height, 1.0) / side, 1.0)
    }

    private func rebuildSpots() {
        for spot in self.spots {
            spot.removeFromSuperlayer()
        }
        self.spots.removeAll()
        self.motions.removeAll()

        let colors = self.colors
        guard !colors.isEmpty else {
            return
        }

        var seed: UInt64 = 0xA0761D6478BD642F
        for color in colors {
            seed = (seed &* 31) &+ UInt64(color)
        }
        var random = AyuGramSplitMix64(seed: seed)

        let side = AyuGramAuroraView.canvasSide
        let count = min(9, max(6, colors.count * 2))
        for index in 0 ..< count {
            let color = AyuGramAuroraView.derivedColor(colors: colors, index: index, random: &random)
            guard let image = AyuGramAuroraView.spotImage(color: color) else {
                continue
            }

            let angle = CGFloat(index) / CGFloat(count) * CGFloat.pi * 2.0 + random.next(in: -0.4 ... 0.4)
            let radius = side * random.next(in: 0.12 ... 0.36)
            let anchor = CGPoint(x: side * 0.5 + cos(angle) * radius, y: side * 0.5 + sin(angle) * radius)

            var points: [CGPoint] = []
            for _ in 0 ..< 5 {
                points.append(CGPoint(x: anchor.x + side * random.next(in: -0.3 ... 0.3), y: anchor.y + side * random.next(in: -0.3 ... 0.3)))
            }
            points.append(points[0])

            var scales: [NSNumber] = []
            for _ in 0 ..< 4 {
                scales.append(NSNumber(value: Double(random.next(in: 0.8 ... 1.25))))
            }
            scales.append(scales[0])

            var opacities: [NSNumber] = []
            for _ in 0 ..< 4 {
                opacities.append(NSNumber(value: Float(random.next(in: 0.4 ... 0.8))))
            }
            opacities.append(opacities[0])

            let motion = SpotMotion(
                path: points.map { NSValue(cgPoint: $0) },
                positionDuration: 46.0 + Double(index) * 6.3 + Double(random.next(in: 0.0 ... 9.0)),
                scales: scales,
                scaleDuration: 31.0 + Double(index) * 4.1 + Double(random.next(in: 0.0 ... 7.0)),
                opacities: opacities,
                opacityDuration: 23.0 + Double(index) * 5.7 + Double(random.next(in: 0.0 ... 5.0)),
                phase: Double(random.next(in: 0.0 ... 600.0))
            )

            let diameter = side * random.next(in: 0.65 ... 1.0)
            let spot = SimpleLayer()
            spot.contents = image.cgImage
            spot.bounds = CGRect(origin: CGPoint(), size: CGSize(width: diameter, height: diameter))
            spot.position = points[0]
            spot.opacity = opacities[0].floatValue
            self.canvas.addSublayer(spot)

            self.spots.append(spot)
            self.motions.append(motion)
        }

        self.updateAnimations()
    }

    private func updateAnimations() {
        if self.isAnimationAllowed && self.window != nil {
            let time = CACurrentMediaTime() - AyuGramAuroraView.epoch
            for (index, spot) in self.spots.enumerated() where spot.animation(forKey: AyuGramAuroraView.positionKey) == nil {
                let motion = self.motions[index]

                let position = CAKeyframeAnimation(keyPath: "position")
                position.values = motion.path
                position.calculationMode = .cubic
                AyuGramAuroraView.configure(position, duration: motion.positionDuration, time: time + motion.phase)
                spot.add(position, forKey: AyuGramAuroraView.positionKey)

                let scale = CAKeyframeAnimation(keyPath: "transform.scale")
                scale.values = motion.scales
                scale.calculationMode = .cubic
                AyuGramAuroraView.configure(scale, duration: motion.scaleDuration, time: time + motion.phase)
                spot.add(scale, forKey: AyuGramAuroraView.scaleKey)

                let opacity = CAKeyframeAnimation(keyPath: "opacity")
                opacity.values = motion.opacities
                opacity.calculationMode = .cubic
                AyuGramAuroraView.configure(opacity, duration: motion.opacityDuration, time: time + motion.phase)
                spot.add(opacity, forKey: AyuGramAuroraView.opacityKey)
            }
        } else {
            for spot in self.spots {
                spot.removeAllAnimations()
            }
        }
    }

    private static func configure(_ animation: CAKeyframeAnimation, duration: Double, time: Double) {
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.timeOffset = time.truncatingRemainder(dividingBy: duration)
        if #available(iOS 15.0, *) {
            animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10.0, maximum: 30.0, preferred: 30.0)
        }
    }

    private static func derivedColor(colors: [UInt32], index: Int, random: inout AyuGramSplitMix64) -> UIColor {
        let first = UIColor(rgb: colors[index % colors.count])
        let second = UIColor(rgb: colors[(index + 1) % colors.count])
        let fraction = random.next(in: 0.15 ... 0.5)

        var r1: CGFloat = 0.0, g1: CGFloat = 0.0, b1: CGFloat = 0.0, a1: CGFloat = 0.0
        var r2: CGFloat = 0.0, g2: CGFloat = 0.0, b2: CGFloat = 0.0, a2: CGFloat = 0.0
        first.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        second.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let mixed = UIColor(red: r1 + (r2 - r1) * fraction, green: g1 + (g2 - g1) * fraction, blue: b1 + (b2 - b1) * fraction, alpha: 1.0)

        var hue: CGFloat = 0.0, saturation: CGFloat = 0.0, brightness: CGFloat = 0.0, alpha: CGFloat = 0.0
        mixed.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        hue += random.next(in: -0.06 ... 0.06)
        hue -= floor(hue)
        return UIColor(hue: hue, saturation: min(1.0, saturation * 1.2 + 0.05), brightness: min(1.0, brightness * 1.05 + 0.02), alpha: 1.0)
    }

    private static func spotImage(color: UIColor) -> UIImage? {
        let side: CGFloat = 128.0
        return generateImage(CGSize(width: side, height: side), contextGenerator: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradientColors = [
                color.withAlphaComponent(0.9).cgColor,
                color.withAlphaComponent(0.55).cgColor,
                color.withAlphaComponent(0.2).cgColor,
                color.withAlphaComponent(0.0).cgColor
            ] as CFArray
            var locations: [CGFloat] = [0.0, 0.32, 0.64, 1.0]
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: &locations) else {
                return
            }
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: size.width * 0.5, options: [])
        }, opaque: false, scale: 1.0)
    }
}
