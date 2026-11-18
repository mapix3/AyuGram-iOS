import Foundation
import UIKit

public protocol AyuGramBubbleEffectsHost: AnyObject {
    func ayuGramBubbleEffectsDidChange()
}

public enum AyuGramBubbleEffects {
    public static let glowRadius: CGFloat = 9.0
    public static let glowPadding: CGFloat = 16.0
    public static let glassFillAlpha: CGFloat = 0.46
    public static let glassBlurRadius: CGFloat = 14.0

    private static let hosts = NSHashTable<AnyObject>.weakObjects()
    private static var observer: AyuGramEffectsObserver?

    public static func register(_ host: AyuGramBubbleEffectsHost) {
        if self.observer == nil {
            self.observer = AyuGramEffectsRuntime.observe {
                AyuGramBubbleEffects.notifyHosts()
            }
        }
        self.hosts.add(host)
    }

    static func notifyHosts() {
        for object in self.hosts.allObjects {
            (object as? AyuGramBubbleEffectsHost)?.ayuGramBubbleEffectsDidChange()
        }
    }

    public static func glass(wallpaperNode: AnyObject?, fallbackIsDark: Bool) -> AyuGramWallpaperTint.Glass {
        return AyuGramWallpaperTint.glass(wallpaperColor: AyuGramWallpaperTint.color(for: wallpaperNode), fallbackIsDark: fallbackIsDark)
    }

    public static func glassTintImage(mask: UIImage) -> UIImage? {
        let key = "glassTint"
        if let cached = cache.image(mask: mask, key: key) {
            return cached
        }
        let size = mask.size
        guard size.width > 0.0, size.height > 0.0 else {
            return nil
        }
        let rect = CGRect(origin: CGPoint(), size: size)
        let image = renderer(size: size, scale: mask.scale).image { context in
            mask.draw(in: rect)
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(rect)
        }
        let result = image.resizableImage(withCapInsets: mask.capInsets, resizingMode: .stretch).withRenderingMode(.alwaysTemplate)
        cache.store(mask: mask, key: key, image: result)
        return result
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

    public static func glassHighlightImage(mask: UIImage, isDarkWallpaper: Bool) -> UIImage? {
        let key = isDarkWallpaper ? "liquidGlass:dark" : "liquidGlass:light"
        if let cached = cache.image(mask: mask, key: key) {
            return cached
        }
        let size = mask.size
        guard size.width > 0.0, size.height > 0.0 else {
            return nil
        }
        let rect = CGRect(origin: CGPoint(), size: size)
        let fadeHeight = max(6.0, min(size.height * 0.5, mask.capInsets.top + 4.0))
        let bottomFadeHeight = max(4.0, min(size.height * 0.4, mask.capInsets.bottom))
        let line: CGFloat = 1.0

        let rimAlpha: CGFloat = isDarkWallpaper ? 0.55 : 0.85
        let innerGlowAlpha: CGFloat = isDarkWallpaper ? 0.16 : 0.3
        let sheenAlpha: CGFloat = isDarkWallpaper ? 0.1 : 0.22
        let bottomAlpha: CGFloat = isDarkWallpaper ? 0.05 : 0.1

        let format = renderer(size: size, scale: mask.scale)
        let white = UIColor.white

        let eroded = erode(mask: mask, rect: rect, radius: line, format: format)
        let deepEroded = erode(mask: mask, rect: rect, radius: 3.0, format: format)

        let rim = format.image { context in
            mask.draw(in: rect)
            eroded.draw(in: rect, blendMode: .destinationOut, alpha: 1.0)
            context.cgContext.setBlendMode(.sourceIn)
            let colors = [
                white.cgColor,
                white.withAlphaComponent(0.18).cgColor,
                white.withAlphaComponent(0.08).cgColor,
                white.withAlphaComponent(0.55).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.4, 0.65, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(), end: CGPoint(x: size.width, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }
        let innerGlow = format.image { context in
            let cgContext = context.cgContext
            cgContext.setShadow(offset: CGSize(), blur: 4.0, color: white.cgColor)
            let ring = format.image { ringContext in
                mask.draw(in: rect)
                deepEroded.draw(in: rect, blendMode: .destinationOut, alpha: 1.0)
                ringContext.cgContext.setBlendMode(.sourceIn)
                ringContext.cgContext.setFillColor(white.cgColor)
                ringContext.cgContext.fill(rect)
            }
            ring.draw(in: rect)
            cgContext.setShadow(offset: CGSize(), blur: 0.0, color: nil)
            mask.draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
        }
        let sheen = format.image { context in
            drawVerticalFade(context: context.cgContext, height: fadeHeight)
            mask.draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
        }
        let bottom = format.image { context in
            drawVerticalFade(context: context.cgContext, from: size.height, height: -bottomFadeHeight)
            mask.draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
        }
        let image = format.image { _ in
            sheen.draw(in: rect, blendMode: .normal, alpha: sheenAlpha)
            bottom.draw(in: rect, blendMode: .normal, alpha: bottomAlpha)
            innerGlow.draw(in: rect, blendMode: .normal, alpha: innerGlowAlpha)
            rim.draw(in: rect, blendMode: .normal, alpha: rimAlpha)
        }
        let result = image.resizableImage(withCapInsets: mask.capInsets, resizingMode: .stretch)
        cache.store(mask: mask, key: key, image: result)
        return result
    }

    private static func erode(mask: UIImage, rect: CGRect, radius: CGFloat, format: UIGraphicsImageRenderer) -> UIImage {
        return format.image { _ in
            mask.draw(in: rect)
            var step: CGFloat = 1.0
            while step <= radius {
                for angle in stride(from: 0.0, to: CGFloat.pi * 2.0, by: CGFloat.pi / 4.0) {
                    let offset = CGPoint(x: cos(angle) * step, y: sin(angle) * step)
                    mask.draw(in: rect.offsetBy(dx: offset.x, dy: offset.y), blendMode: .destinationIn, alpha: 1.0)
                }
                step += 1.0
            }
        }
    }

    private static func drawVerticalFade(context: CGContext, from origin: CGFloat = 0.0, height: CGFloat) {
        let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) else {
            return
        }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: origin), end: CGPoint(x: 0.0, y: origin + height), options: [.drawsAfterEndLocation])
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
