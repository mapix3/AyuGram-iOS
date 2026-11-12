import Foundation
import UIKit
import SGSimpleSettings

public final class AyuGramEffectsView: UIView {
    private let scope: AyuGramAppearanceScope
    private let emitter = CAEmitterLayer()
    private let garlandLayer = CALayer()
    private let wireLayer = CAShapeLayer()
    private var bulbLayers: [CALayer] = []
    private var observers: [NSObjectProtocol] = []
    private var inBackground = false
    private var appliedParticles: (kind: Int32, amount: Float, size: CGSize)?
    private var appliedGarland: (width: CGFloat, top: CGFloat)?

    public var garlandTop: CGFloat = 0.0 {
        didSet {
            if oldValue != self.garlandTop {
                self.reload()
            }
        }
    }

    public init(scope: AyuGramAppearanceScope) {
        self.scope = scope

        super.init(frame: .zero)

        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        self.backgroundColor = nil
        self.isOpaque = false
        self.emitter.emitterShape = .line
        self.emitter.renderMode = .unordered
        self.layer.addSublayer(self.emitter)
        self.wireLayer.fillColor = nil
        self.wireLayer.lineWidth = 1.5
        self.wireLayer.strokeColor = UIColor(white: 0.25, alpha: 1.0).cgColor
        self.garlandLayer.addSublayer(self.wireLayer)
        self.layer.addSublayer(self.garlandLayer)

        let center = NotificationCenter.default
        for name in [AyuGramAppearance.didChange, Notification.Name.NSProcessInfoPowerStateDidChange, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            self.observers.append(center.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                self?.reload()
            }))
        }
        self.observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.inBackground = true
            self.reload()
        }))
        self.observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.inBackground = false
            self.appliedParticles = nil
            self.appliedGarland = nil
            self.reload()
        }))
        self.reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        self.reload()
    }

    public func reload() {
        let state = AyuGramAppearance.shared.effects
        let size = self.bounds.size
        let paused = self.inBackground || UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
        let showParticles = state.particles && (self.scope == .chatList || state.inChats) && !paused && size.width > 0.0 && size.height > 0.0
        let showGarland = state.garland && self.scope == .chatList && size.width > 0.0
        self.isHidden = !(showParticles || showGarland)

        if showParticles {
            if let applied = self.appliedParticles, applied.kind == state.kind, applied.amount == state.amount, applied.size == size {
            } else {
                self.appliedParticles = (state.kind, state.amount, size)
                self.configureEmitter(kind: state.kind, amount: state.amount, size: size)
            }
        } else if self.appliedParticles != nil || self.emitter.emitterCells != nil {
            self.appliedParticles = nil
            self.emitter.emitterCells = nil
        }

        if showGarland {
            if let applied = self.appliedGarland, applied.width == size.width, applied.top == self.garlandTop {
            } else {
                self.appliedGarland = (size.width, self.garlandTop)
                self.configureGarland(width: size.width, top: self.garlandTop, animated: !paused)
            }
            self.garlandLayer.isHidden = false
        } else {
            self.garlandLayer.isHidden = true
            if self.appliedGarland != nil {
                self.appliedGarland = nil
                for bulb in self.bulbLayers {
                    bulb.removeFromSuperlayer()
                }
                self.bulbLayers = []
                self.wireLayer.path = nil
            }
        }
    }

    private static func particleImage(kind: Int32) -> UIImage {
        let side: CGFloat = kind == 0 ? 16.0 : 28.0
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image(actions: { rendererContext in
            let context = rendererContext.cgContext
            let center = CGPoint(x: side / 2.0, y: side / 2.0)
            switch kind {
            case 1:
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(1.6)
                context.setLineCap(.round)
                let radius = side / 2.0 - 2.0
                for index in 0 ..< 6 {
                    let angle = CGFloat(index) * CGFloat.pi / 3.0
                    let tip = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    context.move(to: center)
                    context.addLine(to: tip)
                    let branchBase = CGPoint(x: center.x + cos(angle) * radius * 0.6, y: center.y + sin(angle) * radius * 0.6)
                    for offset in [CGFloat.pi / 4.0, -CGFloat.pi / 4.0] {
                        context.move(to: branchBase)
                        context.addLine(to: CGPoint(x: branchBase.x + cos(angle + offset) * radius * 0.32, y: branchBase.y + sin(angle + offset) * radius * 0.32))
                    }
                }
                context.strokePath()
            case 2:
                context.setFillColor(UIColor(red: 1.0, green: 0.72, blue: 0.82, alpha: 1.0).cgColor)
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: CGFloat.pi / 5.0)
                context.fillEllipse(in: CGRect(x: -side * 0.38, y: -side * 0.2, width: side * 0.76, height: side * 0.4))
            case 3:
                context.setFillColor(UIColor(red: 1.0, green: 0.9, blue: 0.54, alpha: 1.0).cgColor)
                let outer = side / 2.0 - 2.0
                let inner = outer * 0.3
                for index in 0 ..< 8 {
                    let angle = CGFloat(index) * CGFloat.pi / 4.0 - CGFloat.pi / 2.0
                    let radius = index % 2 == 0 ? outer : inner
                    let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    if index == 0 {
                        context.move(to: point)
                    } else {
                        context.addLine(to: point)
                    }
                }
                context.closePath()
                context.fillPath()
            default:
                let colors = [UIColor(white: 1.0, alpha: 1.0).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.35, 1.0]) {
                    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: side / 2.0, options: [])
                }
            }
        })
    }

    private func configureEmitter(kind: Int32, amount: Float, size: CGSize) {
        self.emitter.frame = CGRect(origin: CGPoint(), size: size)
        self.emitter.emitterPosition = CGPoint(x: size.width / 2.0, y: -16.0)
        self.emitter.emitterSize = CGSize(width: size.width + 40.0, height: 1.0)

        let cell = CAEmitterCell()
        cell.contents = AyuGramEffectsView.particleImage(kind: kind).cgImage
        cell.emissionLongitude = CGFloat.pi / 2.0
        cell.emissionRange = CGFloat.pi / 10.0
        cell.alphaRange = 0.35
        var velocity: CGFloat = 60.0
        switch kind {
        case 1:
            velocity = 45.0
            cell.scale = 0.45
            cell.scaleRange = 0.25
            cell.spin = 0.4
            cell.spinRange = 1.2
            cell.birthRate = 9.0 * amount
        case 2:
            velocity = 55.0
            cell.scale = 0.5
            cell.scaleRange = 0.2
            cell.spin = 0.8
            cell.spinRange = 2.0
            cell.xAcceleration = 6.0
            cell.birthRate = 8.0 * amount
        case 3:
            velocity = 28.0
            cell.scale = 0.3
            cell.scaleRange = 0.2
            cell.alphaSpeed = -0.04
            cell.spinRange = 0.6
            cell.birthRate = 6.0 * amount
        default:
            cell.scale = 0.35
            cell.scaleRange = 0.25
            cell.xAcceleration = 3.0
            cell.birthRate = 18.0 * amount
        }
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.4
        cell.yAcceleration = 4.0
        cell.lifetime = Float((size.height + 80.0) / (velocity * 0.75))
        self.emitter.emitterCells = [cell]
        self.emitter.beginTime = CACurrentMediaTime()
    }

    private func configureGarland(width: CGFloat, top: CGFloat, animated: Bool) {
        for bulb in self.bulbLayers {
            bulb.removeFromSuperlayer()
        }
        self.bulbLayers = []
        self.garlandLayer.frame = CGRect(x: 0.0, y: top, width: width, height: 40.0)
        self.wireLayer.frame = self.garlandLayer.bounds

        let segmentCount = max(3, Int((width / 78.0).rounded()))
        let segmentWidth = width / CGFloat(segmentCount)
        let sag: CGFloat = 13.0
        let anchorY: CGFloat = 3.0
        let palette: [UIColor] = [
            UIColor(red: 1.0, green: 0.35, blue: 0.31, alpha: 1.0),
            UIColor(red: 1.0, green: 0.82, blue: 0.29, alpha: 1.0),
            UIColor(red: 0.37, green: 0.76, blue: 0.48, alpha: 1.0),
            UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1.0),
            UIColor(red: 0.78, green: 0.49, blue: 1.0, alpha: 1.0)
        ]
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0.0, y: anchorY))
        var bulbIndex = 0
        for segment in 0 ..< segmentCount {
            let start = CGPoint(x: CGFloat(segment) * segmentWidth, y: anchorY)
            let end = CGPoint(x: CGFloat(segment + 1) * segmentWidth, y: anchorY)
            let control = CGPoint(x: (start.x + end.x) / 2.0, y: anchorY + sag * 2.0)
            path.addQuadCurve(to: end, controlPoint: control)
            for fraction in [CGFloat(0.25), CGFloat(0.5), CGFloat(0.75)] {
                let inverse = 1.0 - fraction
                let point = CGPoint(
                    x: inverse * inverse * start.x + 2.0 * inverse * fraction * control.x + fraction * fraction * end.x,
                    y: inverse * inverse * start.y + 2.0 * inverse * fraction * control.y + fraction * fraction * end.y
                )
                let color = palette[bulbIndex % palette.count]
                let bulb = CALayer()
                bulb.frame = CGRect(x: point.x - 3.5, y: point.y + 1.0, width: 7.0, height: 9.0)
                bulb.cornerRadius = 3.5
                bulb.backgroundColor = color.cgColor
                bulb.shadowColor = color.cgColor
                bulb.shadowOpacity = 0.9
                bulb.shadowRadius = 5.0
                bulb.shadowOffset = CGSize()
                if animated {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.fromValue = 1.0
                    animation.toValue = 0.3
                    animation.duration = 0.9
                    animation.autoreverses = true
                    animation.repeatCount = Float.infinity
                    animation.beginTime = CACurrentMediaTime() + Double(bulbIndex % 3) * 0.45
                    animation.isRemovedOnCompletion = false
                    bulb.add(animation, forKey: "blink")
                }
                self.garlandLayer.addSublayer(bulb)
                self.bulbLayers.append(bulb)
                bulbIndex += 1
            }
        }
        self.wireLayer.path = path.cgPath
    }
}
