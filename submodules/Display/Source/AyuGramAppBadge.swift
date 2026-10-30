import SGSimpleSettings
import UIKit

private func ayuPlane(_ rect: CGRect, foreground: UIColor, secondary: UIColor) {
    let shapes: [([(CGFloat, CGFloat)], UIColor)] = [
        ([(0.02, 0.65), (0.43, 0.02), (0.45, 0.02), (0.31, 0.65)], foreground),
        ([(0.36, 0.69), (0.46, 0.30), (0.48, 0.28), (0.48, 0.98)], foreground),
        ([(0.56, 0.02), (0.59, 0.02), (0.99, 0.65), (0.72, 0.65)], secondary),
        ([(0.54, 0.28), (0.57, 0.31), (0.68, 0.69), (0.54, 0.98)], secondary)
    ]
    for (points, color) in shapes {
        let path = UIBezierPath()
        for (index, point) in points.enumerated() {
            let value = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: value) } else { path.addLine(to: value) }
        }
        path.close()
        color.setFill()
        path.fill()
    }
}

public func ayuGramOwnerBadgeImage() -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
        let seal = UIBezierPath()
        for index in 0 ..< 32 {
            let angle = CGFloat(index) * .pi / 16 - .pi / 2
            let radius: CGFloat = index % 2 == 0 ? 10.8 : 9.6
            let point = CGPoint(x: 11 + cos(angle) * radius, y: 11 + sin(angle) * radius)
            if index == 0 { seal.move(to: point) } else { seal.addLine(to: point) }
        }
        seal.close()
        UIColor(red: 0.56, green: 0.38, blue: 0.95, alpha: 1).setFill()
        seal.fill()
        ayuPlane(CGRect(x: 4.5, y: 4.2, width: 13, height: 13), foreground: .white, secondary: UIColor(red: 0.85, green: 0.77, blue: 1, alpha: 1))
    }
}

private func ayuBadgeColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> UIColor {
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
}

private struct AyuBadgeStyle {
    var colors: [UIColor]
    var foreground: UIColor
    var secondary: UIColor
    var text: UIColor
    var watermark: CGFloat
    var dots: [UIColor]
    var dotRadius: ClosedRange<CGFloat>
    var dotCount: Int
    var glow: UIColor?
}

private func ayuBadgeStyle(_ name: String) -> AyuBadgeStyle {
    switch name {
    case "SkyAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.25, 0.42, 0.97), ayuBadgeColor(0.36, 0.62, 1.0)], foreground: .white, secondary: ayuBadgeColor(0.80, 0.88, 1), text: .white, watermark: 0.12, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.22))
    case "NightAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.04, 0.05, 0.18), ayuBadgeColor(0.10, 0.12, 0.32)], foreground: ayuBadgeColor(0.64, 0.52, 1), secondary: ayuBadgeColor(1, 0.56, 0.82), text: .white, watermark: 0, dots: [ayuBadgeColor(1, 1, 1, 0.75), ayuBadgeColor(1, 0.60, 0.85, 0.8), ayuBadgeColor(0.65, 0.60, 1, 0.8)], dotRadius: 0.3 ... 0.7, dotCount: 34, glow: nil)
    case "TitaniumAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.03, 0.03, 0.04), ayuBadgeColor(0.20, 0.20, 0.22), ayuBadgeColor(0.07, 0.07, 0.08)], foreground: ayuBadgeColor(0.62, 0.62, 0.64), secondary: ayuBadgeColor(0.42, 0.42, 0.45), text: ayuBadgeColor(0.86, 0.86, 0.88), watermark: 0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.08))
    case "ProAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.44, 0.24, 0.98), ayuBadgeColor(0.70, 0.30, 0.62), ayuBadgeColor(0.96, 0.42, 0.20)], foreground: .white, secondary: ayuBadgeColor(1, 0.86, 0.76), text: .white, watermark: 0.12, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    case "DayAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(1, 0.91, 0.95), ayuBadgeColor(0.89, 0.88, 1)], foreground: ayuBadgeColor(0.60, 0.40, 0.98), secondary: ayuBadgeColor(1, 0.45, 0.62), text: ayuBadgeColor(0.45, 0.30, 0.92), watermark: 0, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: ayuBadgeColor(1, 1, 1, 0.5))
    case "DuckyAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.02, 0.02, 0.02), ayuBadgeColor(0.08, 0.05, 0.03)], foreground: ayuBadgeColor(1, 0.85, 0.22), secondary: ayuBadgeColor(1, 0.60, 0.10), text: .white, watermark: 0, dots: [ayuBadgeColor(0.62, 0.32, 0.10, 0.85), ayuBadgeColor(0.45, 0.22, 0.08, 0.85)], dotRadius: 0.5 ... 1.1, dotCount: 26, glow: nil)
    case "SparklingAppBadge":
        return AyuBadgeStyle(colors: [ayuBadgeColor(0.08, 0.08, 0.40), ayuBadgeColor(0.20, 0.18, 0.72), ayuBadgeColor(0.08, 0.08, 0.40)], foreground: ayuBadgeColor(0.56, 0.58, 1), secondary: ayuBadgeColor(0.82, 0.82, 1), text: .white, watermark: 0, dots: [ayuBadgeColor(1, 1, 1, 0.85), ayuBadgeColor(0.75, 0.80, 1, 0.8)], dotRadius: 0.3 ... 0.8, dotCount: 30, glow: ayuBadgeColor(0.55, 0.55, 1, 0.35))
    default:
        let color: UIColor
        switch AyuGramIconSettings.selectedName ?? UIApplication.shared.alternateIconName {
        case "AyuRed": color = ayuBadgeColor(0.91, 0.15, 0.17)
        case "AyuPurple": color = ayuBadgeColor(0.50, 0.25, 0.96)
        default: color = ayuBadgeColor(0.19, 0.15, 0.28)
        }
        return AyuBadgeStyle(colors: [color, color], foreground: .white, secondary: ayuBadgeColor(0.83, 0.73, 1), text: .white, watermark: 0.2, dots: [], dotRadius: 0 ... 0, dotCount: 0, glow: nil)
    }
}

