import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import EmojiTextAttachmentView
import TextFormat
import GlassBackgroundComponent

private final class AyuBubbleLayerDelegate: NSObject, CALayerDelegate {
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return nullAction
    }
}

private let ayuBubbleLayerDelegate = AyuBubbleLayerDelegate()

private func ayuBubbleClamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    return max(lower, min(upper, value))
}

private func ayuBubbleSmooth(_ value: CGFloat) -> CGFloat {
    let x = ayuBubbleClamp(value, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)
}

private func ayuBubbleLerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
    return from + (to - from) * t
}

private func ayuBubbleGlowImage(isDark: Bool) -> UIImage? {
    return generateImage(CGSize(width: 96.0, height: 96.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        let base = isDark ? UIColor(red: 0.42, green: 0.62, blue: 1.0, alpha: 1.0) : UIColor(red: 0.25, green: 0.48, blue: 1.0, alpha: 1.0)
        let colors: [CGColor] = [
            base.withAlphaComponent(isDark ? 0.42 : 0.26).cgColor,
            base.withAlphaComponent(isDark ? 0.3 : 0.18).cgColor,
            base.withAlphaComponent(0.0).cgColor
        ]
        var locations: [CGFloat] = [0.0, 0.62, 1.0]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: &locations) else {
            return
        }
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: size.width / 2.0, options: [])
    })
}

private let ayuBubbleDarkGlowImage = ayuBubbleGlowImage(isDark: true)
private let ayuBubbleLightGlowImage = ayuBubbleGlowImage(isDark: false)

public final class AyuGramProfileBubblesView: UIView {
    public struct Item: Equatable {
        public let id: String
        public let gift: ProfileGiftsContext.State.StarGift
        public let isFake: Bool

        public init(id: String, gift: ProfileGiftsContext.State.StarGift, isFake: Bool) {
            self.id = id
            self.gift = gift
            self.isFake = isFake
        }
    }

    public struct Layout: Equatable {
        public var size: CGSize
        public var avatarCenter: CGPoint
        public var avatarDiameter: CGFloat
        public var fieldTop: CGFloat
        public var fieldBottom: CGFloat
        public var collapseFraction: CGFloat
        public var isDark: Bool
        public var showsAvatarRim: Bool

        public init(size: CGSize, avatarCenter: CGPoint, avatarDiameter: CGFloat, fieldTop: CGFloat, fieldBottom: CGFloat, collapseFraction: CGFloat, isDark: Bool, showsAvatarRim: Bool) {
            self.size = size
            self.avatarCenter = avatarCenter
            self.avatarDiameter = avatarDiameter
            self.fieldTop = fieldTop
            self.fieldBottom = fieldBottom
            self.collapseFraction = collapseFraction
            self.isDark = isDark
            self.showsAvatarRim = showsAvatarRim
        }
    }

    private final class Bubble {
        let id: String
        let copyIndex: Int
        var item: Item
        let container = SimpleLayer()
        let glowLayer = SimpleLayer()
        let backdropLayer: CALayer?
        let backdropMask = SimpleShapeLayer()
        let bodyLayer = SimpleGradientLayer()
        let bodyMask = SimpleShapeLayer()
        let rimLayer = SimpleGradientLayer()
        let rimMask = SimpleShapeLayer()
        let highlightLayer = SimpleGradientLayer()
        var stickerLayer: InlineStickerItemLayer
        var stickerFileId: Int64

        var depth: CGFloat
        var orbitX: CGFloat
        var orbitY: CGFloat
        var angle: CGFloat
        var speed: CGFloat
        let noise: [CGFloat]
        let wobble: [CGFloat]
        var offset = CGPoint()
        var velocity = CGPoint()
        var appear: CGFloat = 0.0
        var removing = false
        var swellStart: Double?
        var swellSide: CGFloat = 1.0
        var appliedBlur: CGFloat = -1.0
        var appliedDark: Bool?
        var displayCenter = CGPoint()
        var displayRadius: CGFloat = 0.0
        var displayAlpha: CGFloat = 0.0

