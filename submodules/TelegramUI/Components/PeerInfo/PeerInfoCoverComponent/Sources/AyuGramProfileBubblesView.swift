import Foundation
import UIKit
import UIKit.UIGestureRecognizerSubclass
import Display
import SwiftSignalKit
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

private let ayuBubbleDesignRadius: CGFloat = 40.0
private let ayuBubbleDesignSide: CGFloat = ayuBubbleDesignRadius * 3.0
private let ayuBubbleBaseSpeed: CGFloat = 0.3
private let ayuBubbleMaxSpeed: CGFloat = 9.0
private let ayuBubblePitch: CGFloat = 0.22
private let ayuBubbleLatitudes: [CGFloat] = [0.04, 0.66, 0.22, 0.92, 0.4, 0.8, 0.12, 0.54]
private let ayuBubbleOrbitScales: [CGFloat] = [1.0, 0.9, 1.05, 0.82, 0.97, 0.88, 1.08, 0.93]
private let ayuBubbleSizeScales: [CGFloat] = [1.0, 0.86, 1.1, 0.8, 0.95, 0.84, 1.04, 0.9]
private let ayuBubbleLongitudeJitter: [CGFloat] = [0.0, 0.21, -0.14, 0.33, -0.08, 0.17, -0.26, 0.11]

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