public let ayuGramAppBadgeStyles: [(name: String, title: String)] = [
    ("Components/AppBadge", "Default"),
    ("SkyAppBadge", "Sky"),
    ("NightAppBadge", "Night"),
    ("TitaniumAppBadge", "Titanium"),
    ("ProAppBadge", "Pro"),
    ("DayAppBadge", "Day"),
    ("DuckyAppBadge", "Ducky"),
    ("SparklingAppBadge", "Sparkling")
]

public func ayuGramAppBadgeImage(style: String, scale: CGFloat) -> UIImage {
    let style = ayuBadgeStyle(style)
    let base = CGSize(width: 108, height: 23)
    let format = UIGraphicsImageRendererFormat.preferred()
    if scale > 0 {
        format.scale = scale
    }
    return UIGraphicsImageRenderer(size: base, format: format).image { renderer in
        let context = renderer.cgContext
        let capsule = UIBezierPath(roundedRect: CGRect(origin: .zero, size: base), cornerRadius: base.height / 2)
        context.saveGState()
        capsule.addClip()
        let cgColors = style.colors.map { $0.cgColor } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: base.width, y: base.height), options: [])
        }
        if let glow = style.glow, let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [glow.cgColor, glow.withAlphaComponent(0).cgColor] as CFArray, locations: nil) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: base.height * 0.6), options: [])
        }
        var seed: UInt32 = 0x41595547
        func next() -> CGFloat {
            seed = seed &* 1664525 &+ 1013904223
            return CGFloat(seed >> 8) / CGFloat(1 << 24)
        }
        for index in 0 ..< style.dotCount {
            let radius = style.dotRadius.lowerBound + (style.dotRadius.upperBound - style.dotRadius.lowerBound) * next()
            let point = CGPoint(x: next() * base.width, y: next() * base.height)
            style.dots[index % style.dots.count].setFill()
            UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        if style.watermark > 0 {
            ayuPlane(CGRect(x: -3, y: -10, width: 116, height: 45), foreground: UIColor.black.withAlphaComponent(style.watermark), secondary: UIColor.black.withAlphaComponent(style.watermark * 0.65))
        }
        context.restoreGState()
        ayuPlane(CGRect(x: 7, y: 3, width: 17, height: 17), foreground: style.foreground, secondary: style.secondary)
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: style.text]
        let text = "AYUGRAM" as NSString
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: 28, y: (base.height - textSize.height) / 2), withAttributes: attributes)
    }
}

func ayuGramAppBadgeImage() -> UIImage {
    return ayuGramAppBadgeImage(style: UserDefaults.standard.string(forKey: "customAppBadge") ?? "", scale: 0)
}

public func ayuGramSettingsIcon() -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 29, height: 29)).image { _ in
        UIColor(red: 0.19, green: 0.15, blue: 0.28, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 29, height: 29), cornerRadius: 7).fill()
        ayuPlane(CGRect(x: 5, y: 5, width: 19, height: 19), foreground: .white, secondary: UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1))
    }
}

/// Sharp, larger variant of the settings icon for headers.
public func ayuGramLargeIcon(size: CGFloat) -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
        UIColor(red: 0.19, green: 0.15, blue: 0.28, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerRadius: size * 0.24).fill()
        let inset = size * 5.0 / 29.0
        ayuPlane(CGRect(x: inset, y: inset, width: size - inset * 2.0, height: size - inset * 2.0), foreground: .white, secondary: UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1))
    }
}

public func ayuGramMemberBadgeImage() -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
        let outline = UIBezierPath(roundedRect: CGRect(x: 2, y: 2, width: 18, height: 18), cornerRadius: 6)
        UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1).setStroke()
        outline.lineWidth = 1.2
        outline.stroke()
        ayuPlane(CGRect(x: 5, y: 4.5, width: 12, height: 13), foreground: .white, secondary: UIColor(red: 0.76, green: 0.65, blue: 1, alpha: 1))
    }
}
