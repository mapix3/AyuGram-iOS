import Foundation
import UIKit
import SGSimpleSettings

private final class AyuGramDisplayLinkTarget: NSObject {
    weak var view: AyuGramEffectsView?

    init(view: AyuGramEffectsView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        self.view?.step(link)
    }
}

private struct AyuGramFlake {
    var x: CGFloat
    var y: CGFloat
    var speed: CGFloat
    var size: CGFloat
    var swayAmplitude: CGFloat
    var swayFrequency: CGFloat
    var phase: CGFloat
    var rotation: CGFloat
    var spin: CGFloat
    var alpha: Float
    var twinkle: CGFloat
    var lastSway: CGFloat
}

private final class AyuGramSnowPile {
    var heights: [CGFloat]
    var width: CGFloat
    let container = CALayer()
    let shape = CAShapeLayer()
    let gradient = CAGradientLayer()
    let mask = CAShapeLayer()
    let highlight = CAShapeLayer()

    init(width: CGFloat) {
        self.width = width
        self.heights = []
        self.container.shadowColor = UIColor(red: 0.1, green: 0.14, blue: 0.25, alpha: 1.0).cgColor
        self.container.shadowOpacity = 0.28
        self.container.shadowRadius = 2.5
        self.container.shadowOffset = CGSize(width: 0.0, height: 1.0)
        self.shape.fillColor = UIColor(white: 1.0, alpha: 1.0).cgColor
        self.gradient.colors = [
            UIColor(white: 1.0, alpha: 1.0).cgColor,
            UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1.0).cgColor,
            UIColor(red: 0.8, green: 0.86, blue: 0.96, alpha: 1.0).cgColor
        ]
        self.gradient.locations = [0.0, 0.55, 1.0]
        self.gradient.mask = self.mask
        self.highlight.fillColor = nil
        self.highlight.strokeColor = UIColor(white: 1.0, alpha: 0.9).cgColor
        self.highlight.lineWidth = 1.0
        self.highlight.lineCap = .round
        self.container.addSublayer(self.shape)
        self.container.addSublayer(self.gradient)
        self.container.addSublayer(self.highlight)
    }
}

public final class AyuGramEffectsView: UIView {
    private static let columnWidth: CGFloat = 2.0
    private static var keptPiles: [[CGFloat]] = []

    private let scope: AyuGramAppearanceScope
    private var observers: [NSObjectProtocol] = []
    private var displayLink: CADisplayLink?
    private var inBackground = false
    private var activeBursts = 0
    private var flakes: [AyuGramFlake] = []
    private var flakeLayers: [CALayer] = []
    private var currentKind: Int32 = -1
    private var currentCount = 0
    private var flakeImage: CGImage?
    private var piles: [AyuGramSnowPile] = []
    private var lastTimestamp: CFTimeInterval = 0.0
    private var time: CGFloat = 0.0
    private var showsParticles = false
    private var showsPiles = false
    private var lastSize = CGSize()

    public var surfaceProvider: (() -> [CGRect])?

    public init(scope: AyuGramAppearanceScope) {
        self.scope = scope

        super.init(frame: .zero)

        self.isUserInteractionEnabled = false
        self.clipsToBounds = true
        self.backgroundColor = nil
        self.isOpaque = false

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
            self.reload()
        }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.displayLink?.invalidate()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()

