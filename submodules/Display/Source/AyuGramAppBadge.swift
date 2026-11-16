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
    return ayuSealBadgeImage(fill: UIColor(red: 0.56, green: 0.38, blue: 0.95, alpha: 1), secondary: UIColor(red: 0.85, green: 0.77, blue: 1, alpha: 1))
}

public func ayuGramChannelBadgeImage() -> UIImage {
    return ayuSealBadgeImage(fill: UIColor(red: 0.90, green: 0.18, blue: 0.20, alpha: 1), secondary: UIColor(red: 1, green: 0.78, blue: 0.78, alpha: 1))
}

private func ayuSealBadgeImage(fill: UIColor, secondary: UIColor) -> UIImage {
    return UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
        let seal = UIBezierPath()
        for index in 0 ..< 32 {
            let angle = CGFloat(index) * .pi / 16 - .pi / 2
            let radius: CGFloat = index % 2 == 0 ? 10.8 : 9.6
            let point = CGPoint(x: 11 + cos(angle) * radius, y: 11 + sin(angle) * radius)
            if index == 0 { seal.move(to: point) } else { seal.addLine(to: point) }
        }
        seal.close()
        fill.setFill()
        seal.fill()
        ayuPlane(CGRect(x: 4.5, y: 4.2, width: 13, height: 13), foreground: .white, secondary: secondary)
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

/// Swiftgram's original badges, kept as images; their stored name has this prefix.
public let swiftgramAppBadgePrefix = "SG:"

/// Loads a bundled image by its asset name; set by the app window.
public var ayuGramBundleImageLoader: ((String) -> UIImage?)?

public let swiftgramAppBadgeStyles: [(name: String, title: String)] = [
    ("SG:Components/AppBadge", "Default"),
    ("SG:SkyAppBadge", "Sky"),
    ("SG:NightAppBadge", "Night"),
    ("SG:TitaniumAppBadge", "Titanium"),
    ("SG:ProAppBadge", "Pro"),
    ("SG:DayAppBadge", "Day"),
    ("SG:DuckyAppBadge", "Ducky"),
    ("SG:SparklingAppBadge", "Sparkling")
]

public func ayuGramAppBadgeImage(style: String, scale: CGFloat) -> UIImage {
    if style.hasPrefix(swiftgramAppBadgePrefix), let image = ayuGramBundleImageLoader?(String(style.dropFirst(swiftgramAppBadgePrefix.count))) {
        return image
    }
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
    let personal = AyuGramPersonalization.shared.settings
    if personal.appBadgeEnabled {
        return ayuGramCustomAppBadgeImage(personal, scale: 0)
    }
    return ayuGramAppBadgeImage(style: UserDefaults.standard.string(forKey: "customAppBadge") ?? "", scale: 0)
}

public func ayuGramCustomAppBadgeImage(_ settings: AyuGramPersonalizationSettings, scale: CGFloat) -> UIImage {
    let text = String(settings.appBadgeText.prefix(18)) as NSString
    let textColor: UIColor = settings.appBadgeDarkText ? UIColor(white: 0.08, alpha: 1.0) : .white
    let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: textColor]
    let textSize = text.length == 0 ? CGSize() : text.size(withAttributes: attributes)
    var picture: UIImage?
    if settings.appBadgeShowsIcon, let url = AyuGramPersonalization.shared.appBadgeImageURL {
        picture = UIImage(contentsOfFile: url.path)
    }
    let hasIcon = settings.appBadgeShowsIcon
    let iconWidth: CGFloat = hasIcon ? 17.0 : 0.0
    var width: CGFloat = 8.0 + iconWidth + 8.0
    if text.length > 0 {
        width = (hasIcon ? 7.0 + iconWidth + 4.0 : 10.0) + ceil(textSize.width) + 10.0
    }
    let base = CGSize(width: max(31.0, width), height: 23)
    let format = UIGraphicsImageRendererFormat.preferred()
    if scale > 0 {
        format.scale = scale
    }
    return UIGraphicsImageRenderer(size: base, format: format).image { renderer in
        let context = renderer.cgContext
        let capsule = UIBezierPath(roundedRect: CGRect(origin: .zero, size: base), cornerRadius: base.height / 2)
        context.saveGState()
        capsule.addClip()
        let colors = [ayuHexColor(settings.appBadgeTop).cgColor, ayuHexColor(settings.appBadgeBottom).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: base.width, y: base.height), options: [])
        }
        context.restoreGState()
        if hasIcon {
            let iconRect = CGRect(x: text.length > 0 ? 7.0 : (base.width - 17.0) / 2.0, y: 3, width: 17, height: 17)
            if let picture {
                context.saveGState()
                UIBezierPath(ovalIn: iconRect).addClip()
                let side = min(picture.size.width, picture.size.height)
                let ratio = 17.0 / max(1.0, side)
                let drawSize = CGSize(width: picture.size.width * ratio, height: picture.size.height * ratio)
                picture.draw(in: CGRect(x: iconRect.midX - drawSize.width / 2.0, y: iconRect.midY - drawSize.height / 2.0, width: drawSize.width, height: drawSize.height))
                context.restoreGState()
            } else {
                ayuPlane(iconRect, foreground: textColor, secondary: textColor.withAlphaComponent(0.7))
            }
        }
        if text.length > 0 {
            text.draw(at: CGPoint(x: hasIcon ? 28.0 : 10.0, y: (base.height - textSize.height) / 2), withAttributes: attributes)
        }
    }
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