        init(context: AccountContext, id: String, copyIndex: Int, item: Item, depth: CGFloat, angle: CGFloat) {
            self.id = id
            self.copyIndex = copyIndex
            self.item = item
            self.depth = depth
            self.angle = angle
            self.orbitX = ayuBubbleLerp(0.5, 0.94, depth) + CGFloat.random(in: -0.05 ... 0.05)
            self.orbitY = ayuBubbleLerp(0.62, 1.0, CGFloat.random(in: 0.0 ... 1.0))
            let direction: CGFloat = depth > 0.5 ? -1.0 : 1.0
            let baseSpeed: CGFloat = ayuBubbleLerp(0.09, 0.2, depth)
            self.speed = direction * baseSpeed * CGFloat.random(in: 0.85 ... 1.15)
            var noise: [CGFloat] = []
            for _ in 0 ..< 4 {
                noise.append(CGFloat.random(in: 0.22 ... 0.58))
                noise.append(CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi)))
            }
            self.noise = noise
            var wobble: [CGFloat] = []
            for index in 0 ..< 3 {
                let speed = CGFloat.random(in: 0.5 ... 1.1) + CGFloat(index) * 0.25
                wobble.append(Bool.random() ? speed : -speed)
                wobble.append(CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi)))
            }
            self.wobble = wobble

            let file = AyuGramProfileBubblesView.stickerFile(item.gift)
            self.stickerFileId = file?.fileId.id ?? 0
            self.stickerLayer = AyuGramProfileBubblesView.makeStickerLayer(context: context, file: file)
            self.backdropLayer = createBackdropLayer()

            if let backdropLayer = self.backdropLayer {
                backdropLayer.delegate = ayuBubbleLayerDelegate
                if backdropLayer.responds(to: NSSelectorFromString("setScale:")) {
                    backdropLayer.setValue(0.5 as NSNumber, forKey: "scale")
                }
                backdropLayer.mask = self.backdropMask
            }

            self.backdropMask.fillColor = UIColor.black.cgColor
            self.bodyMask.fillColor = UIColor.black.cgColor
            self.bodyLayer.mask = self.bodyMask
            self.bodyLayer.type = .radial
            self.bodyLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            self.rimMask.fillColor = nil
            self.rimMask.strokeColor = UIColor.black.cgColor
            self.rimMask.lineJoin = .round
            self.rimLayer.mask = self.rimMask
            self.rimLayer.startPoint = CGPoint(x: 0.15, y: 0.05)
            self.rimLayer.endPoint = CGPoint(x: 0.85, y: 0.95)
            self.highlightLayer.type = .radial
            self.highlightLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            self.highlightLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
            self.highlightLayer.colors = [UIColor(white: 1.0, alpha: 0.42).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
            self.highlightLayer.setAffineTransform(CGAffineTransform(rotationAngle: -0.45))

            self.container.addSublayer(self.glowLayer)
            if let backdropLayer = self.backdropLayer {
                self.container.addSublayer(backdropLayer)
            }
            self.container.addSublayer(self.bodyLayer)
            self.container.addSublayer(self.stickerLayer)
            self.container.addSublayer(self.highlightLayer)
            self.container.addSublayer(self.rimLayer)
        }

        func applyAppearance(isDark: Bool) {
            if self.appliedDark == isDark {
                return
            }
            self.appliedDark = isDark
            self.glowLayer.contents = (isDark ? ayuBubbleDarkGlowImage : ayuBubbleLightGlowImage)?.cgImage
            if isDark {
                self.bodyLayer.colors = [
                    UIColor(red: 0.48, green: 0.66, blue: 1.0, alpha: 0.34).cgColor,
                    UIColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 0.4).cgColor,
                    UIColor(red: 0.68, green: 0.82, blue: 1.0, alpha: 0.55).cgColor,
                    UIColor(red: 0.86, green: 0.93, blue: 1.0, alpha: 0.7).cgColor
                ]
                self.rimLayer.colors = [
                    UIColor(white: 1.0, alpha: 0.95).cgColor,
                    UIColor(red: 0.62, green: 0.77, blue: 1.0, alpha: 0.5).cgColor,
                    UIColor(white: 1.0, alpha: 0.8).cgColor
                ]
            } else {
                self.bodyLayer.colors = [
                    UIColor(red: 0.3, green: 0.52, blue: 1.0, alpha: 0.16).cgColor,
                    UIColor(red: 0.33, green: 0.55, blue: 1.0, alpha: 0.26).cgColor,
                    UIColor(red: 0.4, green: 0.62, blue: 1.0, alpha: 0.42).cgColor,
                    UIColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 0.58).cgColor
                ]
                self.rimLayer.colors = [
                    UIColor(white: 1.0, alpha: 1.0).cgColor,
                    UIColor(red: 0.25, green: 0.47, blue: 1.0, alpha: 0.55).cgColor,
                    UIColor(white: 1.0, alpha: 0.9).cgColor
                ]
            }
            self.bodyLayer.locations = [0.0, 0.62, 0.9, 1.0]
            self.rimLayer.locations = [0.0, 0.55, 1.0]
        }

        func applyBlur(radius: CGFloat) {
            guard let backdropLayer = self.backdropLayer else {
                return
            }
            let quantized = (radius * 2.0).rounded() / 2.0
            if quantized == self.appliedBlur {
                return
            }
            self.appliedBlur = quantized
            if let blurFilter = CALayer.blur() {
                blurFilter.setValue(quantized as NSNumber, forKey: "inputRadius")
                backdropLayer.filters = [blurFilter]
            }
        }
    }

    public var action: ((Item) -> Void)?

    private let context: AccountContext
    private var bubbles: [String: Bubble] = [:]
    private var currentLayout: Layout?
    private let rimContainer = SimpleLayer()
    private let rimGlow = SimpleShapeLayer()
    private let rimGradient = SimpleGradientLayer()
    private let rimMask = SimpleShapeLayer()
    private var link: SharedDisplayLinkDriver.Link?
    private var linkFramesPerSecond = 0
    private var lastTimestamp: Double?
    private var time: Double = 0.0
    private var nextSwell: Double = 3.5
    private var observers: [NSObjectProtocol] = []
    private var accessibilityCache: [String: AyuBubbleAccessibilityElement] = [:]
    public var fakeLabel: String?

    public var isActive: Bool = true {
        didSet {
            if self.isActive != oldValue {
                self.updateRunning()
            }
        }
    }

    public var hasItems: Bool {
        return self.bubbles.values.contains(where: { !$0.removing })
    }

    public init(context: AccountContext) {
        self.context = context
        super.init(frame: CGRect())
        self.clipsToBounds = false
        self.isAccessibilityElement = false

        self.rimGlow.fillColor = nil
        self.rimGlow.lineWidth = 6.0
        self.rimMask.fillColor = nil
        self.rimMask.strokeColor = UIColor.black.cgColor
        self.rimMask.lineWidth = 1.6
        self.rimGradient.type = .conic
        self.rimGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.rimGradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        self.rimGradient.mask = self.rimMask
        self.rimContainer.addSublayer(self.rimGlow)
        self.rimContainer.addSublayer(self.rimGradient)
        self.rimContainer.zPosition = -1000.0
        self.rimContainer.opacity = 0.0
        self.layer.addSublayer(self.rimContainer)

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:))))

        let names: [Notification.Name] = [
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            UIApplication.didBecomeActiveNotification,
            UIApplication.didEnterBackgroundNotification
        ]
        for name in names {
            self.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                self?.updateRunning()
            }))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.link?.invalidate()
    }

    fileprivate static func stickerFile(_ gift: ProfileGiftsContext.State.StarGift) -> TelegramMediaFile? {
        switch gift.gift {
        case let .generic(gift):
            return gift.file
        case let .unique(gift):
            for attribute in gift.attributes {
                if case let .model(_, file, _, _) = attribute {
                    return file
                }
            }
            return nil
        }
    }

    fileprivate static func makeStickerLayer(context: AccountContext, file: TelegramMediaFile?) -> InlineStickerItemLayer {
        let emoji = ChatTextInputTextCustomEmojiAttribute(
            interactivelySelectedFromPackId: nil,
            fileId: file?.fileId.id ?? 0,
            file: file
        )
        return InlineStickerItemLayer(
            context: .account(context),
            userLocation: .other,
            attemptSynchronousLoad: false,
            emoji: emoji,
            file: file,
            cache: context.animationCache,
            renderer: context.animationRenderer,
            unique: true,
            placeholderColor: UIColor.white.withAlphaComponent(0.12),
            pointSize: CGSize(width: 96.0, height: 96.0),
            loopCount: 1
        )
    }

    private static let depthPattern: [CGFloat] = [0.82, 0.32, 0.6, 0.14, 0.72, 0.44, 0.24, 0.94]

    private static func expandedItems(_ items: [Item]) -> [(id: String, copyIndex: Int, item: Item)] {
        let unique = Array(items.prefix(8))
        if unique.isEmpty {
            return []
        }
        let target = min(8, max(unique.count, min(7, unique.count * 3)))
        var result: [(id: String, copyIndex: Int, item: Item)] = []
        var copyIndex = 0
        while result.count < target {
            for item in unique where result.count < target {
                result.append((id: copyIndex == 0 ? item.id : item.id + "|" + String(copyIndex), copyIndex: copyIndex, item: item))
            }
            copyIndex += 1
        }
        return result
    }

    public func update(items: [Item], layout: Layout) {
        let limited = AyuGramProfileBubblesView.expandedItems(items)
        self.currentLayout = layout
        var validIds = Set<String>()
        let count = max(1, limited.count)
        for (index, entry) in limited.enumerated() {
            let item = entry.item
            validIds.insert(entry.id)
            if let bubble = self.bubbles[entry.id] {
                bubble.removing = false
                if bubble.item != item {
                    bubble.item = item
                    let file = AyuGramProfileBubblesView.stickerFile(item.gift)
                    let fileId = file?.fileId.id ?? 0
                    if fileId != bubble.stickerFileId {
                        bubble.stickerFileId = fileId
                        let previous = bubble.stickerLayer
                        let replacement = AyuGramProfileBubblesView.makeStickerLayer(context: self.context, file: file)
                        replacement.bounds = previous.bounds
                        replacement.position = previous.position
                        bubble.container.replaceSublayer(previous, with: replacement)
                        bubble.stickerLayer = replacement
                    }
                }
            } else {
                let depth = AyuGramProfileBubblesView.depthPattern[index % AyuGramProfileBubblesView.depthPattern.count]
                let fraction: CGFloat = CGFloat(index) / CGFloat(count)
                let jitter: CGFloat = CGFloat.random(in: -0.25 ... 0.25)
                let angle: CGFloat = fraction * 2.0 * CGFloat.pi - CGFloat.pi * 0.5 + jitter
                let bubble = Bubble(context: self.context, id: entry.id, copyIndex: entry.copyIndex, item: item, depth: depth, angle: angle)
                bubble.offset = self.anchor(for: bubble, layout: layout, swell: 0.0)
                bubble.container.opacity = 0.0
                self.layer.addSublayer(bubble.container)
                self.bubbles[entry.id] = bubble
            }
        }
        for (id, bubble) in self.bubbles where !validIds.contains(id) {
            bubble.removing = true
        }
        if !AyuGramProfileBubblesView.motionAllowed {
            for bubble in self.bubbles.values {
                bubble.appear = bubble.removing ? 0.0 : 1.0
            }
        }
        self.updateRunning()
        self.render(dt: 0.0)
    }

    private static var motionAllowed: Bool {
        return !UIAccessibility.isReduceMotionEnabled
    }

    private var shouldRun: Bool {
        guard self.isActive, self.window != nil, !self.isHidden, AyuGramProfileBubblesView.motionAllowed, UIApplication.shared.applicationState != .background else {
            return false
        }
        guard let layout = self.currentLayout, layout.collapseFraction < 0.62 else {
            return false
        }
        return !self.bubbles.isEmpty
    }

    private func updateRunning() {
        let framesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        if self.shouldRun {
            if let link = self.link, self.linkFramesPerSecond == framesPerSecond {
                link.isPaused = false
            } else {
                self.link?.invalidate()
                self.linkFramesPerSecond = framesPerSecond
                self.lastTimestamp = nil
                self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(framesPerSecond), { [weak self] _ in
                    self?.tick()
                })
            }
        } else {
            self.link?.isPaused = true
            self.lastTimestamp = nil
            if !AyuGramProfileBubblesView.motionAllowed {
                self.render(dt: 0.0)
            }
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        self.updateRunning()
    }

    public override var isHidden: Bool {
        didSet {
            if self.isHidden != oldValue {
                self.updateRunning()
            }
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt: Double
        if let lastTimestamp = self.lastTimestamp {
            dt = min(1.0 / 20.0, max(0.0, now - lastTimestamp))
        } else {
            dt = 1.0 / 60.0
        }
        self.lastTimestamp = now
        self.render(dt: dt)
        if !self.shouldRun {
            self.link?.isPaused = true
            self.lastTimestamp = nil
        }
    }

    private func fieldGeometry(layout: Layout) -> (origin: CGPoint, halfWidth: CGFloat, halfHeight: CGFloat, avatarRadius: CGFloat) {
        let avatarRadius = max(30.0, layout.avatarDiameter / 2.0)
        let top = layout.fieldTop - layout.avatarCenter.y
        let bottom = layout.fieldBottom - layout.avatarCenter.y
        let centerY = (top + bottom) / 2.0
        let halfHeight = max(avatarRadius * 1.2, (bottom - top) / 2.0)
        return (CGPoint(x: 0.0, y: centerY), layout.size.width / 2.0, halfHeight, avatarRadius)
    }

    private func baseRadius(for bubble: Bubble, layout: Layout) -> CGFloat {
        let avatarDiameter = max(60.0, min(120.0, layout.avatarDiameter))
        return avatarDiameter * ayuBubbleLerp(0.15, 0.27, bubble.depth)
    }

    private func swellAmount(for bubble: Bubble) -> CGFloat {
        guard let start = bubble.swellStart else {
            return 0.0
        }
        let progress = CGFloat((self.time - start) / 4.4)
        if progress <= 0.0 || progress >= 1.0 {
            return 0.0
        }
        return 0.5 - 0.5 * cos(progress * 2.0 * CGFloat.pi)
    }

    private func anchor(for bubble: Bubble, layout: Layout, swell: CGFloat) -> CGPoint {
        let geometry = self.fieldGeometry(layout: layout)
        let t = CGFloat(self.time)
        let noise = bubble.noise
        let noiseX1: CGFloat = sin(noise[0] * t + noise[1])
        let noiseX2: CGFloat = sin(noise[2] * t + noise[3])
        let noiseY1: CGFloat = sin(noise[4] * t + noise[5])
        let noiseY2: CGFloat = sin(noise[6] * t + noise[7])
        let noiseX: CGFloat = geometry.halfWidth * 0.07 * (noiseX1 + 0.6 * noiseX2)
        let noiseY: CGFloat = geometry.halfHeight * 0.14 * (noiseY1 + 0.6 * noiseY2)
        let orbitCos: CGFloat = cos(bubble.angle)
        let orbitSin: CGFloat = sin(bubble.angle)
        var point = CGPoint(
            x: geometry.origin.x + geometry.halfWidth * bubble.orbitX * orbitCos + noiseX,
            y: geometry.origin.y + geometry.halfHeight * bubble.orbitY * orbitSin + noiseY
        )
        if swell > 0.0 {
            let target = CGPoint(x: bubble.swellSide * geometry.halfWidth * 0.16, y: geometry.avatarRadius * 1.45)
            point.x = ayuBubbleLerp(point.x, target.x, swell * 0.85)
            point.y = ayuBubbleLerp(point.y, target.y, swell * 0.85)
        }
        return point
    }

    private func startSwellIfNeeded(layout: Layout) {
        guard AyuGramProfileBubblesView.motionAllowed, self.time >= self.nextSwell else {
            return
        }
        if self.bubbles.values.contains(where: { $0.swellStart != nil }) {
            return
        }
        let halfWidth = layout.size.width / 2.0
        let candidates = self.bubbles.values.filter { bubble in
            return !bubble.removing && bubble.appear >= 1.0 && abs(bubble.offset.x) < halfWidth * 0.55 && bubble.displayAlpha > 0.5
        }
        guard let chosen = candidates.randomElement() else {
            self.nextSwell = self.time + 1.5
            return
        }
        chosen.swellStart = self.time
        chosen.swellSide = chosen.offset.x >= 0.0 ? 1.0 : -1.0
        self.nextSwell = self.time + 4.4 + Double.random(in: 4.0 ... 7.5)
    }

    private func blobPath(center: CGPoint, radius: CGFloat, bubble: Bubble, squash: CGPoint, amplitude: CGFloat) -> CGPath {
        let count = 20
        let t = CGFloat(self.time)
        let wobble = bubble.wobble
        let speed = hypot(squash.x, squash.y)
        let direction = speed > 0.001 ? CGPoint(x: squash.x / speed, y: squash.y / speed) : CGPoint(x: 1.0, y: 0.0)
        let stretch = min(0.12, speed / 1600.0)
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        for index in 0 ..< count {
            let phi: CGFloat = CGFloat(index) / CGFloat(count) * 2.0 * CGFloat.pi
            let wave2: CGFloat = sin(2.0 * phi + wobble[0] * t + wobble[1])
            let wave3: CGFloat = sin(3.0 * phi + wobble[2] * t + wobble[3])
            let wave4: CGFloat = sin(4.0 * phi + wobble[4] * t + wobble[5])
            let deform: CGFloat = 0.045 * wave2 + 0.048 * wave3 + 0.018 * wave4
            let r: CGFloat = radius * (1.0 + deform * amplitude)
            var point = CGPoint(x: cos(phi) * r, y: sin(phi) * r)
            let along = point.x * direction.x + point.y * direction.y
            let across = -point.x * direction.y + point.y * direction.x
            let scaledAlong = along * (1.0 + stretch)
            let scaledAcross = across * (1.0 - stretch * 0.6)
            point = CGPoint(x: scaledAlong * direction.x - scaledAcross * direction.y + center.x, y: scaledAlong * direction.y + scaledAcross * direction.x + center.y)
            points.append(point)
        }
        let path = CGMutablePath()
        path.move(to: points[0])
        for index in 0 ..< count {
            let p0 = points[(index - 1 + count) % count]
            let p1 = points[index]
            let p2 = points[(index + 1) % count]
            let p3 = points[(index + 2) % count]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0, y: p2.y - (p3.y - p1.y) / 6.0)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }

    private func render(dt: Double) {
        guard let layout = self.currentLayout else {
            return
        }
        let motion = AyuGramProfileBubblesView.motionAllowed
        if motion {
            self.time += dt
        }
        let step = CGFloat(dt)
        let geometry = self.fieldGeometry(layout: layout)
        let width = layout.size.width
        let collapse = ayuBubbleClamp(layout.collapseFraction, 0.0, 1.0)

        if motion && dt > 0.0 {
            self.startSwellIfNeeded(layout: layout)
        }

        var removed: [String] = []
        let ordered = self.bubbles.values.sorted(by: { $0.depth < $1.depth })
        var swells: [String: CGFloat] = [:]
        var radii: [String: CGFloat] = [:]
        for bubble in ordered {
            let swell = self.swellAmount(for: bubble)
            if bubble.swellStart != nil && swell == 0.0 && self.time - (bubble.swellStart ?? 0.0) > 1.0 {
                bubble.swellStart = nil
            }
            swells[bubble.id] = swell
            let base = self.baseRadius(for: bubble, layout: layout)
            radii[bubble.id] = ayuBubbleLerp(base, max(base, width * 0.165), swell)
        }

        if motion && dt > 0.0 {
            for bubble in ordered {
                let swell = swells[bubble.id] ?? 0.0
                let speedScale: CGFloat = 1.0 + swell * 0.5
                bubble.angle += bubble.speed * step * speedScale
                if bubble.removing {
                    bubble.appear = max(0.0, bubble.appear - step * 2.2)
                } else {
                    bubble.appear = min(1.0, bubble.appear + step * 1.4)
                }
                let target = self.anchor(for: bubble, layout: layout, swell: swell)
                let stiffness: CGFloat = 3.2 + 7.0 * swell
                let damping: CGFloat = swell > 0.0 ? 1.9 * sqrt(stiffness) : 3.4
                var acceleration = CGPoint(x: (target.x - bubble.offset.x) * stiffness - bubble.velocity.x * damping, y: (target.y - bubble.offset.y) * stiffness - bubble.velocity.y * damping)
                let radius = radii[bubble.id] ?? 0.0
                if swell < 0.05 {
                    for other in ordered where other !== bubble && !other.removing {
                        let otherSwell = swells[other.id] ?? 0.0
                        if otherSwell > 0.05 {
                            continue
                        }
                        let dx = bubble.offset.x - other.offset.x
                        let dy = bubble.offset.y - other.offset.y
                        let distance = max(0.001, hypot(dx, dy))
                        let minimum = (radius + (radii[other.id] ?? 0.0)) * 1.02
                        if distance < minimum {
                            let weight = ayuBubbleClamp(1.0 - abs(bubble.depth - other.depth) * 1.7, 0.0, 1.0)
                            let push = (minimum - distance) * 11.0 * weight
                            acceleration.x += dx / distance * push
                            acceleration.y += dy / distance * push
                        }
                    }
                    let avatarDistance = max(0.001, hypot(bubble.offset.x, bubble.offset.y))
                    let avatarMinimum = geometry.avatarRadius * 0.55 + radius * 0.4
                    if avatarDistance < avatarMinimum {
                        let push = (avatarMinimum - avatarDistance) * 7.0
                        acceleration.x += bubble.offset.x / avatarDistance * push
                        acceleration.y += bubble.offset.y / avatarDistance * push
                    }
                }
                bubble.velocity.x += acceleration.x * step
                bubble.velocity.y += acceleration.y * step
                let speed = hypot(bubble.velocity.x, bubble.velocity.y)
                if speed > 260.0 {
                    bubble.velocity.x *= 260.0 / speed
                    bubble.velocity.y *= 260.0 / speed
                }
                bubble.offset.x += bubble.velocity.x * step
                bubble.offset.y += bubble.velocity.y * step
                if bubble.removing && bubble.appear <= 0.0 {
                    removed.append(bubble.id)
                }
            }
        } else if !motion {
            for bubble in ordered {
                bubble.offset = self.anchor(for: bubble, layout: layout, swell: 0.0)
                bubble.velocity = CGPoint()
                if bubble.removing {
                    removed.append(bubble.id)
                }
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let avatarRadius = layout.avatarDiameter / 2.0
        let rimAlpha = layout.showsAvatarRim && !self.bubbles.isEmpty ? ayuBubbleClamp(1.0 - collapse * 2.2, 0.0, 1.0) : 0.0
        self.rimContainer.opacity = Float(rimAlpha)
        if rimAlpha > 0.0 {
            let rimFrame = CGRect(x: layout.avatarCenter.x - avatarRadius - 6.0, y: layout.avatarCenter.y - avatarRadius - 6.0, width: avatarRadius * 2.0 + 12.0, height: avatarRadius * 2.0 + 12.0)
            self.rimContainer.frame = rimFrame
            let localBounds = CGRect(origin: CGPoint(), size: rimFrame.size)
            let ringPath = CGPath(ellipseIn: localBounds.insetBy(dx: 6.0 + 0.6, dy: 6.0 + 0.6), transform: nil)
            self.rimGlow.frame = localBounds
            self.rimGlow.path = ringPath
            self.rimGlow.strokeColor = (layout.isDark ? UIColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 0.2) : UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.16)).cgColor
            self.rimGradient.bounds = localBounds
            self.rimGradient.position = CGPoint(x: localBounds.midX, y: localBounds.midY)
            self.rimMask.frame = localBounds
            self.rimMask.path = ringPath
            self.rimGradient.colors = [
                UIColor(white: 1.0, alpha: 0.18).cgColor,
                UIColor(red: 0.72, green: 0.84, blue: 1.0, alpha: 0.85).cgColor,
                UIColor(white: 1.0, alpha: 0.95).cgColor,
                UIColor(red: 0.6, green: 0.76, blue: 1.0, alpha: 0.6).cgColor,
                UIColor(white: 1.0, alpha: 0.18).cgColor
            ]
            if motion {
                self.rimGradient.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(self.time) * 0.22))
            }
        }

        for bubble in ordered {
            let swell = swells[bubble.id] ?? 0.0
            var radius = radii[bubble.id] ?? 0.0
            var offset = bubble.offset
            let appear = ayuBubbleSmooth(bubble.appear)
            let edgeDistance = min(layout.avatarCenter.x + offset.x, width - layout.avatarCenter.x - offset.x)
            let edgeVisibility = ayuBubbleSmooth((edgeDistance + radius * 0.6) / (radius * 1.6))
            let topEdge = geometry.origin.y - geometry.halfHeight * 1.15
            let topVisibility = ayuBubbleSmooth((offset.y - topEdge + radius * 0.4) / (radius * 1.3))
            let bottomEdge = geometry.origin.y + geometry.halfHeight * 1.1
            let bottomVisibility = ayuBubbleLerp(ayuBubbleSmooth((bottomEdge - offset.y + radius * 0.4) / (radius * 1.3)), 1.0, swell)
            let visibility = edgeVisibility * topVisibility * bottomVisibility
            let parallax = ayuBubbleLerp(0.6, 1.4, bubble.depth)
            offset.x *= 1.0 - collapse * 0.75
            offset.y = offset.y * (1.0 - collapse * 0.75) - collapse * 40.0 * parallax
            radius *= (1.0 - collapse * 0.55) * ayuBubbleLerp(0.55, 1.0, visibility) * ayuBubbleLerp(0.35, 1.0, appear)
            let alpha = appear * visibility * ayuBubbleLerp(0.8, 1.0, max(bubble.depth, swell)) * ayuBubbleClamp(1.0 - collapse * 1.7, 0.0, 1.0)
            let center = CGPoint(x: layout.avatarCenter.x + offset.x, y: layout.avatarCenter.y + offset.y)
            bubble.displayCenter = center
            bubble.displayRadius = radius
            bubble.displayAlpha = alpha

            bubble.applyAppearance(isDark: layout.isDark)
            bubble.applyBlur(radius: ProcessInfo.processInfo.isLowPowerModeEnabled ? 2.0 : 2.0 + radius * 0.06)

            let side = max(4.0, ceil(radius * 3.0))
            let bounds = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
            let localCenter = CGPoint(x: side / 2.0, y: side / 2.0)
            bubble.container.bounds = bounds
            bubble.container.position = center
            bubble.container.opacity = Float(alpha)
            bubble.container.zPosition = swell > 0.02 ? 100.0 + swell : bubble.depth * 10.0
            bubble.container.isHidden = alpha < 0.005

            if alpha >= 0.005 {
                let path = self.blobPath(center: localCenter, radius: radius, bubble: bubble, squash: motion ? bubble.velocity : CGPoint(), amplitude: motion ? (1.0 + swell * 0.15) : 0.4)
                let glowSide = radius * 2.75
                bubble.glowLayer.frame = CGRect(x: localCenter.x - glowSide / 2.0, y: localCenter.y - glowSide / 2.0, width: glowSide, height: glowSide)
                if let backdropLayer = bubble.backdropLayer {
                    backdropLayer.frame = bounds
                    bubble.backdropMask.frame = bounds
                    bubble.backdropMask.path = path
                }
                bubble.bodyLayer.frame = bounds
                bubble.bodyMask.frame = bounds
                bubble.bodyMask.path = path
                let reach = ayuBubbleClamp(radius * 1.04 / side, 0.05, 0.5)
                bubble.bodyLayer.endPoint = CGPoint(x: 0.5 + reach, y: 0.5 + reach)
                bubble.rimLayer.frame = bounds
                bubble.rimMask.frame = bounds
                bubble.rimMask.path = path
                bubble.rimMask.lineWidth = max(1.0, min(2.6, radius * 0.05))
                bubble.highlightLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: radius * 0.82, height: radius * 0.5))
                bubble.highlightLayer.position = CGPoint(x: localCenter.x - radius * 0.25, y: localCenter.y - radius * 0.49)
                let stickerSide = radius * 1.12
                let bobWave: CGFloat = sin(CGFloat(self.time) * 1.3 + bubble.noise[1])
                let bob: CGFloat = motion ? 1.6 * bobWave : 0.0
                bubble.stickerLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: stickerSide, height: stickerSide))
                bubble.stickerLayer.position = CGPoint(x: localCenter.x, y: localCenter.y + bob)
            }
        }

        CATransaction.commit()

        for id in removed {
            if let bubble = self.bubbles.removeValue(forKey: id) {
                bubble.container.removeFromSuperlayer()
            }
        }
    }

    private func bubble(at point: CGPoint) -> Bubble? {
        var result: Bubble?
        for bubble in self.bubbles.values where !bubble.removing && bubble.displayAlpha > 0.3 && !bubble.container.isHidden {
            let distance = hypot(point.x - bubble.displayCenter.x, point.y - bubble.displayCenter.y)
            if distance <= bubble.displayRadius * 1.05 {
                if let current = result, current.container.zPosition >= bubble.container.zPosition {
                    continue
                }
                result = bubble
            }
        }
        return result
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.bubble(at: point) != nil
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state, let bubble = self.bubble(at: recognizer.location(in: self)) else {
            return
        }
        bubble.container.animateScale(from: 0.86, to: 1.0, duration: 0.35, timingFunction: kCAMediaTimingFunctionSpring)
        self.action?(bubble.item)
    }

    public override var accessibilityElements: [Any]? {
        get {
            var elements: [AyuBubbleAccessibilityElement] = []
            var validIds = Set<String>()
            let sorted = self.bubbles.values.filter { !$0.removing && $0.copyIndex == 0 && $0.displayAlpha > 0.3 }.sorted(by: { lhs, rhs in
                if lhs.displayCenter.y != rhs.displayCenter.y {
                    return lhs.displayCenter.y < rhs.displayCenter.y
                }
                return lhs.displayCenter.x < rhs.displayCenter.x
            })
            for bubble in sorted {
                guard case let .unique(gift) = bubble.item.gift.gift else {
                    continue
                }
                validIds.insert(bubble.id)
                let element: AyuBubbleAccessibilityElement
                if let current = self.accessibilityCache[bubble.id] {
                    element = current
                } else {
                    element = AyuBubbleAccessibilityElement(accessibilityContainer: self)
                    self.accessibilityCache[bubble.id] = element
                }
                if bubble.item.isFake, let fakeLabel = self.fakeLabel, !fakeLabel.isEmpty {
                    element.accessibilityLabel = "\(gift.title) #\(gift.number), \(fakeLabel)"
                } else {
                    element.accessibilityLabel = "\(gift.title) #\(gift.number)"
                }
                element.accessibilityTraits = .button
                element.accessibilityFrameInContainerSpace = CGRect(x: bubble.displayCenter.x - bubble.displayRadius, y: bubble.displayCenter.y - bubble.displayRadius, width: bubble.displayRadius * 2.0, height: bubble.displayRadius * 2.0)
                let item = bubble.item
                element.activate = { [weak self] in
                    guard let self else {
                        return false
                    }
                    self.action?(item)
                    return true
                }
                elements.append(element)
            }
            for id in Array(self.accessibilityCache.keys) where !validIds.contains(id) {
                self.accessibilityCache.removeValue(forKey: id)
            }
            return elements
        } set(value) {
        }
    }
}