        self.reload()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if self.bounds.size != self.lastSize {
            let previous = self.lastSize
            self.lastSize = self.bounds.size
            if previous.width > 0.0, previous.height > 0.0, !self.flakes.isEmpty {
                for index in self.flakes.indices {
                    self.flakes[index].x = self.flakes[index].x / previous.width * self.bounds.width
                    self.flakes[index].y = self.flakes[index].y / previous.height * self.bounds.height
                }
            }
            self.reload()
        }
    }

    private var isPaused: Bool {
        return self.inBackground || UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public func reload() {
        let state = AyuGramAppearance.shared.effects
        let size = self.bounds.size
        let hasSize = size.width > 0.0 && size.height > 0.0
        let active = hasSize && self.window != nil && !self.isPaused
        self.showsParticles = active && state.particles && (self.scope == .chatList || state.inChats)
        self.showsPiles = active && state.drift && self.scope == .conversation

        if self.showsParticles {
            let count = AyuGramEffectsView.flakeCount(kind: state.kind, amount: state.amount)
            if state.kind != self.currentKind || count != self.currentCount {
                self.rebuildFlakes(kind: state.kind, count: count, size: size)
            }
        } else if !self.flakes.isEmpty {
            self.removeFlakes()
        }

        if !self.showsPiles && !self.piles.isEmpty {
            self.storePiles()
            for pile in self.piles {
                pile.container.removeFromSuperlayer()
            }
            self.piles = []
        }

        let running = self.showsParticles || self.showsPiles
        self.isHidden = !(running || self.activeBursts > 0)
        if running {
            if self.displayLink == nil {
                let link = CADisplayLink(target: AyuGramDisplayLinkTarget(view: self), selector: #selector(AyuGramDisplayLinkTarget.tick(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 60.0, preferred: 60.0)
                link.add(to: .main, forMode: .common)
                self.displayLink = link
                self.lastTimestamp = 0.0
            }
        } else if let link = self.displayLink {
            link.invalidate()
            self.displayLink = nil
        }
    }

    private static func flakeCount(kind: Int32, amount: Float) -> Int {
        let maximum: Float
        switch kind {
        case 1:
            maximum = 40.0
        case 2:
            maximum = 34.0
        case 3:
            maximum = 46.0
        case 4:
            maximum = 26.0
        case 5:
            maximum = 110.0
        default:
            maximum = 120.0
        }
        return max(6, Int((maximum * amount).rounded()))
    }

    private func removeFlakes() {
        for layer in self.flakeLayers {
            layer.removeFromSuperlayer()
        }
        self.flakeLayers = []
        self.flakes = []
        self.currentKind = -1
        self.currentCount = 0
    }

    private func rebuildFlakes(kind: Int32, count: Int, size: CGSize) {
        self.removeFlakes()
        self.currentKind = kind
        self.currentCount = count
        let image = AyuGramEffectsView.particleImage(kind: kind)
        self.flakeImage = image.cgImage
        let scale = image.scale
        for _ in 0 ..< count {
            var flake = self.makeFlake(kind: kind, width: size.width)
            flake.y = CGFloat.random(in: -20.0 ... max(0.0, size.height))
            self.flakes.append(flake)
            let layer = CALayer()
            layer.contents = self.flakeImage
            layer.contentsScale = scale
            layer.contentsGravity = .resizeAspect
            layer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: flake.size, height: kind == 5 ? 18.0 : flake.size))
            layer.opacity = flake.alpha
            layer.position = CGPoint(x: flake.x, y: flake.y)
            self.layer.addSublayer(layer)
            self.flakeLayers.append(layer)
        }
        for pile in self.piles {
            self.layer.addSublayer(pile.container)
        }
    }

    private func makeFlake(kind: Int32, width: CGFloat) -> AyuGramFlake {
        let x = CGFloat.random(in: -20.0 ... width + 20.0)
        switch kind {
        case 1:
            let size = CGFloat.random(in: 6.0 ... 11.0)
            return AyuGramFlake(x: x, y: -size, speed: CGFloat.random(in: 22.0 ... 40.0), size: size, swayAmplitude: CGFloat.random(in: 8.0 ... 20.0), swayFrequency: CGFloat.random(in: 0.25 ... 0.6), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: CGFloat.random(in: 0.0 ... 6.28), spin: CGFloat.random(in: -0.8 ... 0.8), alpha: Float.random(in: 0.6 ... 0.95), twinkle: 0.0, lastSway: 0.0)
        case 2:
            let size = CGFloat.random(in: 7.0 ... 11.0)
            return AyuGramFlake(x: x, y: -size, speed: CGFloat.random(in: 30.0 ... 52.0), size: size, swayAmplitude: CGFloat.random(in: 16.0 ... 34.0), swayFrequency: CGFloat.random(in: 0.3 ... 0.7), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: CGFloat.random(in: 0.0 ... 6.28), spin: CGFloat.random(in: -2.2 ... 2.2), alpha: Float.random(in: 0.7 ... 0.95), twinkle: 0.0, lastSway: 0.0)
        case 3:
            let size = CGFloat.random(in: 3.0 ... 6.0)
            return AyuGramFlake(x: x, y: -size, speed: CGFloat.random(in: 8.0 ... 18.0), size: size, swayAmplitude: CGFloat.random(in: 2.0 ... 6.0), swayFrequency: CGFloat.random(in: 0.1 ... 0.3), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: 0.0, spin: 0.0, alpha: Float.random(in: 0.6 ... 1.0), twinkle: CGFloat.random(in: 1.5 ... 4.0), lastSway: 0.0)
        case 4:
            let size = CGFloat.random(in: 9.0 ... 14.0)
            return AyuGramFlake(x: x, y: -size, speed: CGFloat.random(in: 34.0 ... 58.0), size: size, swayAmplitude: CGFloat.random(in: 20.0 ... 44.0), swayFrequency: CGFloat.random(in: 0.25 ... 0.55), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: CGFloat.random(in: 0.0 ... 6.28), spin: CGFloat.random(in: -2.6 ... 2.6), alpha: Float.random(in: 0.8 ... 1.0), twinkle: 0.0, lastSway: 0.0)
        case 5:
            let size: CGFloat = 1.2
            return AyuGramFlake(x: x, y: -20.0, speed: CGFloat.random(in: 520.0 ... 720.0), size: size, swayAmplitude: 0.0, swayFrequency: 0.0, phase: 0.0, rotation: 0.0, spin: 0.0, alpha: Float.random(in: 0.25 ... 0.5), twinkle: 0.0, lastSway: 0.0)
        default:
            let size = CGFloat.random(in: 2.0 ... 5.5)
            return AyuGramFlake(x: x, y: -size, speed: 14.0 + size * 6.0 + CGFloat.random(in: 0.0 ... 8.0), size: size, swayAmplitude: CGFloat.random(in: 5.0 ... 16.0), swayFrequency: CGFloat.random(in: 0.2 ... 0.55), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: 0.0, spin: 0.0, alpha: Float(0.45 + size / 5.5 * 0.5), twinkle: 0.0, lastSway: 0.0)
        }
    }

    fileprivate func step(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        var delta = self.lastTimestamp == 0.0 ? 1.0 / 60.0 : timestamp - self.lastTimestamp
        self.lastTimestamp = timestamp
        delta = min(delta, 0.1)
        let dt = CGFloat(delta)
        self.time += dt
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }

        var surfaces: [CGRect] = []
        if self.showsPiles {
            surfaces = (self.surfaceProvider?() ?? []).filter { $0.maxY > 0.0 && $0.minY < size.height }
            self.syncPiles(surfaces: surfaces)
        }
        let accumulates = self.showsPiles && (self.currentKind == 0 || self.currentKind == 1)
        let wind = sin(self.time * 0.13) * 7.0 + sin(self.time * 0.41) * 3.0
        let kind = self.currentKind

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in self.flakes.indices {
            var flake = self.flakes[index]
            let sway = flake.swayAmplitude * sin(self.time * flake.swayFrequency * 2.0 * .pi + flake.phase)
            let previousY = flake.y
            flake.y += flake.speed * dt
            if kind == 5 {
                flake.x += flake.speed * 0.12 * dt
            } else {
                flake.x += wind * dt * (flake.size / 6.0 + 0.4) + (sway - flake.lastSway)
            }
            flake.lastSway = sway
            flake.rotation += flake.spin * dt

            var landed = false
            if accumulates {
                for (surfaceIndex, surface) in surfaces.enumerated() where flake.x > surface.minX && flake.x < surface.maxX {
                    let top = self.pileTop(index: surfaceIndex, surface: surface, x: flake.x)
                    if previousY <= top && flake.y >= top {
                        self.deposit(index: surfaceIndex, surface: surface, x: flake.x, amount: kind == 1 ? flake.size * 0.5 : flake.size * 0.4)
                        landed = true
                        break
                    }
                }
            }

            if landed || flake.y > size.height + 30.0 || flake.x < -60.0 || flake.x > size.width + 60.0 {
                var next = self.makeFlake(kind: kind, width: size.width)
                if flake.x < -60.0 || flake.x > size.width + 60.0 {
                    next.y = CGFloat.random(in: -20.0 ... size.height * 0.6)
                    next.x = flake.x < 0.0 ? size.width + 10.0 : -10.0
                }
                flake = next
            }
            self.flakes[index] = flake

            let layer = self.flakeLayers[index]
            layer.position = CGPoint(x: flake.x, y: flake.y)
            if flake.spin != 0.0 {
                layer.setAffineTransform(CGAffineTransform(rotationAngle: flake.rotation))
            } else if kind == 5 {
                layer.setAffineTransform(CGAffineTransform(rotationAngle: -0.12))
            }
            if flake.twinkle > 0.0 {
                layer.opacity = flake.alpha * Float(0.55 + 0.45 * sin(self.time * flake.twinkle + flake.phase))
            }
        }
        if self.showsPiles {
            self.settlePiles(dt: dt)
            self.renderPiles(surfaces: surfaces)
        }
        CATransaction.commit()
    }

    private func syncPiles(surfaces: [CGRect]) {
        while self.piles.count < surfaces.count {
            let width = surfaces[self.piles.count].width
            let pile = AyuGramSnowPile(width: width)
            let columns = max(2, Int(width / AyuGramEffectsView.columnWidth) + 1)
            let index = self.piles.count
            if index < AyuGramEffectsView.keptPiles.count {
                pile.heights = AyuGramEffectsView.resample(AyuGramEffectsView.keptPiles[index], to: columns)
            } else {
                pile.heights = (0 ..< columns).map { column in
                    let limit = AyuGramEffectsView.limit(column: column, columns: columns, surface: surfaces[index])
                    return limit * CGFloat.random(in: 0.35 ... 0.55)
                }
            }
            self.layer.addSublayer(pile.container)
            self.piles.append(pile)
        }
        while self.piles.count > surfaces.count {
            let pile = self.piles.removeLast()
            pile.container.removeFromSuperlayer()
        }
        for (index, surface) in surfaces.enumerated() {
            let pile = self.piles[index]
            let columns = max(2, Int(surface.width / AyuGramEffectsView.columnWidth) + 1)
            if pile.heights.count != columns {
                pile.heights = AyuGramEffectsView.resample(pile.heights, to: columns)
            }
            pile.width = surface.width
        }
    }

    private func storePiles() {
        AyuGramEffectsView.keptPiles = self.piles.map { $0.heights }
    }

    private static func resample(_ values: [CGFloat], to count: Int) -> [CGFloat] {
        guard values.count > 1, count > 1 else {
            return Array(repeating: values.first ?? 0.0, count: max(count, 0))
        }
        return (0 ..< count).map { index in
            let position = CGFloat(index) / CGFloat(count - 1) * CGFloat(values.count - 1)
            let lower = Int(position)
            let upper = min(values.count - 1, lower + 1)
            let fraction = position - CGFloat(lower)
            return values[lower] * (1.0 - fraction) + values[upper] * fraction
        }
    }

    private static func baseOffset(x: CGFloat, surface: CGRect) -> CGFloat {
        let radius = min(surface.height, surface.width) / 2.0
        let local = x - surface.minX
        let distance: CGFloat
        if local < radius {
            distance = radius - local
        } else if local > surface.width - radius {
            distance = local - (surface.width - radius)
        } else {
            return 0.0
        }
        let clamped = min(distance, radius)
        return radius - sqrt(max(0.0, radius * radius - clamped * clamped))
    }

    private static func limit(column: Int, columns: Int, surface: CGRect) -> CGFloat {
        let radius = min(surface.height, surface.width) / 2.0
        let x = CGFloat(column) / CGFloat(max(1, columns - 1)) * surface.width
        let isRound = surface.width < surface.height * 1.4
        if isRound {
            let t = x / surface.width
            let dome = max(0.0, sin(t * .pi))
            return 9.0 * pow(dome, 2.2)
        }
        let maximum: CGFloat = 15.0
        let edge = min(x, surface.width - x)
        let start = radius * 0.3
        let full = radius * 1.25
        if edge <= start {
            return 0.0
        }
        if edge >= full {
            return maximum
        }
        let t = (edge - start) / (full - start)
        return maximum * t * t * (3.0 - 2.0 * t)
    }

    private func pileTop(index: Int, surface: CGRect, x: CGFloat) -> CGFloat {
        let pile = self.piles[index]
        let columns = pile.heights.count
        let position = (x - surface.minX) / max(1.0, surface.width) * CGFloat(columns - 1)
        let column = min(columns - 1, max(0, Int(position.rounded())))
        return surface.minY + AyuGramEffectsView.baseOffset(x: x, surface: surface) - pile.heights[column]
    }

    private func deposit(index: Int, surface: CGRect, x: CGFloat, amount: CGFloat) {
        let pile = self.piles[index]
        let columns = pile.heights.count
        let position = (x - surface.minX) / max(1.0, surface.width) * CGFloat(columns - 1)
        let center = Int(position.rounded())
        let spread = 4
        for offset in -spread ... spread {
            let column = center + offset
            if column < 0 || column >= columns {
                continue
            }
            let weight = exp(-CGFloat(offset * offset) / 6.0)
            let limit = AyuGramEffectsView.limit(column: column, columns: columns, surface: surface)
            pile.heights[column] = min(limit, pile.heights[column] + amount * weight * 0.35)
        }
    }

    private func settlePiles(dt: CGFloat) {
        let rate = min(1.0, dt * 5.0)
        for pile in self.piles {
            let count = pile.heights.count
            guard count > 2 else {
                continue
            }
            var next = pile.heights
            for column in 1 ..< count - 1 {
                let slopeLeft = pile.heights[column] - pile.heights[column - 1]
                let slopeRight = pile.heights[column] - pile.heights[column + 1]
                var change: CGFloat = 0.0
                if slopeLeft > 1.4 {
                    change -= (slopeLeft - 1.4) * 0.25 * rate
                    next[column - 1] += (slopeLeft - 1.4) * 0.25 * rate
                }
                if slopeRight > 1.4 {
                    change -= (slopeRight - 1.4) * 0.25 * rate
                    next[column + 1] += (slopeRight - 1.4) * 0.25 * rate
                }
                next[column] += change
            }
            pile.heights = next.map { max(0.0, $0) }
        }
    }

    private func renderPiles(surfaces: [CGRect]) {
        for (index, surface) in surfaces.enumerated() {
            let pile = self.piles[index]
            let columns = pile.heights.count
            guard columns > 1 else {
                continue
            }
            var smoothed = pile.heights
            for _ in 0 ..< 2 {
                var pass = smoothed
                for column in 1 ..< columns - 1 {
                    pass[column] = smoothed[column - 1] * 0.25 + smoothed[column] * 0.5 + smoothed[column + 1] * 0.25
                }
                smoothed = pass
            }
            let step = surface.width / CGFloat(columns - 1)
            var tops: [CGPoint] = []
            var bottoms: [CGPoint] = []
            var minTop = CGFloat.greatestFiniteMagnitude
            for column in 0 ..< columns {
                let x = surface.minX + CGFloat(column) * step
                let base = surface.minY + AyuGramEffectsView.baseOffset(x: x, surface: surface) + 1.5
                let height = smoothed[column] > 0.25 ? smoothed[column] + 1.5 : 0.0
                let top = CGPoint(x: x, y: base - height)
                tops.append(top)
                bottoms.append(CGPoint(x: x, y: base))
                minTop = min(minTop, top.y)
            }
            let path = UIBezierPath()
            path.move(to: tops[0])
            for column in 1 ..< columns {
                let previous = tops[column - 1]
                let current = tops[column]
                path.addQuadCurve(to: CGPoint(x: (previous.x + current.x) / 2.0, y: (previous.y + current.y) / 2.0), controlPoint: previous)
            }
            path.addLine(to: tops[columns - 1])
            for point in bottoms.reversed() {
                path.addLine(to: point)
            }
            path.close()

            let highlight = UIBezierPath()
            highlight.move(to: CGPoint(x: tops[0].x, y: tops[0].y + 0.6))
            for column in 1 ..< columns {
                let previous = tops[column - 1]
                let current = tops[column]
                highlight.addQuadCurve(to: CGPoint(x: (previous.x + current.x) / 2.0, y: (previous.y + current.y) / 2.0 + 0.6), controlPoint: CGPoint(x: previous.x, y: previous.y + 0.6))
            }

            let bounds = CGRect(x: surface.minX, y: min(minTop, surface.minY) - 2.0, width: surface.width, height: surface.minY + surface.height * 0.5 - min(minTop, surface.minY) + 2.0)
            pile.container.frame = self.bounds
            pile.container.shadowPath = path.cgPath
            pile.shape.frame = self.bounds
            pile.shape.path = path.cgPath
            pile.gradient.frame = bounds
            let shifted = UIBezierPath(cgPath: path.cgPath)
            shifted.apply(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            pile.mask.frame = CGRect(origin: CGPoint(), size: bounds.size)
            pile.mask.path = shifted.cgPath
            pile.highlight.frame = self.bounds
            pile.highlight.path = highlight.cgPath
        }
        if !self.piles.isEmpty {
            self.storePiles()
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
        let image = AyuGramEffectsView.particleImage(kind: 0)
        let burst = CAEmitterLayer()
        burst.frame = CGRect(origin: CGPoint(), size: size)
        burst.emitterShape = .point
        burst.renderMode = .additive
        burst.emitterPosition = CGPoint(x: CGFloat.random(in: size.width * 0.15 ... size.width * 0.85), y: CGFloat.random(in: size.height * 0.15 ... size.height * 0.45))
        let cell = CAEmitterCell()
        cell.contents = image.cgImage
        cell.contentsScale = image.scale
        cell.color = (palette.randomElement() ?? UIColor.white).cgColor
        cell.birthRate = 400.0
        cell.lifetime = 1.2
        cell.lifetimeRange = 0.4
        cell.velocity = 150.0
        cell.velocityRange = 70.0
        cell.emissionRange = CGFloat.pi * 2.0
        cell.yAcceleration = 140.0
        cell.scale = 0.7
        cell.scaleRange = 0.3
        cell.scaleSpeed = -0.35
        cell.alphaSpeed = -0.8
        burst.emitterCells = [cell]
        burst.beginTime = CACurrentMediaTime()
        self.layer.addSublayer(burst)
        self.activeBursts += 1
        self.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: {
            burst.birthRate = 0.0
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: { [weak self] in
            burst.removeFromSuperlayer()
            guard let self else {
                return
            }
            self.activeBursts = max(0, self.activeBursts - 1)
            self.reload()
        })
    }

    private static func particleImage(kind: Int32) -> UIImage {
        let side: CGFloat
        switch kind {
        case 0, 3:
            side = 8.0
        case 5:
            side = 2.0
        default:
            side = 24.0
        }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let canvas = kind == 5 ? CGSize(width: 2.0, height: 28.0) : CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: canvas, format: format).image(actions: { rendererContext in
            let context = rendererContext.cgContext
            let center = CGPoint(x: canvas.width / 2.0, y: canvas.height / 2.0)
            switch kind {
            case 1:
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(1.4)
                context.setLineCap(.round)
                let radius = side / 2.0 - 1.5
                for index in 0 ..< 6 {
                    let angle = CGFloat(index) * CGFloat.pi / 3.0
                    context.move(to: center)
                    context.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                    let branchBase = CGPoint(x: center.x + cos(angle) * radius * 0.58, y: center.y + sin(angle) * radius * 0.58)
                    for offset in [CGFloat.pi / 4.0, -CGFloat.pi / 4.0] {
                        context.move(to: branchBase)
                        context.addLine(to: CGPoint(x: branchBase.x + cos(angle + offset) * radius * 0.3, y: branchBase.y + sin(angle + offset) * radius * 0.3))
                    }
                }
                context.strokePath()
            case 2:
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: CGFloat.pi / 5.0)
                context.setFillColor(UIColor(red: 1.0, green: 0.76, blue: 0.85, alpha: 1.0).cgColor)
                let petal = UIBezierPath()
                petal.move(to: CGPoint(x: -side * 0.42, y: 0.0))
                petal.addQuadCurve(to: CGPoint(x: side * 0.42, y: -side * 0.04), controlPoint: CGPoint(x: 0.0, y: -side * 0.42))
                petal.addQuadCurve(to: CGPoint(x: -side * 0.42, y: 0.0), controlPoint: CGPoint(x: side * 0.05, y: side * 0.34))
                context.addPath(petal.cgPath)
                context.fillPath()
            case 3:
                let colors = [UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1.0).cgColor, UIColor(red: 1.0, green: 0.9, blue: 0.6, alpha: 0.0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.2, 1.0]) {
                    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: side / 2.0, options: [])
                }
            case 4:
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: -CGFloat.pi / 4.0)
                let palette = [UIColor(red: 0.93, green: 0.5, blue: 0.14, alpha: 1.0), UIColor(red: 0.85, green: 0.3, blue: 0.12, alpha: 1.0), UIColor(red: 0.95, green: 0.7, blue: 0.2, alpha: 1.0)]
                context.setFillColor((palette.randomElement() ?? palette[0]).cgColor)
                let length = side * 0.42
                let width = side * 0.2
                context.move(to: CGPoint(x: -length, y: 0.0))
                context.addQuadCurve(to: CGPoint(x: length, y: 0.0), control: CGPoint(x: 0.0, y: -width * 2.0))
                context.addQuadCurve(to: CGPoint(x: -length, y: 0.0), control: CGPoint(x: 0.0, y: width * 2.0))
                context.closePath()
                context.fillPath()
            case 5:
                let colors = [UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 0.0).cgColor, UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 0.9).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                    context.drawLinearGradient(gradient, start: CGPoint(x: 1.0, y: 0.0), end: CGPoint(x: 1.0, y: canvas.height), options: [])
                }
            default:
                let colors = [UIColor(white: 1.0, alpha: 1.0).cgColor, UIColor(white: 1.0, alpha: 0.85).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.5, 1.0]) {
                    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: side / 2.0, options: [])
                }
            }
        })
    }
}