private func ayuHexColor(_ hex: String) -> UIColor {
    var value: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))).scanHexInt64(&value)
    return UIColor(red: CGFloat((value >> 16) & 0xff) / 255.0, green: CGFloat((value >> 8) & 0xff) / 255.0, blue: CGFloat(value & 0xff) / 255.0, alpha: 1.0)
}

private var ayuCustomBadgeCache: [String: UIImage] = [:]
private let ayuCustomBadgeLock = NSLock()

public func ayuGramCustomBadgeImage(_ badge: AyuGramCustomBadge, size: CGFloat = 22.0) -> UIImage {
    let key = "\(badge.symbol)|\(badge.emoji)|\(badge.shape)|\(badge.top)|\(badge.bottom)|\(badge.darkGlyph)|\(size)"
    ayuCustomBadgeLock.lock()
    let cached = ayuCustomBadgeCache[key]
    ayuCustomBadgeLock.unlock()
    if let cached {
        return cached
    }
    let scale = size / 22.0
    let top = ayuHexColor(badge.top)
    let bottom = ayuHexColor(badge.bottom)
    let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
        let rect = CGRect(x: 1.5 * scale, y: 1.5 * scale, width: 19.0 * scale, height: 19.0 * scale)
        var path: UIBezierPath?
        switch badge.shape {
        case 1:
            path = UIBezierPath(ovalIn: rect)
        case 2:
            let seal = UIBezierPath()
            for index in 0 ..< 32 {
                let angle = CGFloat(index) * .pi / 16.0 - .pi / 2.0
                let radius = (index % 2 == 0 ? 10.8 : 9.6) * scale
                let point = CGPoint(x: size / 2.0 + cos(angle) * radius, y: size / 2.0 + sin(angle) * radius)
                if index == 0 { seal.move(to: point) } else { seal.addLine(to: point) }
            }
            seal.close()
            path = seal
        case 3:
            path = nil
        default:
            path = UIBezierPath(roundedRect: rect, cornerRadius: 6.0 * scale)
        }
        if let path {
            context.cgContext.saveGState()
            path.addClip()
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size), options: [])
            }
            context.cgContext.restoreGState()
        }
        let glyphColor: UIColor = path == nil ? top : (badge.darkGlyph ? UIColor(white: 0.08, alpha: 1.0) : .white)
        let emoji = badge.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        if !emoji.isEmpty {
            let font = UIFont.systemFont(ofSize: (path == nil ? 17.0 : 12.5) * scale)
            let text = NSAttributedString(string: String(emoji.prefix(2)), attributes: [.font: font])
            let bounds = text.boundingRect(with: CGSize(width: size * 2.0, height: size * 2.0), options: [.usesLineFragmentOrigin], context: nil)
            text.draw(at: CGPoint(x: (size - bounds.width) / 2.0, y: (size - bounds.height) / 2.0))
        } else if !badge.symbol.isEmpty {
            let pointSize = (path == nil ? 16.0 : 11.0) * scale
            if let symbol = UIImage(systemName: badge.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold))?.withTintColor(glyphColor, renderingMode: .alwaysOriginal) {
                let symbolSize = symbol.size
                symbol.draw(in: CGRect(x: (size - symbolSize.width) / 2.0, y: (size - symbolSize.height) / 2.0, width: symbolSize.width, height: symbolSize.height))
            }
        }
    }
    ayuCustomBadgeLock.lock()
    if ayuCustomBadgeCache.count > 400 {
        ayuCustomBadgeCache.removeAll()
    }
    ayuCustomBadgeCache[key] = image
    ayuCustomBadgeLock.unlock()
    return image
}

