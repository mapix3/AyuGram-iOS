import Foundation
import UIKit
import AsyncDisplayKit
import UIKit.UIGestureRecognizerSubclass
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

private struct AyuGramIcicle {
    var position: CGFloat
    var length: CGFloat
    var maximum: CGFloat
    var width: CGFloat
    var lean: CGFloat
}

private final class AyuGramChunk {
    enum Kind {
        case crumb
        case snowball
    }

    let layer = CALayer()
    var position: CGPoint
    var velocity: CGPoint
    var life: CGFloat
    let kind: Kind
    var gravity: CGFloat = 900.0

    init(kind: Kind, position: CGPoint, velocity: CGPoint, life: CGFloat) {
        self.kind = kind
        self.position = position
        self.velocity = velocity
        self.life = life
    }
}

private final class AyuGramTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTouch: ((CGPoint) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)

        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
        self.delegate = self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first, let view = self.view {
            self.onTouch?(touch.location(in: view))
        }
        self.state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

private struct AyuGramSurface {
    let key: Int
    let rect: CGRect
    let isTabBar: Bool
}

private final class AyuGramWeakView {
    weak var view: UIView?
    let key: Int
    let isTabBar: Bool
    let isChrome: Bool

    init(view: UIView, isTabBar: Bool, isChrome: Bool) {
        self.view = view
        self.key = ObjectIdentifier(view).hashValue
        self.isTabBar = isTabBar
        self.isChrome = isChrome
    }
}

private final class AyuGramSnowPile {
    var heights: [CGFloat] = []
    var icicles: [AyuGramIcicle] = []
    var previousFrame: CGRect?
    var stillTime: CGFloat = 0.0
    let container = CALayer()
    let gradient = CAGradientLayer()
    let mask = CAShapeLayer()
    let icicleLayer = CAShapeLayer()

    init() {
        self.container.zPosition = 5.0
        self.container.shadowColor = UIColor(red: 0.08, green: 0.12, blue: 0.24, alpha: 1.0).cgColor
        self.container.shadowOpacity = 0.32
        self.container.shadowRadius = 2.0
        self.container.shadowOffset = CGSize(width: 0.0, height: 1.0)
        self.gradient.colors = [
            UIColor(white: 1.0, alpha: 1.0).cgColor,
            UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1.0).cgColor,
            UIColor(red: 0.84, green: 0.88, blue: 0.95, alpha: 1.0).cgColor
        ]
        self.gradient.locations = [0.0, 0.55, 1.0]
        self.gradient.mask = self.mask
        self.icicleLayer.fillColor = UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 0.88).cgColor
        self.icicleLayer.strokeColor = UIColor(red: 0.7, green: 0.8, blue: 0.95, alpha: 0.55).cgColor
        self.icicleLayer.lineWidth = 0.5
        self.container.addSublayer(self.gradient)
        self.container.addSublayer(self.icicleLayer)
    }
}

public final class AyuGramEffectsView: UIView {
    private static let columnWidth: CGFloat = 2.0
    private static var keptPiles: [Int: [CGFloat]] = [:]
    public private(set) static weak var shared: AyuGramEffectsView?

    private var observers: [NSObjectProtocol] = []
    private var displayLink: CADisplayLink?
    private var inBackground = false
    private var activeBursts = 0
    private var flakes: [AyuGramFlake] = []
    private var flakeLayers: [CALayer] = []
    private var flakeVariants: [Int] = []
    private var currentKind: Int32 = -1
    private var currentCount = 0
    private var flakeImages: [CGImage] = []
    private var flakeScale: CGFloat = 1.0
    private var piles: [Int: AyuGramSnowPile] = [:]
    private var tracked: [AyuGramWeakView] = []
    private var scanTimer: CGFloat = 0.0
    private var frontTimer: CGFloat = 0.0
    private var chunks: [AyuGramChunk] = []
    private var lastTimestamp: CFTimeInterval = 0.0
    private var time: CGFloat = 0.0
    private var showsParticles = false
    private var showsPiles = false
    private var lastSize = CGSize()
    private var snowman: AyuGramSnowman?
    private var snowmanCooldown: CGFloat = 6.0
    private var lastSurfaces: [AyuGramSurface] = []