private final class AyuBubbleAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        return self.activate?() ?? false
    }
}

public final class AyuGramProfileBubblesHaloView: UIView {
    private let gradientLayer = SimpleGradientLayer()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.gradientLayer.type = .radial
        self.layer.addSublayer(self.gradientLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(size: CGSize, center: CGPoint, radius: CGFloat, isDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradientLayer.frame = CGRect(origin: CGPoint(), size: size)
        if isDark {
            self.gradientLayer.colors = [
                UIColor(red: 0.36, green: 0.44, blue: 0.6, alpha: 0.42).cgColor,
                UIColor(red: 0.22, green: 0.28, blue: 0.4, alpha: 0.24).cgColor,
                UIColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 0.0).cgColor
            ]
        } else {
            self.gradientLayer.colors = [
                UIColor(red: 0.55, green: 0.68, blue: 1.0, alpha: 0.22).cgColor,
                UIColor(red: 0.6, green: 0.72, blue: 1.0, alpha: 0.1).cgColor,
                UIColor(red: 0.6, green: 0.72, blue: 1.0, alpha: 0.0).cgColor
            ]
        }
        self.gradientLayer.locations = [0.0, 0.45, 1.0]
        if size.width > 0.0 && size.height > 0.0 {
            self.gradientLayer.startPoint = CGPoint(x: center.x / size.width, y: center.y / size.height)
            self.gradientLayer.endPoint = CGPoint(x: (center.x + radius) / size.width, y: (center.y + radius) / size.height)
        }
        CATransaction.commit()
    }
}
