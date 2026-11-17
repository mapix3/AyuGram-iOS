import Foundation
import UIKit
import Display
import SGSimpleSettings

enum AyuGramParticleImages {
    private static var cache: [AyuGramEffectsSettings.Particles: UIImage] = [:]

    static func image(for style: AyuGramEffectsSettings.Particles) -> UIImage? {
        if let cached = self.cache[style] {
            return cached
        }
        let image: UIImage?
        switch style {
        case .off:
            image = nil
        case .snow:
            image = self.softDot()
        case .stars:
            image = self.sparkle()
        case .fireflies:
            image = self.firefly()
        case .petals:
            image = self.petal()
        case .bubbles:
            image = self.bubble()
        }
        if let image = image {
            self.cache[style] = image
        }
        return image
    }

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
        return UIColor(red: r, green: g, blue: b, alpha: a).cgColor
    }

    private static func radialGradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient? {
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)
    }

    private static func softDot() -> UIImage? {
        return generateImage(CGSize(width: 16.0, height: 16.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            guard let gradient = self.radialGradient([
                self.color(1.0, 1.0, 1.0, 1.0),
                self.color(1.0, 1.0, 1.0, 0.85),
                self.color(1.0, 1.0, 1.0, 0.0)
            ], [0.0, 0.45, 1.0]) else {
                return
            }
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: size.width / 2.0, options: [])
        })
    }

    private static func sparkle() -> UIImage? {
        return generateImage(CGSize(width: 22.0, height: 22.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            let radius = size.width / 2.0
            if let glow = self.radialGradient([
                self.color(1.0, 1.0, 1.0, 0.55),
                self.color(1.0, 1.0, 1.0, 0.0)
            ], [0.0, 1.0]) {
                context.drawRadialGradient(glow, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: radius * 0.55, options: [])
            }
            let k = radius * 0.16
            context.beginPath()
            context.move(to: CGPoint(x: center.x, y: center.y - radius))
            context.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + k, y: center.y - k))
            context.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + k, y: center.y + k))
            context.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - k, y: center.y + k))
            context.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - k, y: center.y - k))
            context.closePath()
            context.setFillColor(self.color(1.0, 1.0, 1.0, 1.0))
            context.fillPath()
        })
    }

    private static func firefly() -> UIImage? {
        return generateImage(CGSize(width: 28.0, height: 28.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            guard let gradient = self.radialGradient([
                self.color(1.0, 0.98, 0.78, 1.0),
                self.color(0.88, 1.0, 0.45, 0.6),
                self.color(0.6, 0.9, 0.3, 0.0)
            ], [0.0, 0.22, 1.0]) else {
                return
            }
            let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0.0, endCenter: center, endRadius: size.width / 2.0, options: [])
        })
    }

    private static func petal() -> UIImage? {
        return generateImage(CGSize(width: 24.0, height: 16.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            let w = size.width
            let h = size.height
            context.beginPath()
            context.move(to: CGPoint(x: 0.5, y: h / 2.0))
            context.addCurve(to: CGPoint(x: w - 0.5, y: h / 2.0), control1: CGPoint(x: w * 0.3, y: 0.0), control2: CGPoint(x: w * 0.8, y: h * 0.15))
            context.addCurve(to: CGPoint(x: 0.5, y: h / 2.0), control1: CGPoint(x: w * 0.8, y: h * 0.85), control2: CGPoint(x: w * 0.3, y: h))
            context.closePath()
            context.clip()
            guard let gradient = self.radialGradient([
                self.color(1.0, 0.68, 0.78, 1.0),
                self.color(1.0, 0.9, 0.93, 1.0)
            ], [0.0, 1.0]) else {
                return
            }
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: h / 2.0), end: CGPoint(x: w, y: h / 2.0), options: [])
        })
    }

    private static func bubble() -> UIImage? {
        return generateImage(CGSize(width: 28.0, height: 28.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            let rect = CGRect(origin: CGPoint(), size: size).insetBy(dx: 1.5, dy: 1.5)
            context.setFillColor(self.color(1.0, 1.0, 1.0, 0.08))
            context.fillEllipse(in: rect)
            context.setStrokeColor(self.color(1.0, 1.0, 1.0, 0.75))
            context.setLineWidth(1.2)
            context.strokeEllipse(in: rect)
            context.setFillColor(self.color(1.0, 1.0, 1.0, 0.8))
            context.fillEllipse(in: CGRect(x: size.width * 0.24, y: size.height * 0.2, width: size.width * 0.22, height: size.height * 0.14))
        })
    }
}