    public init() {
        super.init(frame: .zero)

        AyuGramEffectsView.shared = self
        self.isUserInteractionEnabled = true
        self.clipsToBounds = true
        self.backgroundColor = nil
        self.isOpaque = false
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:))))

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
        self.snowman?.remove()
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard self.isUserInteractionEnabled, !self.isHidden, let snowman = self.snowman, !snowman.container.isHidden, snowman.hitPart(at: point) != nil else {
            return nil
        }
        return self
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard let snowman = self.snowman else {
            return
        }
        let location = recognizer.location(in: self)
        guard let body = snowman.hitPart(at: location) else {
            return
        }
        snowman.smash(body: body, burst: { [weak self] center, radius in
            self?.burst(at: center, radius: radius)
        })
    }

    private weak var touchObserver: AyuGramTouchObserver?

    public override func didMoveToWindow() {
        super.didMoveToWindow()

        if let window = self.window, self.touchObserver?.view !== window {
            if let previous = self.touchObserver {
                previous.view?.removeGestureRecognizer(previous)
            }
            let observer = AyuGramTouchObserver(target: nil, action: nil)
            observer.onTouch = { [weak self] point in
                self?.touched(at: point)
            }
            window.addGestureRecognizer(observer)
            self.touchObserver = observer
        }
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

    private var previewKind: Int32?
    private var previewToken = 0

    public func preview(kind: Int32) {
        self.previewKind = kind
        self.previewToken += 1
        let token = self.previewToken
        self.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: { [weak self] in
            guard let self, self.previewToken == token else {
                return
            }
            self.previewKind = nil
            self.reload()
        })
    }

    public func reload() {
        var state = AyuGramAppearance.shared.effects
        if let previewKind = self.previewKind {
            state.kind = previewKind
            state.particles = true
            state.drift = state.drift && (previewKind == 0 || previewKind == 1)
        }
        let size = self.bounds.size
        let hasSize = size.width > 0.0 && size.height > 0.0
        let active = hasSize && self.window != nil && !self.isPaused
        self.showsParticles = active && state.particles
        self.showsPiles = self.showsParticles && state.drift && (state.kind == 0 || state.kind == 1)

        if self.showsParticles {
            let count = AyuGramEffectsView.flakeCount(kind: state.kind, amount: state.amount)
            if state.kind != self.currentKind || count != self.currentCount {
                self.rebuildFlakes(kind: state.kind, count: count, size: size)
            }
        } else if !self.flakes.isEmpty {
            self.removeFlakes()
        }

        if !self.showsPiles {
            if !self.piles.isEmpty {
                self.storePiles()
                for pile in self.piles.values {
                    pile.container.removeFromSuperlayer()
                }
                self.piles = [:]
            }
            self.tracked = []
            if let snowman = self.snowman {
                snowman.remove()
                self.snowman = nil
            }
        }

        let running = self.showsParticles || self.showsPiles || !self.chunks.isEmpty
        self.isHidden = !(running || self.activeBursts > 0)
        if running && active {
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
        default:
            maximum = 110.0
        }
        return max(6, Int((maximum * amount).rounded()))
    }

    private func removeFlakes() {
        for layer in self.flakeLayers {
            layer.removeFromSuperlayer()
        }
        self.flakeLayers = []
        self.flakes = []
        self.flakeVariants = []
        self.currentKind = -1
        self.currentCount = 0
    }

    private func rebuildFlakes(kind: Int32, count: Int, size: CGSize) {
        self.removeFlakes()
        self.currentKind = kind
        self.currentCount = count
        let images = kind == 0 ? [AyuGramEffectsView.particleImage(kind: 0), AyuGramEffectsView.particleImage(kind: 6)] : [AyuGramEffectsView.particleImage(kind: kind)]
        self.flakeImages = images.compactMap { $0.cgImage }
        self.flakeScale = images.first?.scale ?? 1.0
        guard !self.flakeImages.isEmpty else {
            return
        }
        for _ in 0 ..< count {
            let variant = kind == 0 && Double.random(in: 0.0 ... 1.0) < 0.38 ? 1 : 0
            var flake = self.makeFlake(kind: kind, variant: variant, width: size.width)
            flake.y = CGFloat.random(in: -20.0 ... max(0.0, size.height))
            self.flakes.append(flake)
            self.flakeVariants.append(variant)
            let layer = CALayer()
            layer.contents = self.flakeImages[min(variant, self.flakeImages.count - 1)]
            layer.contentsScale = self.flakeScale
            layer.contentsGravity = .resizeAspect
            layer.zPosition = 6.0
            layer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: flake.size, height: kind == 5 ? 18.0 : flake.size))
            layer.opacity = flake.alpha
            layer.position = CGPoint(x: flake.x, y: flake.y)
            self.layer.addSublayer(layer)
            self.flakeLayers.append(layer)
        }
    }

    private func makeFlake(kind: Int32, variant: Int, width: CGFloat) -> AyuGramFlake {
        let x = CGFloat.random(in: -20.0 ... width + 20.0)
        switch kind {
        case 1:
            let size = CGFloat.random(in: 6.0 ... 10.0)
            return AyuGramFlake(x: x, y: -size, speed: CGFloat.random(in: 26.0 ... 44.0), size: size, swayAmplitude: CGFloat.random(in: 6.0 ... 16.0), swayFrequency: CGFloat.random(in: 0.2 ... 0.5), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: CGFloat.random(in: 0.0 ... 6.28), spin: CGFloat.random(in: -0.8 ... 0.8), alpha: Float.random(in: 0.7 ... 0.95), twinkle: 0.0, lastSway: 0.0)
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
            return AyuGramFlake(x: x, y: -20.0, speed: CGFloat.random(in: 520.0 ... 720.0), size: 1.2, swayAmplitude: 0.0, swayFrequency: 0.0, phase: 0.0, rotation: 0.0, spin: 0.0, alpha: Float.random(in: 0.25 ... 0.5), twinkle: 0.0, lastSway: 0.0)
        default:
            if variant == 1 {
                let size = CGFloat.random(in: 5.0 ... 8.0)
                return AyuGramFlake(x: x, y: -size, speed: CGFloat.random(in: 34.0 ... 56.0), size: size, swayAmplitude: CGFloat.random(in: 4.0 ... 12.0), swayFrequency: CGFloat.random(in: 0.2 ... 0.45), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: CGFloat.random(in: 0.0 ... 6.28), spin: CGFloat.random(in: -0.6 ... 0.6), alpha: Float.random(in: 0.75 ... 1.0), twinkle: 0.0, lastSway: 0.0)
            }
            let size = CGFloat.random(in: 2.0 ... 3.6)
            return AyuGramFlake(x: x, y: -size, speed: 26.0 + size * 7.0 + CGFloat.random(in: 0.0 ... 8.0), size: size, swayAmplitude: CGFloat.random(in: 4.0 ... 12.0), swayFrequency: CGFloat.random(in: 0.2 ... 0.5), phase: CGFloat.random(in: 0.0 ... 6.28), rotation: 0.0, spin: 0.0, alpha: Float(0.6 + size / 3.6 * 0.4), twinkle: 0.0, lastSway: 0.0)
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

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.frontTimer -= dt
        if self.frontTimer <= 0.0 {
            self.frontTimer = 0.5
            if let superview = self.superview, superview.subviews.last !== self {
                superview.bringSubviewToFront(self)
            }
        }
        var surfaces: [AyuGramSurface] = []
        if self.showsPiles {
            self.scanTimer -= dt
            if self.scanTimer <= 0.0 {
                self.scanTimer = 0.35
                self.scanSurfaces()
            }
            surfaces = self.currentSurfaces(size: size)
            self.syncPiles(surfaces: surfaces)
            self.handleMotion(surfaces: surfaces, dt: dt)
        }
        self.lastSurfaces = surfaces
        let wind = sin(self.time * 0.13) * 6.0 + sin(self.time * 0.41) * 2.5
        let kind = self.currentKind

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
            if self.showsPiles {
                for item in surfaces where flake.x > item.rect.minX + 2.0 && flake.x < item.rect.maxX - 2.0 {
                    guard let pile = self.piles[item.key] else {
                        continue
                    }
                    let top = self.pileTop(pile: pile, surface: item.rect, x: flake.x)
                    if previousY <= top && flake.y >= top {
                        let volume = self.flakeVariants[index] == 1 ? flake.size * 0.22 : flake.size * 0.3
                        self.deposit(pile: pile, surface: item.rect, x: flake.x, amount: volume)
                        landed = true
                        break
                    }
                }
            }

            if landed || flake.y > size.height + 30.0 || flake.x < -60.0 || flake.x > size.width + 60.0 {
                var next = self.makeFlake(kind: kind, variant: self.flakeVariants[index], width: size.width)
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
            self.settlePiles(dt: dt, snowing: self.showsParticles)
            self.renderPiles(surfaces: surfaces)
            self.updateSnowman(surfaces: surfaces, dt: dt)
        }
        self.stepChunks(dt: dt, size: size)

        CATransaction.commit()

        if !self.showsParticles && !self.showsPiles && self.chunks.isEmpty {
            self.reload()
        }
    }

    private func capacity(for surface: CGRect) -> CGFloat {
        if surface.width < surface.height * 1.4 {
            return 6.5
        }
        if surface.width > 200.0 {
            return 10.5
        }
        return 8.5
    }

    private static func name(of view: UIView) -> String {
        if let node = view.asyncdisplaykit_node {
            return NSStringFromClass(type(of: node))
        }
        return NSStringFromClass(type(of: view))
    }

    private func scanSurfaces() {
        guard let window = self.window else {
            self.tracked = []
            return
        }
        var found: [AyuGramWeakView] = []
        func visit(_ view: UIView, depth: Int, kind: Int) {
            if view === self || view.isHidden || view.alpha < 0.05 || depth > 80 || found.count > 24 {
                return
            }
            let name = AyuGramEffectsView.name(of: view)
            var kind = kind
            if name.contains("TabBar") {
                kind = 1
            } else if name.contains("ChatTextInputPanel") {
                kind = 2
            }
            if name.hasSuffix("GlassBackgroundView") {
                found.append(AyuGramWeakView(view: view, isTabBar: kind == 1, isChrome: kind != 0))
            }
            for subview in view.subviews {
                visit(subview, depth: depth + 1, kind: kind)
            }
        }
        visit(window, depth: 0, kind: 0)
        var result: [AyuGramWeakView] = []
        for item in found {
            guard let view = item.view else {
                continue
            }
            let bounds = view.bounds
            let point = view.convert(CGPoint(x: bounds.midX, y: bounds.minY + min(4.0, bounds.height * 0.25)), to: window)
            if let hit = window.hitTest(point, with: nil), hit !== self {
                if !(hit === view || hit.isDescendant(of: view) || view.isDescendant(of: hit)) {
                    continue
                }
            }
            result.append(item)
        }
        self.tracked = result
    }

    private func currentSurfaces(size: CGSize) -> [AyuGramSurface] {
        let targetLayer = self.layer.presentation() ?? self.layer
        var result: [AyuGramSurface] = []
        for item in self.tracked {
            guard let view = item.view, view.window === self.window else {
                continue
            }
            let layer = view.layer.presentation() ?? view.layer
            let rect = layer.convert(layer.bounds, to: targetLayer)
            if rect.width < 26.0 || rect.height < 26.0 || rect.height > 96.0 || rect.width > size.width * 0.995 || rect.minY < 30.0 || rect.maxY > size.height || rect.minX < -1.0 || rect.maxX > size.width + 1.0 {
                continue
            }
            if !item.isChrome {
                if rect.width > 76.0 || rect.height > 60.0 || rect.minY > 150.0 {
                    continue
                }
            }
            var visible = true
            var current: UIView? = view
            while let node = current, node !== self.window {
                let nodeLayer = node.layer.presentation() ?? node.layer
                if node.isHidden || nodeLayer.opacity < 0.9 {
                    visible = false
                    break
                }
                if node !== view && (node.clipsToBounds || nodeLayer.masksToBounds || nodeLayer.mask != nil) {
                    let clip = nodeLayer.convert(nodeLayer.bounds, to: targetLayer)
                    if rect.minY < clip.minY + 1.0 || rect.maxY > clip.maxY + 1.0 || rect.minX < clip.minX - 1.0 || rect.maxX > clip.maxX + 1.0 {
                        visible = false
                        break
                    }
                }
                let transform = nodeLayer.affineTransform()
                if abs(transform.a - 1.0) > 0.02 || abs(transform.d - 1.0) > 0.02 || abs(transform.b) > 0.02 {
                    visible = false
                    break
                }
                current = node.superview
            }
            if !visible {
                continue
            }
            if result.contains(where: { $0.rect.intersects(rect.insetBy(dx: -2.0, dy: -12.0)) }) {
                continue
            }
            result.append(AyuGramSurface(key: item.key, rect: rect, isTabBar: item.isTabBar))
        }
        return result
    }

    private func syncPiles(surfaces: [AyuGramSurface]) {
        var present = Set<Int>()
        for item in surfaces {
            present.insert(item.key)
            let surface = item.rect
            let columns = max(3, Int(surface.width / AyuGramEffectsView.columnWidth) + 1)
            if let pile = self.piles[item.key] {
                if pile.heights.count != columns {
                    let previousWidth = pile.previousFrame?.width ?? surface.width
                    pile.heights = AyuGramEffectsView.resample(pile.heights, to: columns)
                    if !pile.icicles.isEmpty, previousWidth > 0.0 {
                        for icicle in pile.icicles.indices {
                            pile.icicles[icicle].position = pile.icicles[icicle].position / previousWidth * surface.width
                        }
                    }
                }
                continue
            }
            let pile = AyuGramSnowPile()
            if let kept = AyuGramEffectsView.keptPiles[item.key], !kept.isEmpty {
                pile.heights = AyuGramEffectsView.resample(kept, to: columns)
            } else {
                var heights = (0 ..< columns).map { column -> CGFloat in
                    return self.limit(column: column, columns: columns, surface: surface) * CGFloat.random(in: 0.49 ... 0.61)
                }
                for _ in 0 ..< 4 {
                    var pass = heights
                    for column in 1 ..< columns - 1 {
                        pass[column] = heights[column - 1] * 0.25 + heights[column] * 0.5 + heights[column + 1] * 0.25
                    }
                    heights = pass
                }
                pile.heights = heights
            }
            if !item.isTabBar && surface.width > 120.0 && surface.minY > self.bounds.height * 0.5 {
                pile.icicles = self.makeIcicles(surface: surface)
            }
            self.layer.addSublayer(pile.container)
            self.piles[item.key] = pile
        }
        for (key, pile) in self.piles where !present.contains(key) {
            AyuGramEffectsView.keptPiles[key] = pile.heights
            pile.container.removeFromSuperlayer()
            self.piles[key] = nil
        }
        if AyuGramEffectsView.keptPiles.count > 300 {
            AyuGramEffectsView.keptPiles = [:]
        }
    }
    private func makeIcicles(surface: CGRect) -> [AyuGramIcicle] {
        let radius = min(surface.width, surface.height) / 2.0
        var result: [AyuGramIcicle] = []
        var x = radius * 0.9 + CGFloat.random(in: 0.0 ... 6.0)
        while x < surface.width - radius * 0.9 {
            let maximum = CGFloat.random(in: 3.0 ... 12.0)
            result.append(AyuGramIcicle(position: x, length: maximum * CGFloat.random(in: 0.0 ... 0.5), maximum: maximum, width: CGFloat.random(in: 2.2 ... 3.6), lean: CGFloat.random(in: -0.6 ... 0.6)))
            x += CGFloat.random(in: 7.0 ... 15.0)
        }
        return result
    }

    private func storePiles() {
        for (key, pile) in self.piles {
            AyuGramEffectsView.keptPiles[key] = pile.heights
        }
    }
    private static func resample(_ values: [CGFloat], to count: Int) -> [CGFloat] {
        guard values.count > 1, count > 1 else {
            return Array(repeating: values.first ?? 0.0, count: max(count, 0))
        }
        return (0 ..< count).map { index in
            let position = CGFloat(index) / CGFloat(count - 1) * CGFloat(values.count - 1)
            let lower = min(values.count - 1, Int(position))
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

    private func limit(column: Int, columns: Int, surface: CGRect) -> CGFloat {
        let cap = self.capacity(for: surface)
        let x = CGFloat(column) / CGFloat(max(1, columns - 1)) * surface.width
        let radius = min(surface.height, surface.width) / 2.0
        let start: CGFloat
        if surface.width < surface.height * 1.4 {
            start = surface.width * 0.16
        } else {
            start = radius * 0.32
        }
        let maxDepth: CGFloat = 2.5
        let drape = radius - sqrt(max(0.0, radius * radius - (radius - maxDepth) * (radius - maxDepth)))
        let edge = min(x, surface.width - x) - max(start, drape)
        if edge <= 0.0 {
            return 0.0
        }
        if edge >= cap {
            return cap
        }
        let t = 1.0 - edge / cap
        return cap * sqrt(max(0.0, 1.0 - t * t))
    }

    private func column(for x: CGFloat, surface: CGRect, columns: Int) -> Int {
        let position = (x - surface.minX) / max(1.0, surface.width) * CGFloat(columns - 1)
        return min(columns - 1, max(0, Int(position.rounded())))
    }

    private func pileTop(pile: AyuGramSnowPile, surface: CGRect, x: CGFloat) -> CGFloat {
        let column = self.column(for: x, surface: surface, columns: pile.heights.count)
        return surface.minY + AyuGramEffectsView.baseOffset(x: x, surface: surface) - pile.heights[column]
    }
    private func deposit(pile: AyuGramSnowPile, surface: CGRect, x: CGFloat, amount: CGFloat) {
        let columns = pile.heights.count
        let center = self.column(for: x, surface: surface, columns: columns)
        for offset in -4 ... 4 {
            let column = center + offset
            if column < 0 || column >= columns {
                continue
            }
            let weight = exp(-CGFloat(offset * offset) / 6.0)
            let limit = self.limit(column: column, columns: columns, surface: surface)
            let current = pile.heights[column]
            pile.heights[column] = max(current, min(limit, current + amount * weight * 0.35))
        }
    }
    private func handleMotion(surfaces: [AyuGramSurface], dt: CGFloat) {
        for item in surfaces {
            guard let pile = self.piles[item.key] else {
                continue
            }
            let surface = item.rect
            defer {
                pile.previousFrame = surface
            }
            guard let previous = pile.previousFrame, abs(previous.width - surface.width) < 1.0 else {
                pile.stillTime = 0.0
                continue
            }
            let dx = surface.midX - previous.midX
            let dy = surface.minY - previous.minY
            let distance = hypot(dx, dy)
            let speed = distance / max(dt, 0.001)
            if distance < 0.3 {
                pile.stillTime += dt
                if pile.stillTime > 4.0 {
                    for icicle in pile.icicles.indices where pile.icicles[icicle].length < pile.icicles[icicle].maximum {
                        pile.icicles[icicle].length = min(pile.icicles[icicle].maximum, pile.icicles[icicle].length + dt * 0.05 * pile.icicles[icicle].maximum)
                    }
                }
                continue
            }
            pile.stillTime = 0.0
            let _ = speed
        }
    }

    private func shed(pile: AyuGramSnowPile, surface: CGRect, fraction: CGFloat, velocity: CGPoint, breakIcicles: Bool) {
        let columns = pile.heights.count
        let step = surface.width / CGFloat(max(1, columns - 1))
        var column = 0
        while column < columns {
            let removed = pile.heights[column] * fraction
            if removed > 0.6 {
                let x = surface.minX + CGFloat(column) * step
                let y = surface.minY + AyuGramEffectsView.baseOffset(x: x, surface: surface) - pile.heights[column] * 0.5
                let crumbVelocity = CGPoint(x: velocity.x * 0.35 + CGFloat.random(in: -40.0 ... 40.0), y: min(0.0, velocity.y) * 0.2 - CGFloat.random(in: 20.0 ... 90.0))
                self.addCrumb(at: CGPoint(x: x, y: y), velocity: crumbVelocity, size: min(7.0, 2.0 + removed * 0.8))
            }
            column += 5
        }
        for column in 0 ..< columns {
            pile.heights[column] *= (1.0 - fraction)
        }
        if breakIcicles {
            for icicle in pile.icicles.indices where pile.icicles[icicle].length > 1.5 {
                let item = pile.icicles[icicle]
                let chunk = AyuGramChunk(kind: .crumb, position: CGPoint(x: surface.minX + item.position, y: surface.maxY + item.length / 2.0), velocity: CGPoint(x: CGFloat.random(in: -15.0 ... 15.0), y: CGFloat.random(in: 0.0 ... 40.0)), life: 2.0)
                chunk.layer.backgroundColor = UIColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 0.85).cgColor
                chunk.layer.bounds = CGRect(x: 0.0, y: 0.0, width: item.width * 0.7, height: item.length)
                chunk.layer.cornerRadius = item.width * 0.35
                self.addChunk(chunk)
                pile.icicles[icicle].length = 0.0
            }
            pile.stillTime = 0.0
        }
    }

    fileprivate func touched(at windowPoint: CGPoint) {
        guard self.showsPiles, let window = self.window else {
            return
        }
        let point = self.convert(windowPoint, from: window)
        for item in self.lastSurfaces {
            guard let pile = self.piles[item.key] else {
                continue
            }
            let area = item.rect.insetBy(dx: -10.0, dy: -10.0).union(CGRect(x: item.rect.minX, y: item.rect.minY - self.capacity(for: item.rect) - 6.0, width: item.rect.width, height: 1.0))
            guard area.contains(point) else {
                continue
            }
            self.shed(pile: pile, surface: item.rect, fraction: 1.0, velocity: CGPoint(x: 0.0, y: 0.0), breakIcicles: true)
        }
    }

    private func settlePiles(dt: CGFloat, snowing: Bool) {
        let rate = min(1.0, dt * 6.0)
        for pile in self.piles.values {
            let count = pile.heights.count
            guard count > 2 else {
                continue
            }
            var next = pile.heights
            for column in 1 ..< count - 1 {
                let slopeLeft = pile.heights[column] - pile.heights[column - 1]
                let slopeRight = pile.heights[column] - pile.heights[column + 1]
                if slopeLeft > 0.9 {
                    let moved = (slopeLeft - 0.9) * 0.25 * rate
                    next[column] -= moved
                    next[column - 1] += moved
                }
                if slopeRight > 0.9 {
                    let moved = (slopeRight - 0.9) * 0.25 * rate
                    next[column] -= moved
                    next[column + 1] += moved
                }
            }
            let melt: CGFloat = snowing ? 0.0 : dt * 0.04
            pile.heights = next.map { max(0.0, $0 - melt) }
        }
    }

    private func renderPiles(surfaces: [AyuGramSurface]) {
        for item in surfaces {
            guard let pile = self.piles[item.key] else {
                continue
            }
            let surface = item.rect
            let columns = pile.heights.count
            guard columns > 2 else {
                continue
            }
            for column in 0 ..< columns {
                let limit = self.limit(column: column, columns: columns, surface: surface)
                if pile.heights[column] > limit * 1.3 {
                    pile.heights[column] = limit * 1.3
                }
            }
            var smoothed = pile.heights
            for _ in 0 ..< 3 {
                var pass = smoothed
                for column in 1 ..< columns - 1 {
                    pass[column] = smoothed[column - 1] * 0.25 + smoothed[column] * 0.5 + smoothed[column + 1] * 0.25
                }
                smoothed = pass
            }
            let step = surface.width / CGFloat(columns - 1)
            var tops: [CGPoint] = []
            var bottoms: [CGPoint] = []
            var minTop = surface.minY
            for column in 0 ..< columns {
                let x = surface.minX + CGFloat(column) * step
                let base = surface.minY + AyuGramEffectsView.baseOffset(x: x, surface: surface) + 1.0
                let height = smoothed[column] > 0.35 ? smoothed[column] + 1.0 : 0.0
                let top = CGPoint(x: x, y: base - height)
                tops.append(top)
                bottoms.append(CGPoint(x: x, y: base))
                minTop = min(minTop, top.y)
            }
            let path = UIBezierPath()
            path.move(to: bottoms[0])
            path.addLine(to: tops[0])
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

            let frame = CGRect(x: surface.minX - 2.0, y: minTop - 2.0, width: surface.width + 4.0, height: surface.minY - minTop + surface.height * 0.5 + 4.0)
            pile.container.frame = self.bounds
            pile.container.shadowPath = path.cgPath
            pile.gradient.frame = frame
            let shifted = UIBezierPath(cgPath: path.cgPath)
            shifted.apply(CGAffineTransform(translationX: -frame.minX, y: -frame.minY))
            pile.mask.frame = CGRect(origin: CGPoint(), size: frame.size)
            pile.mask.path = shifted.cgPath

            if pile.icicles.isEmpty {
                pile.icicleLayer.path = nil
            } else {
                let icicles = UIBezierPath()
                let bottom = surface.maxY - 0.5
                for icicle in pile.icicles where icicle.length > 0.8 {
                    let x = surface.minX + icicle.position
                    let tip = CGPoint(x: x + icicle.lean, y: bottom + icicle.length)
                    icicles.move(to: CGPoint(x: x - icicle.width / 2.0, y: bottom - 0.5))
                    icicles.addQuadCurve(to: tip, controlPoint: CGPoint(x: x - icicle.width * 0.25, y: bottom + icicle.length * 0.55))
                    icicles.addQuadCurve(to: CGPoint(x: x + icicle.width / 2.0, y: bottom - 0.5), controlPoint: CGPoint(x: x + icicle.width * 0.25, y: bottom + icicle.length * 0.55))
                    icicles.close()
                }
                pile.icicleLayer.frame = self.bounds
                pile.icicleLayer.path = icicles.cgPath
            }
        }
        if !self.piles.isEmpty {
            self.storePiles()
        }
    }

    private func updateSnowman(surfaces: [AyuGramSurface], dt: CGFloat) {
        guard let item = surfaces.first(where: { $0.isTabBar && $0.rect.width > 120.0 }), let pile = self.piles[item.key] else {
            self.snowman?.container.isHidden = true
            return
        }
        let surface = item.rect
        let cap = self.capacity(for: surface)
        if let snowman = self.snowman {
            snowman.container.isHidden = false
            let size = snowman.size
            snowman.container.position = CGPoint(x: surface.minX + surface.width * 0.25, y: surface.minY + size.height * 0.03 - cap * 0.62 - size.height / 2.0)
            return
        }
        self.snowmanCooldown -= dt
        guard self.snowmanCooldown <= 0.0 else {
            return
        }
        let columns = pile.heights.count
        var filled: CGFloat = 0.0
        var total: CGFloat = 0.0
        for column in 0 ..< columns {
            let limit = self.limit(column: column, columns: columns, surface: surface)
            filled += min(limit, pile.heights[column])
            total += limit
        }
        guard total > 0.0, filled / total >= 0.85 else {
            return
        }
        let width = min(64.0, max(44.0, surface.height * 1.05))
        let snowman = AyuGramSnowman(width: width)
        snowman.container.zPosition = 4.0
        let size = snowman.size
        snowman.container.position = CGPoint(x: surface.minX + surface.width * 0.25, y: surface.minY + size.height * 0.03 - cap * 0.62 - size.height / 2.0)
        snowman.onGone = { [weak self] melted in
            guard let self else {
                return
            }
            self.snowman = nil
            self.snowmanCooldown = 45.0
            if melted {
                self.addMound()
            }
        }
        snowman.onThrow = { [weak self] point in
            self?.throwSnowball(from: point)
        }
        self.layer.addSublayer(snowman.container)
        self.snowman = snowman
        snowman.build(melts: true)
    }

    private func addMound() {
        guard let item = self.lastSurfaces.first(where: { $0.isTabBar && $0.rect.width > 120.0 }), let pile = self.piles[item.key] else {
            return
        }
        let surface = item.rect
        let columns = pile.heights.count
        let center = self.column(for: surface.minX + surface.width * 0.25, surface: surface, columns: columns)
        let cap = self.capacity(for: surface)
        for offset in -8 ... 8 {
            let column = center + offset
            if column < 0 || column >= columns {
                continue
            }
            let limit = self.limit(column: column, columns: columns, surface: surface)
            pile.heights[column] = min(limit * 1.3, pile.heights[column] + cap * 0.7 * exp(-CGFloat(offset * offset) / 18.0))
        }
    }

    private func addChunk(_ chunk: AyuGramChunk) {
        chunk.layer.zPosition = 7.0
        chunk.layer.position = chunk.position
        self.layer.addSublayer(chunk.layer)
        self.chunks.append(chunk)
        self.reload()
    }

    private func addCrumb(at position: CGPoint, velocity: CGPoint, size: CGFloat) {
        let chunk = AyuGramChunk(kind: .crumb, position: position, velocity: velocity, life: 2.5)
        chunk.layer.backgroundColor = UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1.0).cgColor
        chunk.layer.bounds = CGRect(x: 0.0, y: 0.0, width: size, height: size)
        chunk.layer.cornerRadius = size / 2.0
        self.addChunk(chunk)
    }

    private func burst(at center: CGPoint, radius: CGFloat) {
        for _ in 0 ..< 12 {
            let angle = -CGFloat.pi / 2.0 + CGFloat.random(in: -1.4 ... 1.4)
            let speed = radius * CGFloat.random(in: 3.0 ... 6.0)
            let position = CGPoint(x: center.x + cos(angle) * radius * 0.4, y: center.y + sin(angle) * radius * 0.4)
            let chunk = AyuGramChunk(kind: .crumb, position: position, velocity: CGPoint(x: cos(angle) * speed, y: sin(angle) * speed), life: CGFloat.random(in: 0.7 ... 1.1))
            chunk.gravity = 420.0
            let size = CGFloat.random(in: 1.4 ... 3.6)
            chunk.layer.backgroundColor = UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1.0).cgColor
            chunk.layer.bounds = CGRect(x: 0.0, y: 0.0, width: size, height: size)
            chunk.layer.cornerRadius = size / 2.0
            self.addChunk(chunk)
        }
    }

    private func throwSnowball(from point: CGPoint) {
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0, !self.isPaused else {
            return
        }
        let target = CGPoint(x: CGFloat.random(in: size.width * 0.15 ... size.width * 0.9), y: CGFloat.random(in: size.height * 0.18 ... size.height * 0.55))
        let flight: CGFloat = 0.9
        let gravity: CGFloat = 900.0
        let velocity = CGPoint(x: (target.x - point.x) / flight, y: (target.y - point.y - 0.5 * gravity * flight * flight) / flight)
        let chunk = AyuGramChunk(kind: .snowball, position: point, velocity: velocity, life: flight)
        chunk.gravity = gravity
        chunk.layer.contents = AyuGramEffectsView.snowballImage.cgImage
        chunk.layer.contentsScale = AyuGramEffectsView.snowballImage.scale
        chunk.layer.bounds = CGRect(x: 0.0, y: 0.0, width: 8.0, height: 8.0)
        self.addChunk(chunk)
    }

    private static let snowballImage: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 8.0, height: 8.0), format: format).image(actions: { rendererContext in
            let context = rendererContext.cgContext
            context.addEllipse(in: CGRect(x: 0.0, y: 0.0, width: 8.0, height: 8.0))
            context.clip()
            let colors = [UIColor(white: 1.0, alpha: 1.0).cgColor, UIColor(red: 0.945, green: 0.96, blue: 0.99, alpha: 1.0).cgColor, UIColor(red: 0.655, green: 0.725, blue: 0.855, alpha: 1.0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0]) {
                context.drawRadialGradient(gradient, startCenter: CGPoint(x: 2.9, y: 2.4), startRadius: 0.0, endCenter: CGPoint(x: 2.9, y: 2.4), endRadius: 6.4, options: [.drawsAfterEndLocation])
            }
        })
    }()

    private func splat(at point: CGPoint) {
        let splat = CAShapeLayer()
        splat.zPosition = 7.0
        let blob = UIBezierPath()
        for index in 0 ..< 10 {
            let angle = CGFloat(index) / 10.0 * 2.0 * .pi
            let radius: CGFloat = (index % 2 == 0 ? 6.5 : 4.0) * CGFloat.random(in: 0.85 ... 1.15)
            let item = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius * 0.75)
            if index == 0 {
                blob.move(to: item)
            } else {
                blob.addLine(to: item)
            }
        }
        blob.close()
        let fill = UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 0.95).cgColor
        splat.path = blob.cgPath
        splat.fillColor = fill
        splat.strokeColor = fill
        splat.lineJoin = .round
        splat.lineWidth = 2.0
        let end = CGPoint(x: point.x, y: point.y + 34.0)
        splat.position = end
        splat.opacity = 0.0
        self.layer.addSublayer(splat)
        let slide = CABasicAnimation(keyPath: "position.y")
        slide.fromValue = point.y
        slide.toValue = end.y
        slide.duration = 3.2
        slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let stretch = CABasicAnimation(keyPath: "transform.scale.y")
        stretch.fromValue = 1.0
        stretch.toValue = 1.6
        stretch.duration = 3.2
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.5, 1.0]
        fade.duration = 3.2
        splat.add(slide, forKey: "slide")
        splat.add(stretch, forKey: "stretch")
        splat.add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: {
            splat.removeFromSuperlayer()
        })
        for _ in 0 ..< 6 {
            let angle = CGFloat.random(in: 0.0 ... 2.0 * .pi)
            self.addCrumb(at: point, velocity: CGPoint(x: cos(angle) * 60.0, y: sin(angle) * 60.0 - 40.0), size: CGFloat.random(in: 1.4 ... 2.6))
        }
    }

    private func stepChunks(dt: CGFloat, size: CGSize) {
        guard !self.chunks.isEmpty else {
            return
        }
        var remaining: [AyuGramChunk] = []
        var splats: [CGPoint] = []
        for chunk in self.chunks {
            chunk.velocity.y += chunk.gravity * dt
            chunk.position.x += chunk.velocity.x * dt
            chunk.position.y += chunk.velocity.y * dt
            chunk.life -= dt
            if chunk.kind == .snowball && chunk.life <= 0.0 {
                chunk.layer.removeFromSuperlayer()
                splats.append(chunk.position)
                continue
            }
            if chunk.life <= 0.0 || chunk.position.y > size.height + 20.0 {
                chunk.layer.removeFromSuperlayer()
                continue
            }
            chunk.layer.position = chunk.position
            if chunk.kind == .crumb && chunk.life < 0.5 {
                chunk.layer.opacity = Float(max(0.0, chunk.life / 0.5))
            }
            remaining.append(chunk)
        }
        self.chunks = remaining
        for point in splats {
            self.splat(at: point)
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
        burst.zPosition = 8.0
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
        case 6:
            side = 12.0
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
            case 6:
                context.setStrokeColor(UIColor.white.cgColor)
                context.setLineWidth(1.5)
                context.setLineCap(.round)
                let radius = side / 2.0 - 1.0
                for index in 0 ..< 3 {
                    let angle = CGFloat(index) * CGFloat.pi / 3.0 + CGFloat.pi / 2.0
                    context.move(to: CGPoint(x: center.x - cos(angle) * radius, y: center.y - sin(angle) * radius))
                    context.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                }
                context.strokePath()
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: CGRect(x: center.x - 1.4, y: center.y - 1.4, width: 2.8, height: 2.8))
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
                context.setFillColor(UIColor(red: 0.93, green: 0.5, blue: 0.14, alpha: 1.0).cgColor)
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
                let colors = [UIColor(white: 1.0, alpha: 1.0).cgColor, UIColor(white: 1.0, alpha: 0.9).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0]) {
                    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: side / 2.0, options: [])
                }
            }
        })
    }
}