public func ayuGramBadgeImage(kind: String?, peerId: Int64) -> UIImage {
    switch kind {
    case "member":
        return ayuGramMemberBadgeImage()
    case "supporter":
        if let badge = AyuGramClientBadges.shared.supporterBadge(peerId: peerId) {
            return ayuGramCustomBadgeImage(badge)
        }
        return ayuGramMemberBadgeImage()
    case "updates", "peek":
        return ayuGramChannelBadgeImage()
    default:
        return ayuGramOwnerBadgeImage()
    }
}

private weak var ayuBadgeToastView: UIView?

public func ayuGramShowBadgeToast(markdown: String, from view: UIView) {
    guard let window = view.window else {
        return
    }
    ayuBadgeToastView?.removeFromSuperview()
    let text = NSMutableAttributedString()
    let regular = UIFont.systemFont(ofSize: 14.0)
    let bold = UIFont.systemFont(ofSize: 14.0, weight: .semibold)
    for (index, part) in markdown.components(separatedBy: "**").enumerated() where !part.isEmpty {
        text.append(NSAttributedString(string: part, attributes: [.font: index % 2 == 1 ? bold : regular, .foregroundColor: UIColor.white]))
    }
    let container = UIView()
    container.backgroundColor = UIColor(white: 0.12, alpha: 0.96)
    container.layer.cornerRadius = 14.0
    container.layer.cornerCurve = .continuous
    container.layer.shadowColor = UIColor.black.cgColor
    container.layer.shadowOpacity = 0.25
    container.layer.shadowRadius = 12.0
    container.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)
    container.isUserInteractionEnabled = false
    let icon = UIImageView(image: ayuGramOwnerBadgeImage())
    let label = UILabel()
    label.numberOfLines = 0
    label.attributedText = text
    container.addSubview(icon)
    container.addSubview(label)
    let width = min(window.bounds.width - 24.0, 420.0)
    let labelSize = label.sizeThatFits(CGSize(width: width - 56.0, height: 200.0))
    let height = max(48.0, ceil(labelSize.height) + 24.0)
    icon.frame = CGRect(x: 14.0, y: (height - 22.0) / 2.0, width: 22.0, height: 22.0)
    label.frame = CGRect(x: 46.0, y: (height - ceil(labelSize.height)) / 2.0, width: width - 56.0, height: ceil(labelSize.height))
    container.frame = CGRect(x: (window.bounds.width - width) / 2.0, y: window.bounds.height - window.safeAreaInsets.bottom - height - 70.0, width: width, height: height)
    window.addSubview(container)
    ayuBadgeToastView = container
    container.alpha = 0.0
    container.transform = CGAffineTransform(translationX: 0.0, y: 16.0)
    UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [], animations: {
        container.alpha = 1.0
        container.transform = .identity
    }, completion: { _ in
        UIView.animate(withDuration: 0.3, delay: 3.2, options: [], animations: {
            container.alpha = 0.0
        }, completion: { _ in
            container.removeFromSuperview()
        })
    })
}
