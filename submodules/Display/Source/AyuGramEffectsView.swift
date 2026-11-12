import Foundation
import UIKit
import SGSimpleSettings

public final class AyuGramEffectsView: UIView {
    private let scope: AyuGramAppearanceScope
    private let emitter = CAEmitterLayer()
    private let driftLayer = CAShapeLayer()
    private var observers: [NSObjectProtocol] = []
    private var inBackground = false
    private var activeBursts = 0
    private var appliedParticles: (kind: Int32, amount: Float, size: CGSize)?
    private var appliedDrift: CGRect?

    public var driftFrame: CGRect? {
        didSet {
            if oldValue != self.driftFrame {
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
        self.driftLayer.fillColor = UIColor(white: 1.0, alpha: 0.96).cgColor
        self.driftLayer.shadowColor = UIColor.black.cgColor
        self.driftLayer.shadowOpacity = 0.18
        self.driftLayer.shadowRadius = 2.0
        self.driftLayer.shadowOffset = CGSize(width: 0.0, height: 1.0)
        self.driftLayer.isHidden = true
        self.layer.addSublayer(self.driftLayer)

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

    private var isPaused: Bool {
        return self.inBackground || UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public func reload() {
        let state = AyuGramAppearance.shared.effects
        let size = self.bounds.size
        let hasSize = size.width > 0.0 && size.height > 0.0
        let showParticles = state.particles && (self.scope == .chatList || state.inChats) && !self.isPaused && hasSize
        var drift: CGRect?
        if state.drift, self.scope == .conversation, hasSize, let driftFrame = self.driftFrame, driftFrame.width > 60.0 {
            drift = driftFrame
        }
        self.isHidden = !(showParticles || drift != nil || self.activeBursts > 0)

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

        if let drift {
            if self.appliedDrift != drift {
                self.appliedDrift = drift
                self.configureDrift(frame: drift)
            }
            self.driftLayer.isHidden = false
        } else {
            self.appliedDrift = nil
            self.driftLayer.isHidden = true
        }
    }

    public func celebrateIfNeeded(text: String) {
        let state = AyuGramAppearance.shared.effects
        guard state.fireworks, !self.isPaused, self.bounds.width > 0.0, self.bounds.height > 0.0 else {
            return
        }
        let lowered = text.lowercased()
        let triggers = ["🎄", "🎆", "🎇", "🎉", "🥳", "с новым годом", "з новим роком", "happy new year"]
        guard triggers.contains(where: { lowered.contains($0) }) else {
            return
        }
        for index in 0 ..< 4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.26, execute: { [weak self] in
                self?.addBurst()
            })
        }
    }

    private func addBurst() {
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0, !self.isPaused else {
            return
        }
        let palette: [UIColor] = [
            UIColor(red: 1.0, green: 0.35, blue: 0.31, alpha: 1.0),
            UIColor(red: 1.0, green: 0.82, blue: 0.29, alpha: 1.0),
            UIColor(red: 0.37, green: 0.86, blue: 0.52, alpha: 1.0),
            UIColor(red: 0.35, green: 0.68, blue: 1.0, alpha: 1.0),
            UIColor(red: 0.82, green: 0.52, blue: 1.0, alpha: 1.0)
        ]
        let burst = CAEmitterLayer()
        burst.frame = CGRect(origin: CGPoint(), size: size)
        burst.emitterShape = .point
        burst.renderMode = .additive
        burst.emitterPosition = CGPoint(x: CGFloat.random(in: size.width * 0.15 ... size.width * 0.85), y: CGFloat.random(in: size.height * 0.15 ... size.height * 0.5))
        let cell = CAEmitterCell()
        cell.contents = AyuGramEffectsView.particleImage(kind: 0).cgImage
        cell.color = (palette.randomElement() ?? UIColor.white).cgColor
        cell.birthRate = 520.0
        cell.lifetime = 1.3
        cell.lifetimeRange = 0.4
        cell.velocity = 190.0
        cell.velocityRange = 90.0
        cell.emissionRange = CGFloat.pi * 2.0
        cell.yAcceleration = 170.0
        cell.scale = 0.5
        cell.scaleRange = 0.25
        cell.scaleSpeed = -0.2
        cell.alphaSpeed = -0.75
        burst.emitterCells = [cell]
        burst.beginTime = CACurrentMediaTime()
        self.layer.addSublayer(burst)
        self.activeBursts += 1
        self.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: {
            burst.birthRate = 0.0
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: { [weak self] in
            burst.removeFromSuperlayer()
            guard let self else {
                return
            }
            self.activeBursts = max(0, self.activeBursts - 1)
            self.reload()
        })
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
            case 4:
                context.setFillColor(UIColor.white.cgColor)
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: -CGFloat.pi / 4.0)
                let length = side * 0.42
                let width = side * 0.2
                context.move(to: CGPoint(x: -length, y: 0.0))
                context.addQuadCurve(to: CGPoint(x: length, y: 0.0), control: CGPoint(x: 0.0, y: -width * 2.0))
                context.addQuadCurve(to: CGPoint(x: -length, y: 0.0), control: CGPoint(x: 0.0, y: width * 2.0))
                context.closePath()
                context.fillPath()
            case 5:
                context.setFillColor(UIColor(red: 0.72, green: 0.84, blue: 1.0, alpha: 0.9).cgColor)
                context.fill(CGRect(x: center.x - 0.75, y: 3.0, width: 1.5, height: side - 6.0))
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
        cell.yAcceleration = 4.0
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
        case 4:
            velocity = 50.0
            cell.scale = 0.5
            cell.scaleRange = 0.2
            cell.spin = 0.9
            cell.spinRange = 2.4
            cell.xAcceleration = 9.0
            cell.color = UIColor(red: 0.93, green: 0.5, blue: 0.14, alpha: 1.0).cgColor
            cell.redRange = 0.07
            cell.greenRange = 0.25
            cell.birthRate = 7.0 * amount
        case 5:
            velocity = 430.0
            cell.scale = 0.8
            cell.scaleRange = 0.2
            cell.emissionRange = CGFloat.pi / 60.0
            cell.yAcceleration = 0.0
            cell.birthRate = 46.0 * amount
        default:
            cell.scale = 0.35
            cell.scaleRange = 0.25
            cell.xAcceleration = 3.0
            cell.birthRate = 18.0 * amount
        }
        cell.velocity = velocity
        cell.velocityRange = velocity * (kind == 5 ? 0.15 : 0.4)
        cell.lifetime = Float((size.height + 80.0) / (velocity * 0.75))
        self.emitter.emitterCells = [cell]
        self.emitter.beginTime = CACurrentMediaTime()
    }

    private func configureDrift(frame: CGRect) {
        let inset: CGFloat = 14.0
        let width = max(0.0, frame.width - inset * 2.0)
        let height: CGFloat = 13.0
        let bumps: [CGFloat] = [0.55, 1.0, 0.7, 0.9, 0.5, 0.8, 1.0, 0.6, 0.85, 0.65]
        let bumpWidth: CGFloat = 34.0
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0.0, y: height))
        var x: CGFloat = 0.0
        var index = 0
        while x < width {
            let next = min(width, x + bumpWidth)
            let peak = height - height * bumps[index % bumps.count]
            path.addQuadCurve(to: CGPoint(x: next, y: height - 2.0), controlPoint: CGPoint(x: (x + next) / 2.0, y: peak - (height - peak) * 0.6))
            x = next
            index += 1
        }
        path.addLine(to: CGPoint(x: width, y: height))
        path.close()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.driftLayer.frame = CGRect(x: frame.minX + inset, y: frame.minY - height + 4.0, width: width, height: height)
        self.driftLayer.path = path.cgPath
        CATransaction.commit()
    }
}
