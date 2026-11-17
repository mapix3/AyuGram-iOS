import Foundation
import UIKit

public protocol AyuGramBubbleEffectsHost: AnyObject {
    func ayuGramBubbleEffectsDidChange()
}

public enum AyuGramBubbleEffects {
    public static let glowRadius: CGFloat = 9.0
    public static let glowPadding: CGFloat = 16.0
    public static let glassFillAlpha: CGFloat = 0.74

    private static let hosts = NSHashTable<AnyObject>.weakObjects()
    private static var observer: AyuGramEffectsObserver?

    public static func register(_ host: AyuGramBubbleEffectsHost) {
        if self.observer == nil {
            self.observer = AyuGramEffectsRuntime.observe {
                for object in AyuGramBubbleEffects.hosts.allObjects {
                    (object as? AyuGramBubbleEffectsHost)?.ayuGramBubbleEffectsDidChange()
                }
            }
        }
        self.hosts.add(host)
    }

    public static func glowColor(fillColors: [UIColor], accentColor: UIColor, isDark: Bool) -> UIColor {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var count: CGFloat = 0.0
        for color in fillColors {
            var r: CGFloat = 0.0
            var g: CGFloat = 0.0
            var b: CGFloat = 0.0
            var a: CGFloat = 0.0
            if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
                red += r
                green += g
                blue += b
                count += 1.0
            }
        }
        let alpha: CGFloat = isDark ? 0.62 : 0.5

        var base = accentColor
        if count > 0.0 {
            base = UIColor(red: red / count, green: green / count, blue: blue / count, alpha: 1.0)
        }
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        var baseAlpha: CGFloat = 0.0
        guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &baseAlpha) else {
            return accentColor.withAlphaComponent(alpha)
        }
        if saturation < 0.08 {
            return accentColor.withAlphaComponent(alpha)
        }
        return UIColor(hue: hue, saturation: max(saturation, 0.55), brightness: min(max(brightness, 0.55), 0.95), alpha: alpha)
    }

    public static func glowImage(mask: UIImage, color: UIColor) -> UIImage? {
        let key = "glow:" + colorKey(color)
        if let cached = cache.image(mask: mask, key: key) {
            return cached
        }
        let padding = self.glowPadding
        let size = CGSize(width: mask.size.width + padding * 2.0, height: mask.size.height + padding * 2.0)
        let shapeRect = CGRect(origin: CGPoint(x: padding, y: padding), size: mask.size)
        guard size.width > 0.0, size.height > 0.0, let tintedShape = tinted(mask: mask, color: color.withAlphaComponent(1.0)) else {
            return nil
        }
        let image = renderer(size: size, scale: mask.scale).image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(offset: CGSize(), blur: self.glowRadius, color: color.cgColor)
            tintedShape.draw(in: shapeRect)
            cgContext.setShadow(offset: CGSize(), blur: 0.0, color: nil)
            mask.draw(in: shapeRect, blendMode: .destinationOut, alpha: 1.0)
        }
        let capInsets = mask.capInsets
        let result = image.resizableImage(withCapInsets: UIEdgeInsets(top: capInsets.top + padding, left: capInsets.left + padding, bottom: capInsets.bottom + padding, right: capInsets.right + padding), resizingMode: .stretch)
        cache.store(mask: mask, key: key, image: result)
        return result
    }

    public static func glassHighlightImage(mask: UIImage, isDark: Bool) -> UIImage? {
        let key = isDark ? "glass:dark" : "glass:light"
        if let cached = cache.image(mask: mask, key: key) {
            return cached
        }
        let size = mask.size
        guard size.width > 0.0, size.height > 0.0 else {
            return nil
        }
        let rect = CGRect(origin: CGPoint(), size: size)
        let fadeHeight = max(4.0, min(size.height, mask.capInsets.top))
        let line: CGFloat = 1.0

        let borderAlpha: CGFloat = isDark ? 0.12 : 0.4
        let topAlpha: CGFloat = isDark ? 0.32 : 0.75
        let sheenAlpha: CGFloat = isDark ? 0.07 : 0.2

        let format = renderer(size: size, scale: mask.scale)
        let white = UIColor.white

        let eroded = format.image { _ in
            mask.draw(in: rect)
            for offset in [CGPoint(x: 0.0, y: line), CGPoint(x: 0.0, y: -line), CGPoint(x: line, y: 0.0), CGPoint(x: -line, y: 0.0)] {
                mask.draw(in: rect.offsetBy(dx: offset.x, dy: offset.y), blendMode: .destinationIn, alpha: 1.0)
            }
        }
        let border = format.image { context in
            mask.draw(in: rect)
            eroded.draw(in: rect, blendMode: .destinationOut, alpha: 1.0)
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(white.cgColor)
            context.cgContext.fill(rect)
        }
        let topEdge = format.image { context in
            mask.draw(in: rect)
            mask.draw(in: rect.offsetBy(dx: 0.0, dy: line), blendMode: .destinationOut, alpha: 1.0)
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(white.cgColor)
            context.cgContext.fill(rect)
            context.cgContext.setBlendMode(.destinationIn)
            drawVerticalFade(context: context.cgContext, height: fadeHeight)
        }
        let sheen = format.image { context in
            drawVerticalFade(context: context.cgContext, height: fadeHeight)
            mask.draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
        }
        let image = format.image { _ in
            sheen.draw(in: rect, blendMode: .normal, alpha: sheenAlpha)
            border.draw(in: rect, blendMode: .normal, alpha: borderAlpha)
            topEdge.draw(in: rect, blendMode: .normal, alpha: topAlpha)
        }
        let result = image.resizableImage(withCapInsets: mask.capInsets, resizingMode: .stretch)
        cache.store(mask: mask, key: key, image: result)
        return result
    }

    private static func drawVerticalFade(context: CGContext, height: CGFloat) {
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) else {
            return
        }
        context.drawLinearGradient(gradient, start: CGPoint(), end: CGPoint(x: 0.0, y: height), options: [.drawsAfterEndLocation])
    }

    private static func tinted(mask: UIImage, color: UIColor) -> UIImage? {
        let rect = CGRect(origin: CGPoint(), size: mask.size)
        return renderer(size: mask.size, scale: mask.scale).image { context in
            mask.draw(in: rect)
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(color.cgColor)
            context.cgContext.fill(rect)
        }
    }

    private static func renderer(size: CGSize, scale: CGFloat) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static func colorKey(_ color: UIColor) -> String {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 0.0
        _ = color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "\(Int(r * 255.0)),\(Int(g * 255.0)),\(Int(b * 255.0)),\(Int(a * 255.0))"
    }

    private static let cache = ImageCache()

    private final class ImageCache {
        private struct Entry {
            weak var mask: UIImage?
            let key: String
            let image: UIImage
        }

        private let lock = NSLock()
        private var entries: [Entry] = []
        private let limit = 64

        func image(mask: UIImage, key: String) -> UIImage? {
            self.lock.lock()
            defer {
                self.lock.unlock()
            }
            for entry in self.entries {
                if entry.mask === mask && entry.key == key {
                    return entry.image
                }
            }
            return nil
        }

        func store(mask: UIImage, key: String, image: UIImage) {
            self.lock.lock()
            defer {
                self.lock.unlock()
            }
            self.entries.removeAll(where: { $0.mask == nil })
            if self.entries.count >= self.limit {
                self.entries.removeFirst(self.entries.count - self.limit + 1)
            }
            self.entries.append(Entry(mask: mask, key: key, image: image))
        }
    }
}
