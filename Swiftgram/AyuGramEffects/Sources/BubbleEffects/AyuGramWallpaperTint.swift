import Foundation
import UIKit

public enum AyuGramWallpaperTint {
    public struct Glass: Equatable {
        public let tint: UIColor
        public let isDarkWallpaper: Bool

        public static func ==(lhs: Glass, rhs: Glass) -> Bool {
            return lhs.isDarkWallpaper == rhs.isDarkWallpaper && lhs.tint.isEqual(rhs.tint)
        }
    }

    private static let colors = NSMapTable<AnyObject, UIColor>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    public static func color(for wallpaperNode: AnyObject?) -> UIColor? {
        guard let wallpaperNode else {
            return nil
        }
        return self.colors.object(forKey: wallpaperNode)
    }

    public static func update(color: UIColor?, for wallpaperNode: AnyObject) {
        let apply = {
            let previous = AyuGramWallpaperTint.colors.object(forKey: wallpaperNode)
            if let color {
                if let previous, AyuGramWallpaperTint.isClose(previous, color) {
                    return
                }
                AyuGramWallpaperTint.colors.setObject(color, forKey: wallpaperNode)
            } else {
                if previous == nil {
                    return
                }
                AyuGramWallpaperTint.colors.removeObject(forKey: wallpaperNode)
            }
            AyuGramWallpaperTint.scheduleNotify()
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private static var isNotifyScheduled = false

    private static func scheduleNotify() {
        if self.isNotifyScheduled {
            return
        }
        self.isNotifyScheduled = true
        DispatchQueue.main.async {
            AyuGramWallpaperTint.isNotifyScheduled = false
            AyuGramBubbleEffects.notifyHosts()
        }
    }

    public static func averageColor(rgb values: [UInt32], invertedPattern: Bool) -> UIColor? {
        if values.isEmpty {
            return nil
        }
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        for value in values {
            red += CGFloat((value >> 16) & 0xff) / 255.0
            green += CGFloat((value >> 8) & 0xff) / 255.0
            blue += CGFloat(value & 0xff) / 255.0
        }
        let count = CGFloat(values.count)
        let average = UIColor(red: red / count, green: green / count, blue: blue / count, alpha: 1.0)
        if invertedPattern {
            return self.mix(average, UIColor.black, 0.82)
        }
        return average
    }

    public static func averageColor(image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let side = 8
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(side), height: CGFloat(side)))
            return true
        }
        if !drawn {
            return nil
        }
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var weight: CGFloat = 0.0
        for index in 0 ..< side * side {
            let alpha = CGFloat(bytes[index * 4 + 3]) / 255.0
            if alpha <= 0.01 {
                continue
            }
            red += CGFloat(bytes[index * 4]) / 255.0
            green += CGFloat(bytes[index * 4 + 1]) / 255.0
            blue += CGFloat(bytes[index * 4 + 2]) / 255.0
            weight += alpha
        }
        if weight <= 0.0 {
            return nil
        }
        return UIColor(red: min(1.0, red / weight), green: min(1.0, green / weight), blue: min(1.0, blue / weight), alpha: 1.0)
    }

    public static func glass(wallpaperColor: UIColor?, fallbackIsDark: Bool) -> Glass {
        guard let wallpaperColor, let components = self.components(wallpaperColor) else {
            if fallbackIsDark {
                return Glass(tint: UIColor(white: 1.0, alpha: 0.14), isDarkWallpaper: true)
            } else {
                return Glass(tint: UIColor(white: 0.0, alpha: 0.08), isDarkWallpaper: false)
            }
        }
        let luminance = 0.2126 * components.r + 0.7152 * components.g + 0.0722 * components.b
        let isDark = luminance < 0.5
        var base = wallpaperColor
        var hue: CGFloat = 0.0
        var saturation: CGFloat = 0.0
        var brightness: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        if base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
            base = UIColor(hue: hue, saturation: min(1.0, saturation * 1.15), brightness: brightness, alpha: 1.0)
        }
        if isDark {
            let lift = 0.55 + (0.5 - luminance) * 0.4
            let tint = self.mix(base, UIColor.white, lift)
            return Glass(tint: tint.withAlphaComponent(0.2 + (0.5 - luminance) * 0.16), isDarkWallpaper: true)
        } else {
            let depth = 0.45 + (luminance - 0.5) * 0.4
            let tint = self.mix(base, UIColor.black, depth)
            return Glass(tint: tint.withAlphaComponent(0.13 + (luminance - 0.5) * 0.14), isDarkWallpaper: false)
        }
    }

    static func mix(_ a: UIColor, _ b: UIColor, _ fraction: CGFloat) -> UIColor {
        guard let ca = self.components(a), let cb = self.components(b) else {
            return a
        }
        let t = max(0.0, min(1.0, fraction))
        return UIColor(red: ca.r + (cb.r - ca.r) * t, green: ca.g + (cb.g - ca.g) * t, blue: ca.b + (cb.b - ca.b) * t, alpha: 1.0)
    }

    private static func components(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 0.0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (max(0.0, min(1.0, r)), max(0.0, min(1.0, g)), max(0.0, min(1.0, b)))
        }
        var white: CGFloat = 0.0
        if color.getWhite(&white, alpha: &a) {
            return (white, white, white)
        }
        return nil
    }

    private static func isClose(_ a: UIColor, _ b: UIColor) -> Bool {
        guard let ca = self.components(a), let cb = self.components(b) else {
            return false
        }
        return abs(ca.r - cb.r) < 0.004 && abs(ca.g - cb.g) < 0.004 && abs(ca.b - cb.b) < 0.004
    }
}