private func ayuBubbleBlobPath(center: CGPoint, radius: CGFloat, seeds: [CGFloat]) -> CGPath {
    let count = 24
    var points: [CGPoint] = []
    points.reserveCapacity(count)
    for index in 0 ..< count {
        let phi: CGFloat = CGFloat(index) / CGFloat(count) * 2.0 * CGFloat.pi
        let wave2: CGFloat = sin(2.0 * phi + seeds[0])
        let wave3: CGFloat = sin(3.0 * phi + seeds[1])
        let wave4: CGFloat = sin(4.0 * phi + seeds[2])
        let deform: CGFloat = 0.034 * wave2 + 0.03 * wave3 + 0.012 * wave4
        let r: CGFloat = radius * (1.0 + deform)
        points.append(CGPoint(x: center.x + cos(phi) * r, y: center.y + sin(phi) * r))
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

public final class AyuGramOrbitPanGestureRecognizer: UIPanGestureRecognizer, UIGestureRecognizerDelegate {
    private let bandTest: (CGPoint) -> Bool
    private let isBlocked: () -> Bool
    private let updated: (AyuGramOrbitPanGestureRecognizer) -> Void
    private var startLocation = CGPoint()
    private var decided = false

    public init(bandTest: @escaping (CGPoint) -> Bool, isBlocked: @escaping () -> Bool, updated: @escaping (AyuGramOrbitPanGestureRecognizer) -> Void) {
        self.bandTest = bandTest
        self.isBlocked = isBlocked
        self.updated = updated
        super.init(target: nil, action: nil)
        self.addTarget(self, action: #selector(self.handleUpdate))
        self.delegate = self
        self.maximumNumberOfTouches = 1
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
    }

    @objc private func handleUpdate() {
        self.updated(self)
    }

    public override func reset() {
        super.reset()
        self.decided = false
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, let touch = touches.first, let view = self.view else {
            self.state = .failed
            return
        }
        let location = touch.location(in: view)
        if !self.bandTest(location) || self.isBlocked() {
            self.state = .failed
            return
        }
        self.startLocation = location
        self.decided = false
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !self.decided, let touch = touches.first, let view = self.view {
            let location = touch.location(in: view)
            let dx = abs(location.x - self.startLocation.x)
            let dy = abs(location.y - self.startLocation.y)
            if dx > 3.0 || dy > 3.0 {
                self.decided = true
                if dy >= dx || self.isBlocked() {
                    self.state = .failed
                    return
                }
            }
        }
        super.touchesMoved(touches, with: event)
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if self.isBlocked() {
            return false
        }
        let velocity = self.velocity(in: self.view)
        return abs(velocity.x) >= abs(velocity.y)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer.view is UIScrollView
    }
}

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
        public var collapseFraction: CGFloat
        public var isDark: Bool
        public var showsAvatarRim: Bool

        public init(size: CGSize, avatarCenter: CGPoint, avatarDiameter: CGFloat, collapseFraction: CGFloat, isDark: Bool, showsAvatarRim: Bool) {
            self.size = size
            self.avatarCenter = avatarCenter
            self.avatarDiameter = avatarDiameter
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
        let shapeLayer = SimpleLayer()
        let backdropLayer: CALayer?
        let backdropMask = SimpleShapeLayer()
        let bodyLayer = SimpleGradientLayer()
        let bodyMask = SimpleShapeLayer()
        let rimLayer = SimpleGradientLayer()
        let rimMask = SimpleShapeLayer()
        let highlightLayer = SimpleGradientLayer()
        var stickerLayer: InlineStickerItemLayer
        var stickerFileId: Int64

        let longitudeOffset: CGFloat
        let latitude: CGFloat
        let orbitScale: CGFloat
        let sizeScale: CGFloat
        let phase1: CGFloat
        let phase2: CGFloat
        let phase3: CGFloat
        let wobbleSpeed: CGFloat
        let beatGain: CGFloat

        var appear: CGFloat = 0.0
        var removing = false
        var isFront = true
        var hop: CGFloat = 0.0
        var hopVelocity: CGFloat = 0.0
        var tapPulse: CGFloat = 0.0
        var lift: CGFloat = 0.0
        var liftTarget: CGFloat = 0.0
        var dragCenter = CGPoint()
        var dragVelocity = CGPoint()
        var lastCenter = CGPoint()
        var hasLastCenter = false
        var screenVelocity = CGPoint()
        var displayCenter = CGPoint()
        var displayRadius: CGFloat = 0.0
        var displayAlpha: CGFloat = 0.0
        var depth: CGFloat = 0.0
        var appliedDark: Bool?
        var appliedLowPower: Bool?

        init(context: AccountContext, id: String, copyIndex: Int, item: Item, slot: Int, longitudeOffset: CGFloat) {
            self.id = id
            self.copyIndex = copyIndex
            self.item = item
            let patternIndex = slot % ayuBubbleLatitudes.count
            self.longitudeOffset = longitudeOffset
            self.latitude = ayuBubbleLatitudes[patternIndex]
            self.orbitScale = ayuBubbleOrbitScales[patternIndex]
            self.sizeScale = ayuBubbleSizeScales[patternIndex]
            self.phase1 = CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi))
            self.phase2 = CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi))
            self.phase3 = CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi))
            self.wobbleSpeed = CGFloat.random(in: 1.6 ... 2.6)
            self.beatGain = CGFloat.random(in: 0.7 ... 1.15)

            let file = AyuGramProfileBubblesView.stickerFile(item.gift)
            self.stickerFileId = file?.fileId.id ?? 0
            self.stickerLayer = AyuGramProfileBubblesView.makeStickerLayer(context: context, file: file)
            self.backdropLayer = createBackdropLayer()

            let side = ayuBubbleDesignSide
            let radius = ayuBubbleDesignRadius
            let bounds = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
            let center = CGPoint(x: side / 2.0, y: side / 2.0)
            let seeds: [CGFloat] = [
                CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi)),
                CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi)),
                CGFloat.random(in: 0.0 ... (2.0 * CGFloat.pi))
            ]
            let path = ayuBubbleBlobPath(center: center, radius: radius, seeds: seeds)

            self.container.bounds = bounds
            self.container.opacity = 0.0

            let glowSide = radius * 2.75
            self.glowLayer.frame = CGRect(x: center.x - glowSide / 2.0, y: center.y - glowSide / 2.0, width: glowSide, height: glowSide)

            self.shapeLayer.bounds = bounds
            self.shapeLayer.position = center

            if let backdropLayer = self.backdropLayer {
                backdropLayer.delegate = ayuBubbleLayerDelegate
                if backdropLayer.responds(to: NSSelectorFromString("setScale:")) {
                    backdropLayer.setValue(0.5 as NSNumber, forKey: "scale")
                }
                backdropLayer.frame = bounds
                self.backdropMask.frame = bounds
                self.backdropMask.path = path
                self.backdropMask.fillColor = UIColor.black.cgColor
                backdropLayer.mask = self.backdropMask
            }

            self.bodyLayer.frame = bounds
            self.bodyMask.frame = bounds
            self.bodyMask.path = path
            self.bodyMask.fillColor = UIColor.black.cgColor
            self.bodyLayer.mask = self.bodyMask
            self.bodyLayer.type = .radial
            self.bodyLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            let reach = radius * 1.04 / side
            self.bodyLayer.endPoint = CGPoint(x: 0.5 + reach, y: 0.5 + reach)

            self.rimLayer.frame = bounds
            self.rimMask.frame = bounds
            self.rimMask.path = path
            self.rimMask.fillColor = nil
            self.rimMask.strokeColor = UIColor.black.cgColor
            self.rimMask.lineJoin = .round
            self.rimMask.lineWidth = 1.8
            self.rimLayer.mask = self.rimMask
            self.rimLayer.startPoint = CGPoint(x: 0.15, y: 0.05)
            self.rimLayer.endPoint = CGPoint(x: 0.85, y: 0.95)

            self.highlightLayer.type = .radial
            self.highlightLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
            self.highlightLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
            self.highlightLayer.colors = [UIColor(white: 1.0, alpha: 0.42).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor]
            self.highlightLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: radius * 0.82, height: radius * 0.5))
            self.highlightLayer.position = CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.49)
            self.highlightLayer.setAffineTransform(CGAffineTransform(rotationAngle: -0.45))

            let stickerSide = radius * 1.12
            self.stickerLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: stickerSide, height: stickerSide))
            self.stickerLayer.position = center

            self.container.addSublayer(self.glowLayer)
            if let backdropLayer = self.backdropLayer {
                self.shapeLayer.addSublayer(backdropLayer)
            }
            self.shapeLayer.addSublayer(self.bodyLayer)
            self.shapeLayer.addSublayer(self.rimLayer)
            self.container.addSublayer(self.shapeLayer)
            self.container.addSublayer(self.stickerLayer)
            self.container.addSublayer(self.highlightLayer)
        }

        func replaceSticker(context: AccountContext, file: TelegramMediaFile?) {
            let previous = self.stickerLayer
            let replacement = AyuGramProfileBubblesView.makeStickerLayer(context: context, file: file)
            replacement.bounds = previous.bounds
            replacement.position = previous.position
            self.container.replaceSublayer(previous, with: replacement)
            self.stickerLayer = replacement
        }

        func applyAppearance(isDark: Bool, lowPower: Bool) {
            if self.appliedLowPower != lowPower {
                self.appliedLowPower = lowPower
                if let backdropLayer = self.backdropLayer, let blurFilter = CALayer.blur() {
                    blurFilter.setValue((lowPower ? 2.0 : 4.5) as NSNumber, forKey: "inputRadius")
                    backdropLayer.filters = [blurFilter]
                }
            }
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
    }

    public var action: ((Item) -> Void)?
    public var fakeLabel: String?
    public let backView: UIView

    private let context: AccountContext
    private var bubbles: [Bubble] = []
    private var currentLayout: Layout?
    private let rimContainer = SimpleLayer()
    private let rimGlow = SimpleShapeLayer()
    private let rimGradient = SimpleGradientLayer()
    private let rimMask = SimpleShapeLayer()
    private var rimAppliedFrame = CGRect()
    private var rimAppliedDark: Bool?
    private var link: SharedDisplayLinkDriver.Link?
    private var linkFramesPerSecond = 0
    private var lastTimestamp: Double?
    private var time: Double = 0.0
    private var observers: [NSObjectProtocol] = []
    private var accessibilityCache: [String: AyuBubbleAccessibilityElement] = [:]

    private var phase: CGFloat = 0.0
    private var angularVelocity: CGFloat = -ayuBubbleBaseSpeed
    private var isSpinning = false
    private var lastOrbitRadius: CGFloat = 150.0

    private weak var draggedBubble: Bubble?
    private var dragTarget = CGPoint()
    private var dragOffset = CGPoint()
    private var hapticFeedback: HapticFeedback?

    private let musicActivityDisposable = MetaDisposable()
    private let musicLevelDisposable = MetaDisposable()
    private var isObservingMusic = false
    private var isObservingLevel = false
    private var musicPlaying = false
    private var musicTimestamp: Double = 0.0
    private var musicGenerationTimestamp: Double = 0.0
    private var musicRate: Double = 1.0
    private var lastLevelTime: Double = 0.0
    private var levelFast: CGFloat = 0.0
    private var levelSlow: CGFloat = 0.0
    private var lastBeatTime: Double = 0.0
    private var fallbackBeatIndex: Int = -1
    private var beatEnvelope: CGFloat = 0.0

    public var isActive: Bool = true {
        didSet {
            if self.isActive != oldValue {
                if !self.isActive {
                    self.releaseDrag()
                }
                self.updateRunning()
            }
        }
    }

    public var hasItems: Bool {
        return self.bubbles.contains(where: { !$0.removing })
    }

    public var isInteracting: Bool {
        return self.draggedBubble != nil
    }

    public init(context: AccountContext) {
        self.context = context
        self.backView = UIView()
        super.init(frame: CGRect())
        self.clipsToBounds = false
        self.isAccessibilityElement = false
        self.backView.clipsToBounds = false
        self.backView.isUserInteractionEnabled = false
        self.backView.isAccessibilityElement = false

        self.rimGlow.fillColor = nil
        self.rimGlow.lineWidth = 6.0
        self.rimMask.fillColor = nil
        self.rimMask.strokeColor = UIColor.black.cgColor
        self.rimMask.lineWidth = 1.6
        self.rimGradient.type = .conic
        self.rimGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.rimGradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        self.rimGradient.mask = self.rimMask
        self.rimGradient.colors = [
            UIColor(white: 1.0, alpha: 0.18).cgColor,
            UIColor(red: 0.72, green: 0.84, blue: 1.0, alpha: 0.85).cgColor,
            UIColor(white: 1.0, alpha: 0.95).cgColor,
            UIColor(red: 0.6, green: 0.76, blue: 1.0, alpha: 0.6).cgColor,
            UIColor(white: 1.0, alpha: 0.18).cgColor
        ]
        self.rimContainer.addSublayer(self.rimGlow)
        self.rimContainer.addSublayer(self.rimGradient)
        self.rimContainer.zPosition = -1000.0
        self.rimContainer.opacity = 0.0
        self.layer.addSublayer(self.rimContainer)

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:)))
        self.addGestureRecognizer(tapRecognizer)
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(self.longPressed(_:)))
        longPressRecognizer.minimumPressDuration = 0.28
        longPressRecognizer.allowableMovement = 12.0
        self.addGestureRecognizer(longPressRecognizer)

        let names: [Notification.Name] = [
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange,
            UIApplication.didBecomeActiveNotification,
            UIApplication.didEnterBackgroundNotification
        ]
        for name in names {
            self.observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main, using: { [weak self] _ in
                guard let self else {
                    return
                }
                if UIApplication.shared.applicationState == .background {
                    self.releaseDrag()
                }
                self.updateRunning()
                self.render(dt: 0.0)
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
        self.musicActivityDisposable.dispose()
        self.musicLevelDisposable.dispose()
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
            pointSize: CGSize(width: 128.0, height: 128.0),
            loopCount: 1
        )
    }

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
        let count = max(1, limited.count)
        var validIds = Set<String>()
        for (index, entry) in limited.enumerated() {
            validIds.insert(entry.id)
            if let bubble = self.bubbles.first(where: { $0.id == entry.id }) {
                bubble.removing = false
                if bubble.item != entry.item {
                    bubble.item = entry.item
                    let file = AyuGramProfileBubblesView.stickerFile(entry.item.gift)
                    let fileId = file?.fileId.id ?? 0
                    if fileId != bubble.stickerFileId {
                        bubble.stickerFileId = fileId
                        bubble.replaceSticker(context: self.context, file: file)
                    }
                }
            } else {
                let jitter = ayuBubbleLongitudeJitter[index % ayuBubbleLongitudeJitter.count]
                let longitudeOffset = CGFloat(index) / CGFloat(count) * 2.0 * CGFloat.pi + jitter - self.phase
                let bubble = Bubble(context: self.context, id: entry.id, copyIndex: entry.copyIndex, item: entry.item, slot: index, longitudeOffset: longitudeOffset)
                bubble.isFront = true
                self.layer.addSublayer(bubble.container)
                self.bubbles.append(bubble)
            }
        }
        for bubble in self.bubbles where !validIds.contains(bubble.id) {
            bubble.removing = true
            if bubble === self.draggedBubble {
                self.releaseDrag()
            }
        }
        if !AyuGramProfileBubblesView.motionAllowed {
            for bubble in self.bubbles {
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
        guard let layout = self.currentLayout, layout.collapseFraction < 0.62 || self.draggedBubble != nil else {
            return false
        }
        return !self.bubbles.isEmpty
    }

    private func updateRunning() {
        let framesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        if self.shouldRun {
            if let link = self.link, self.linkFramesPerSecond == framesPerSecond {
                if link.isPaused {
                    self.lastTimestamp = nil
                    link.isPaused = false
                }
            } else {
                self.link?.invalidate()
                self.linkFramesPerSecond = framesPerSecond
                self.lastTimestamp = nil
                self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(framesPerSecond), { [weak self] _ in
                    self?.tick()
                })
            }
            self.startMusicObservation()
        } else {
            self.link?.isPaused = true
            self.lastTimestamp = nil
            self.stopMusicObservation()
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window == nil {
            self.releaseDrag()
        }
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
            self.stopMusicObservation()
        }
    }

    private func startMusicObservation() {
        if self.isObservingMusic {
            return
        }
        self.isObservingMusic = true
        self.musicActivityDisposable.set((self.context.sharedContext.mediaManager.ayuMusicActivity
        |> deliverOnMainQueue).startStrict(next: { [weak self] activity in
            self?.updateMusicActivity(activity)
        }))
    }

    private func stopMusicObservation() {
        if !self.isObservingMusic {
            return
        }
        self.isObservingMusic = false
        self.musicActivityDisposable.set(nil)
        self.updateMusicActivity(nil)
    }

    private func updateMusicActivity(_ activity: AyuGramMusicActivity?) {
        let isPlaying = activity?.isPlaying ?? false
        if let activity {
            self.musicTimestamp = activity.timestamp
            self.musicGenerationTimestamp = activity.generationTimestamp
            self.musicRate = activity.rate > 0.0 ? activity.rate : 1.0
        }
        if isPlaying != self.musicPlaying {
            self.musicPlaying = isPlaying
            self.fallbackBeatIndex = -1
            self.levelFast = 0.0
            self.levelSlow = 0.0
        }
        if isPlaying && !self.isObservingLevel {
            self.isObservingLevel = true
            self.lastLevelTime = 0.0
            self.musicLevelDisposable.set((self.context.sharedContext.mediaManager.ayuMusicAudioLevel
            |> deliverOnMainQueue).startStrict(next: { [weak self] level in
                self?.handleAudioLevel(level)
            }))
        } else if !isPlaying && self.isObservingLevel {
            self.isObservingLevel = false
            self.musicLevelDisposable.set(nil)
        }
    }

    private func handleAudioLevel(_ level: Float) {
        guard self.musicPlaying, level.isFinite else {
            return
        }
        let now = CACurrentMediaTime()
        self.lastLevelTime = now
        let value = ayuBubbleClamp(CGFloat(level) / 6.0, 0.0, 1.0)
        self.levelFast += (value - self.levelFast) * 0.55
        self.levelSlow += (value - self.levelSlow) * 0.06
        if self.levelFast > self.levelSlow * 1.28 + 0.035 && now - self.lastBeatTime > 0.24 {
            self.lastBeatTime = now
            self.triggerBeat(strength: ayuBubbleClamp(0.45 + (self.levelFast - self.levelSlow) * 3.0, 0.45, 1.0))
        }
    }

    private func triggerBeat(strength: CGFloat) {
        guard AyuGramProfileBubblesView.motionAllowed, self.link != nil, !(self.link?.isPaused ?? true) else {
            return
        }
        self.beatEnvelope = max(self.beatEnvelope, strength)
        for bubble in self.bubbles where !bubble.removing {
            bubble.hopVelocity -= 125.0 * strength * bubble.beatGain
        }
    }

    private func updateFallbackBeat(now: Double) {
        guard self.musicPlaying, now - self.lastLevelTime > 0.8 else {
            return
        }
        let position = self.musicTimestamp + max(0.0, now - self.musicGenerationTimestamp) * self.musicRate
        guard position.isFinite, abs(position) < 1.0e7 else {
            return
        }
        let index = Int(floor(position * 2.0))
        if index != self.fallbackBeatIndex {
            let shouldBeat = self.fallbackBeatIndex >= 0
            self.fallbackBeatIndex = index
            if shouldBeat {
                self.triggerBeat(strength: 0.7)
            }
        }
    }

    public func spinBandContains(_ point: CGPoint) -> Bool {
        guard self.isActive, !self.isHidden, self.window != nil, self.alpha > 0.01, let layout = self.currentLayout, layout.collapseFraction < 0.25, self.hasItems else {
            return false
        }
        if point.x < 24.0 || point.x > layout.size.width {
            return false
        }
        let avatarRadius = max(24.0, layout.avatarDiameter / 2.0)
        let top = layout.avatarCenter.y - avatarRadius * 2.7
        let bottom = layout.avatarCenter.y + avatarRadius * 1.15
        return point.y >= top && point.y <= bottom
    }

    public func spinBegan() {
        self.isSpinning = true
    }

    public func spinChanged(translationX: CGFloat) {
        guard self.isSpinning, translationX.isFinite else {
            return
        }
        self.phase += translationX / max(40.0, self.lastOrbitRadius)
        if self.link == nil || (self.link?.isPaused ?? true) {
            self.render(dt: 0.0)
        }
    }

    public func spinEnded(velocityX: CGFloat) {
        guard self.isSpinning else {
            return
        }
        self.isSpinning = false
        var velocity = velocityX.isFinite ? velocityX / max(40.0, self.lastOrbitRadius) : 0.0
        velocity = ayuBubbleClamp(velocity, -ayuBubbleMaxSpeed, ayuBubbleMaxSpeed)
        if abs(velocity) < ayuBubbleBaseSpeed {
            let sign: CGFloat = velocity == 0.0 ? (self.angularVelocity >= 0.0 ? 1.0 : -1.0) : (velocity > 0.0 ? 1.0 : -1.0)
            velocity = sign * ayuBubbleBaseSpeed
        }
        self.angularVelocity = velocity
    }

    private func releaseDrag() {
        if let bubble = self.draggedBubble {
            bubble.liftTarget = 0.0
            self.draggedBubble = nil
        }
    }

    private func setFront(_ bubble: Bubble, _ front: Bool) {
        if bubble.isFront == front {
            return
        }
        bubble.isFront = front
        bubble.container.removeFromSuperlayer()
        if front {
            self.layer.addSublayer(bubble.container)
        } else {
            self.backView.layer.addSublayer(bubble.container)
        }
    }

    private func render(dt: Double) {
        guard let layout = self.currentLayout else {
            return
        }
        let motion = AyuGramProfileBubblesView.motionAllowed
        let step = CGFloat(dt)
        let advancing = motion && dt > 0.0
        if advancing {
            self.time += dt
            if !self.isSpinning {
                let target: CGFloat = self.angularVelocity >= 0.0 ? ayuBubbleBaseSpeed : -ayuBubbleBaseSpeed
                self.angularVelocity += (target - self.angularVelocity) * (1.0 - exp(-step * 0.9))
                self.phase += self.angularVelocity * step
            }
            self.updateFallbackBeat(now: CACurrentMediaTime())
            self.beatEnvelope *= exp(-step * 6.0)
        }
        let fullTurn: CGFloat = 2.0 * CGFloat.pi
        if abs(self.phase) > fullTurn * 64.0 {
            self.phase = self.phase.truncatingRemainder(dividingBy: fullTurn)
        }

        let t = CGFloat(self.time)
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let collapse = ayuBubbleClamp(layout.collapseFraction, 0.0, 1.0)
        let avatarRadius = max(24.0, layout.avatarDiameter / 2.0)
        let orbitX = min(layout.size.width * 0.43, avatarRadius * 3.4)
        let orbitY = avatarRadius * 1.45
        self.lastOrbitRadius = orbitX
        let cosPitch = cos(ayuBubblePitch)
        let sinPitch = sin(ayuBubblePitch)
        let baseRadius = ayuBubbleClamp(layout.avatarDiameter, 60.0, 120.0) * 0.24
        let shrink = 1.0 - collapse * 0.6
        let collapseAlpha = ayuBubbleClamp(1.0 - collapse * 1.7, 0.0, 1.0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let rimAlpha: CGFloat = layout.showsAvatarRim && self.hasItems ? ayuBubbleClamp(1.0 - collapse * 2.2, 0.0, 1.0) : 0.0
        self.rimContainer.opacity = Float(rimAlpha)
        if rimAlpha > 0.0 {
            let rimRadius = layout.avatarDiameter / 2.0
            let rimFrame = CGRect(x: layout.avatarCenter.x - rimRadius - 6.0, y: layout.avatarCenter.y - rimRadius - 6.0, width: rimRadius * 2.0 + 12.0, height: rimRadius * 2.0 + 12.0)
            if rimFrame.size != self.rimAppliedFrame.size {
                let localBounds = CGRect(origin: CGPoint(), size: rimFrame.size)
                let ringPath = CGPath(ellipseIn: localBounds.insetBy(dx: 6.6, dy: 6.6), transform: nil)
                self.rimGlow.frame = localBounds
                self.rimGlow.path = ringPath
                self.rimGradient.bounds = localBounds
                self.rimGradient.position = CGPoint(x: localBounds.midX, y: localBounds.midY)
                self.rimMask.frame = localBounds
                self.rimMask.path = ringPath
            }
            if rimFrame != self.rimAppliedFrame {
                self.rimAppliedFrame = rimFrame
                self.rimContainer.frame = rimFrame
            }
            if self.rimAppliedDark != layout.isDark {
                self.rimAppliedDark = layout.isDark
                self.rimGlow.strokeColor = (layout.isDark ? UIColor(red: 0.55, green: 0.72, blue: 1.0, alpha: 0.2) : UIColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.16)).cgColor
            }
            if motion {
                self.rimGradient.setAffineTransform(CGAffineTransform(rotationAngle: t * 0.22))
            }
        }

        var hasRemoved = false
        for bubble in self.bubbles {
            if advancing {
                if bubble.removing {
                    bubble.appear = max(0.0, bubble.appear - step * 2.2)
                } else {
                    bubble.appear = min(1.0, bubble.appear + step * 1.4)
                }
                let hopAcceleration = -170.0 * bubble.hop - 13.0 * bubble.hopVelocity
                bubble.hopVelocity += hopAcceleration * step
                bubble.hop += bubble.hopVelocity * step
                bubble.tapPulse = max(0.0, bubble.tapPulse - step * 3.2)
            } else if !motion {
                bubble.appear = bubble.removing ? 0.0 : 1.0
                bubble.hop = 0.0
                bubble.hopVelocity = 0.0
                bubble.tapPulse = 0.0
            }
            if bubble.removing && bubble.appear <= 0.0 {
                hasRemoved = true
            }

            let longitude = self.phase + bubble.longitudeOffset
            let cosLatitude = cos(bubble.latitude)
            let sinLatitude = sin(bubble.latitude)
            let x = orbitX * bubble.orbitScale * cosLatitude * sin(longitude)
            let up = orbitY * bubble.orbitScale * sinLatitude
            let z = orbitX * bubble.orbitScale * cosLatitude * cos(longitude)
            let screenY = -up * cosPitch + z * sinPitch
            let depth = z * cosPitch + up * sinPitch
            let normalizedDepth = ayuBubbleClamp(depth / max(1.0, orbitX), -1.0, 1.0)
            bubble.depth = normalizedDepth

            let floatX: CGFloat = motion ? 3.5 * sin(t * 0.7 + bubble.phase1) : 0.0
            let floatY: CGFloat = motion ? 4.5 * sin(t * 0.9 + bubble.phase2) : 0.0
            let perspective = 1.0 + 0.07 * normalizedDepth
            var center = CGPoint(
                x: layout.avatarCenter.x + (x * perspective + floatX) * shrink,
                y: layout.avatarCenter.y + (screenY + floatY + bubble.hop) * shrink - collapse * 30.0
            )

            let appear = ayuBubbleSmooth(bubble.appear)
            let depthScale = 1.0 + 0.26 * normalizedDepth
            let beatScale = 1.0 + 0.1 * self.beatEnvelope * bubble.beatGain + min(0.12, abs(bubble.hop) * 0.012)
            var radius = baseRadius * bubble.sizeScale * depthScale * beatScale * ayuBubbleLerp(0.35, 1.0, appear) * (1.0 - collapse * 0.5)
            var alpha = appear * ayuBubbleLerp(0.62, 1.0, (normalizedDepth + 1.0) * 0.5) * collapseAlpha

            if bubble.lift > 0.0 || bubble.liftTarget > 0.0 {
                if bubble === self.draggedBubble {
                    if advancing {
                        let ax = (self.dragTarget.x - bubble.dragCenter.x) * 260.0 - bubble.dragVelocity.x * 20.0
                        let ay = (self.dragTarget.y - bubble.dragCenter.y) * 260.0 - bubble.dragVelocity.y * 20.0
                        bubble.dragVelocity.x += ax * step
                        bubble.dragVelocity.y += ay * step
                        bubble.dragCenter.x += bubble.dragVelocity.x * step
                        bubble.dragCenter.y += bubble.dragVelocity.y * step
                    } else if !motion {
                        bubble.dragCenter = self.dragTarget
                    }
                }
                if advancing {
                    let rate: CGFloat = bubble.liftTarget > bubble.lift ? 10.0 : 5.5
                    bubble.lift += (bubble.liftTarget - bubble.lift) * (1.0 - exp(-step * rate))
                } else if !motion {
                    bubble.lift = bubble.liftTarget
                }
                if bubble.liftTarget <= 0.0 && bubble.lift < 0.002 {
                    bubble.lift = 0.0
                }
                let lift = ayuBubbleSmooth(bubble.lift)
                let liftFloatX: CGFloat = motion ? 2.5 * sin(t * 2.1 + bubble.phase1) : 0.0
                let liftFloatY: CGFloat = motion ? 3.0 * sin(t * 1.7 + bubble.phase2) : 0.0
                center.x = ayuBubbleLerp(center.x, bubble.dragCenter.x + liftFloatX, lift)
                center.y = ayuBubbleLerp(center.y, bubble.dragCenter.y + liftFloatY, lift)
                radius = ayuBubbleLerp(radius, baseRadius * bubble.sizeScale * 2.5, lift)
                alpha = ayuBubbleLerp(alpha, 1.0, lift)
            }
            radius *= 1.0 - 0.14 * sin(bubble.tapPulse * CGFloat.pi)

            if advancing && bubble.hasLastCenter {
                let vx = (center.x - bubble.lastCenter.x) / step
                let vy = (center.y - bubble.lastCenter.y) / step
                bubble.screenVelocity.x += (vx - bubble.screenVelocity.x) * 0.3
                bubble.screenVelocity.y += (vy - bubble.screenVelocity.y) * 0.3
            } else if !motion {
                bubble.screenVelocity = CGPoint()
            }
            bubble.lastCenter = center
            bubble.hasLastCenter = true

            bubble.displayCenter = center
            bubble.displayRadius = radius
            bubble.displayAlpha = alpha

            self.setFront(bubble, normalizedDepth >= 0.0 || bubble.lift > 0.0 || bubble.liftTarget > 0.0)

            bubble.applyAppearance(isDark: layout.isDark, lowPower: lowPower)

            let hidden = alpha < 0.005
            if bubble.container.isHidden != hidden {
                bubble.container.isHidden = hidden
            }
            if hidden {
                continue
            }

            let scale = radius / ayuBubbleDesignRadius
            let speed = hypot(bubble.screenVelocity.x, bubble.screenVelocity.y)
            let stretch: CGFloat = motion ? min(0.14, speed / 1800.0) : 0.0
            let wobble: CGFloat = motion ? 0.03 * sin(t * bubble.wobbleSpeed + bubble.phase3) * (1.0 + 0.6 * self.beatEnvelope) : 0.0
            let angle: CGFloat = speed > 1.0 ? atan2(bubble.screenVelocity.y, bubble.screenVelocity.x) : 0.0
            var transform = CATransform3DMakeRotation(angle, 0.0, 0.0, 1.0)
            transform = CATransform3DScale(transform, scale * (1.0 + stretch + wobble), scale * (1.0 - stretch * 0.6 - wobble), 1.0)
            transform = CATransform3DRotate(transform, -angle, 0.0, 0.0, 1.0)

            bubble.container.position = center
            bubble.container.transform = transform
            bubble.container.opacity = Float(alpha)
            bubble.container.zPosition = bubble.lift > 0.0 ? 10000.0 + bubble.lift : 100.0 + normalizedDepth * 50.0
            if motion {
                bubble.shapeLayer.setAffineTransform(CGAffineTransform(rotationAngle: 0.25 * sin(t * 0.3 + bubble.phase3)))
                let bob: CGFloat = 1.6 * sin(t * 1.3 + bubble.phase1)
                bubble.stickerLayer.position = CGPoint(x: ayuBubbleDesignSide / 2.0, y: ayuBubbleDesignSide / 2.0 + bob)
            }
        }

        CATransaction.commit()

        if hasRemoved {
            var index = self.bubbles.count - 1
            while index >= 0 {
                let bubble = self.bubbles[index]
                if bubble.removing && bubble.appear <= 0.0 {
                    if bubble === self.draggedBubble {
                        self.draggedBubble = nil
                    }
                    bubble.container.removeFromSuperlayer()
                    self.bubbles.remove(at: index)
                }
                index -= 1
            }
        }
    }

    private func bubble(at point: CGPoint, frontOnly: Bool, backOnly: Bool) -> Bubble? {
        var result: Bubble?
        var resultRank: CGFloat = -CGFloat.greatestFiniteMagnitude
        for bubble in self.bubbles where !bubble.removing && bubble.displayAlpha > 0.3 && !bubble.container.isHidden {
            if frontOnly && !bubble.isFront {
                continue
            }
            if backOnly && bubble.isFront {
                continue
            }
            let distance = hypot(point.x - bubble.displayCenter.x, point.y - bubble.displayCenter.y)
            if distance <= bubble.displayRadius * 1.05 {
                let rank = (bubble.isFront ? 1000.0 : 0.0) + bubble.depth + bubble.lift * 10.0
                if rank > resultRank {
                    result = bubble
                    resultRank = rank
                }
            }
        }
        return result
    }

    public func backBubbleContains(_ point: CGPoint) -> Bool {
        if self.alpha <= 0.01 || self.isHidden {
            return false
        }
        return self.bubble(at: point, frontOnly: false, backOnly: true) != nil
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.bubble(at: point, frontOnly: true, backOnly: false) != nil
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view !== self {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        if self.draggedBubble != nil {
            return false
        }
        return self.bubble(at: gestureRecognizer.location(in: self), frontOnly: false, backOnly: false) != nil
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state, self.draggedBubble == nil, let bubble = self.bubble(at: recognizer.location(in: self), frontOnly: false, backOnly: false) else {
            return
        }
        if AyuGramProfileBubblesView.motionAllowed {
            bubble.tapPulse = 1.0
        }
        self.action?(bubble.item)
    }

    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            guard let bubble = self.bubble(at: location, frontOnly: false, backOnly: false) else {
                return
            }
            self.draggedBubble = bubble
            bubble.liftTarget = 1.0
            bubble.dragCenter = bubble.displayCenter
            bubble.dragVelocity = CGPoint()
            self.dragOffset = CGPoint(x: bubble.displayCenter.x - location.x, y: bubble.displayCenter.y - location.y)
            self.dragTarget = bubble.displayCenter
            self.setFront(bubble, true)
            let haptic: HapticFeedback
            if let current = self.hapticFeedback {
                haptic = current
            } else {
                haptic = HapticFeedback()
                self.hapticFeedback = haptic
            }
            haptic.impact(.light)
        case .changed:
            guard self.draggedBubble != nil else {
                return
            }
            self.dragTarget = CGPoint(x: location.x + self.dragOffset.x * 0.6, y: location.y + self.dragOffset.y * 0.6)
        case .ended, .cancelled, .failed:
            self.releaseDrag()
        default:
            break
        }
        self.updateRunning()
        if self.link == nil || (self.link?.isPaused ?? true) {
            self.render(dt: 0.0)
        }
    }

    public override var accessibilityElements: [Any]? {
        get {
            var elements: [AyuBubbleAccessibilityElement] = []
            var validIds = Set<String>()
            let sorted = self.bubbles.filter { !$0.removing && $0.copyIndex == 0 && $0.displayAlpha > 0.3 }.sorted(by: { lhs, rhs in
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

    public func update(size: CGSize, center: CGPoint, radius: CGFloat, isDark: Bool, dimsBackground: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradientLayer.frame = CGRect(origin: CGPoint(), size: size)
        if dimsBackground {
            self.gradientLayer.colors = [
                UIColor(white: 0.0, alpha: 0.3).cgColor,
                UIColor(white: 0.0, alpha: 0.2).cgColor,
                UIColor(white: 0.0, alpha: 0.1).cgColor
            ]
        } else if isDark {
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
