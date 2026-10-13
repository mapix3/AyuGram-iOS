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

func ayuGramAppBadgeImage() -> UIImage {
    let color: UIColor
    switch AyuGramIconSettings.selectedName ?? UIApplication.shared.alternateIconName {
    case "AyuRed": color = UIColor(red: 0.91, green: 0.15, blue: 0.17, alpha: 1)
    case "AyuPurple": color = UIColor(red: 0.50, green: 0.25, blue: 0.96, alpha: 1)
    default: color = UIColor(red: 0.19, green: 0.15, blue: 0.28, alpha: 1)
    }
    let size = CGSize(width: 108, height: 23)
    return UIGraphicsImageRenderer(size: size).image { renderer in
        let capsule = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 11.5)
        color.setFill()
        capsule.fill()
        renderer.cgContext.saveGState()
        capsule.addClip()
        ayuPlane(CGRect(x: -3, y: -10, width: 116, height: 45), foreground: UIColor.black.withAlphaComponent(0.20), secondary: UIColor.black.withAlphaComponent(0.13))
        renderer.cgContext.restoreGState()
        ayuPlane(CGRect(x: 7, y: 3, width: 17, height: 17), foreground: .white, secondary: UIColor(red: 0.83, green: 0.73, blue: 1, alpha: 1))
        ("AYUGRAM" as NSString).draw(at: CGPoint(x: 28, y: 4), withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: UIColor.white])
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
