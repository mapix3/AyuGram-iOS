import Foundation
import UIKit
import QuartzCore
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
}

public final class AyuGramDeleteEffectLayer: CALayer {
    public var becameEmpty: (() -> Void)?

    private var activeItemCount: Int = 0

    public var hasActiveItems: Bool {
        return self.activeItemCount > 0
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

    public func addItem(frame: CGRect, image: UIImage, style: AyuGramEffectsSettings.DeleteStyle) -> Bool {
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

        CATransaction.commit()

        self.activeItemCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime + 0.05, execute: { [weak self, weak container] in
            container?.removeFromSuperlayer()
            guard let self else {
                return
            }
            self.activeItemCount -= 1
            if self.activeItemCount == 0 {
                self.becameEmpty?()
            }
        })
        return true
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
