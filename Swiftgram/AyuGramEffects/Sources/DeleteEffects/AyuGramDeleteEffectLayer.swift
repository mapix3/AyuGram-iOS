import Foundation
import UIKit
import QuartzCore
import Display
import SGSimpleSettings

public enum AyuGramDeleteEffect {
    public static var currentStyle: AyuGramEffectsSettings.DeleteStyle {
        let style = AyuGramEffectsRuntime.settings.activeDeleteStyle
        if style != .standard && !AyuGramEffectsRuntime.motionAllowed {
            return .standard
        }
        return style
    }

    public static func usesCustomLayer(_ style: AyuGramEffectsSettings.DeleteStyle) -> Bool {
        switch style {
        case .burn, .shatter, .implode:
            return true
        case .standard, .dust:
            return false
        }
    }

    public static func collapseDelay(_ style: AyuGramEffectsSettings.DeleteStyle) -> Double {
        let fadeStart = self.fadeStart(style)
        if fadeStart <= 0.0 {
            return 0.0
        }
        return fadeStart + self.fadeOutDuration * 0.5
    }

    static func fadeStart(_ style: AyuGramEffectsSettings.DeleteStyle) -> Double {
        switch style {
        case .burn:
            return AyuGramBurnDeleteEffect.collapseDelay
        case .shatter:
            return AyuGramShatterDeleteEffect.collapseDelay
        case .implode:
            return AyuGramImplodeDeleteEffect.collapseDelay
        case .standard, .dust:
            return 0.0
        }
    }

    public static func collapseDuration(_ style: AyuGramEffectsSettings.DeleteStyle) -> Double {
        switch style {
        case .burn, .shatter, .implode:
            return 0.34
        case .standard, .dust:
            return 0.8
        }
    }

    static let fadeOutDuration: Double = 0.3
}

public final class AyuGramDeleteEffectLayer: CALayer {
    private final class Item {
        let container: CALayer
        let track: (() -> CGRect?)?
        var isTracking: Bool

        init(container: CALayer, track: (() -> CGRect?)?) {
            self.container = container
            self.track = track
            self.isTracking = track != nil
        }
    }

    public var becameEmpty: (() -> Void)?

    private var items: [Item] = []
    private var displayLink: SharedDisplayLinkDriver.Link?

    public var hasActiveItems: Bool {
        return !self.items.isEmpty
    }

    override public init() {
        super.init()
    }

    override public init(layer: Any) {
        super.init(layer: layer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.displayLink?.invalidate()
    }

    public func addItem(frame: CGRect, image: UIImage, style: AyuGramEffectsSettings.DeleteStyle, track: (() -> CGRect?)? = nil) -> Bool {
        guard frame.width >= 1.0, frame.height >= 1.0, let cgImage = image.cgImage else {
            return false
        }
        guard AyuGramDeleteEffect.usesCustomLayer(style) else {
            return false
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let container = CALayer()
        container.frame = frame
        self.addSublayer(container)

        let lifetime: Double
        switch style {
        case .burn:
            lifetime = AyuGramBurnDeleteEffect.run(in: container, image: cgImage, imageScale: image.scale)
        case .shatter:
            lifetime = AyuGramShatterDeleteEffect.run(in: container, image: cgImage, imageScale: image.scale)
        case .implode:
            lifetime = AyuGramImplodeDeleteEffect.run(in: container, image: cgImage, imageScale: image.scale)
        case .standard, .dust:
            lifetime = 0.0
        }

        let fadeStart = AyuGramDeleteEffect.fadeStart(style)
        let fadeDuration = AyuGramDeleteEffect.fadeOutDuration
        let effectiveLifetime: Double
        if fadeStart > 0.0 && fadeStart + fadeDuration < lifetime {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0 as NSNumber
            fade.toValue = 0.0 as NSNumber
            fade.duration = fadeDuration
            fade.beginTime = container.convertTime(CACurrentMediaTime(), from: nil) + fadeStart
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0.0, 0.55, 1.0)
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            container.add(fade, forKey: "ayuDeleteFadeOut")
            effectiveLifetime = fadeStart + fadeDuration
        } else {
            effectiveLifetime = lifetime
        }

        CATransaction.commit()

        let item = Item(container: container, track: track)
        self.items.append(item)
        self.updateDisplayLink()

        DispatchQueue.main.asyncAfter(deadline: .now() + effectiveLifetime + 0.05, execute: { [weak self, weak item] in
            guard let self, let item else {
                return
            }
            self.removeItem(item)
        })
        return true
    }

    public func stopTracking() {
        if !self.items.contains(where: { $0.isTracking }) {
            return
        }
        self.updateTracking()
        for item in self.items {
            item.isTracking = false
        }
        self.updateDisplayLink()
    }

    private func removeItem(_ item: Item) {
        guard let index = self.items.firstIndex(where: { $0 === item }) else {
            return
        }
        self.items.remove(at: index)
        item.container.removeFromSuperlayer()
        self.updateDisplayLink()
        if self.items.isEmpty {
            self.becameEmpty?()
        }
    }

    private func updateDisplayLink() {
        let needsLink = self.items.contains(where: { $0.isTracking })
        if needsLink {
            if self.displayLink == nil {
                self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max, { [weak self] _ in
                    self?.updateTracking()
                })
            }
        } else if let displayLink = self.displayLink {
            self.displayLink = nil
            displayLink.invalidate()
        }
    }

    private func updateTracking() {
        var stoppedTracking = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in self.items where item.isTracking {
            guard let track = item.track, let rect = track() else {
                item.isTracking = false
                stoppedTracking = true
                continue
            }
            let position = CGPoint(x: rect.midX, y: rect.midY)
            if item.container.position != position {
                item.container.position = position
            }
        }
        CATransaction.commit()
        if stoppedTracking {
            self.updateDisplayLink()
        }
    }
}

enum AyuGramDeleteEffectSupport {
    static func radialGlowImage(diameter: Int, inner: UIColor, outer: UIColor) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: diameter, height: diameter, bitsPerComponent: 8, bytesPerRow: diameter * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let colors = [inner.cgColor, outer.cgColor, outer.withAlphaComponent(0.0).cgColor] as CFArray
        let locations: [CGFloat] = [0.0, 0.35, 1.0]
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
            return nil
        }
        let center = CGPoint(x: CGFloat(diameter) / 2.0, y: CGFloat(diameter) / 2.0)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: CGFloat(diameter) / 2.0, options: [])
        return context.makeImage()
    }

    static func rgbaBytes(image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        return success ? bytes : nil
    }

    static func makeImage(width: Int, height: Int, bytes: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    static func byte(_ value: Float) -> UInt8 {
        return UInt8(max(0, min(255, Int(value * 255.0))))
    }
}
