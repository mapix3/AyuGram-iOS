import Foundation
import UIKit

private let ayuSnowmanViewBox = CGRect(x: 15.0, y: 24.0, width: 70.0, height: 62.0)
private let ayuSnowmanEase = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0)

private func ayuColor(_ hex: UInt32, _ alpha: CGFloat = 1.0) -> UIColor {
    return UIColor(red: CGFloat((hex >> 16) & 0xff) / 255.0, green: CGFloat((hex >> 8) & 0xff) / 255.0, blue: CGFloat(hex & 0xff) / 255.0, alpha: alpha)
}

private struct AyuSnowmanStep {
    var dx: CGFloat = 0.0
    var dy: CGFloat = 0.0
    var rotation: CGFloat = 0.0
    var sx: CGFloat = 1.0
    var sy: CGFloat = 1.0
    var opacity: Float = 1.0
    var offset: Double
}

final class AyuGramSnowman {
    enum State {
        case building
        case standing
        case wrecked
        case melting
        case gone
    }

    let container = CALayer()
    private let unit: CGFloat
    private var parts: [String: CALayer] = [:]
    private var timers: [DispatchWorkItem] = []
    private(set) var state: State = .building
    private var bodyGone = false
    private var headGone = false
    var onGone: ((Bool) -> Void)?
    var onThrow: ((CGPoint) -> Void)?
    var throwsSnowballs = true

    init(width: CGFloat) {
        self.unit = width / ayuSnowmanViewBox.width
        self.container.bounds = CGRect(origin: CGPoint(), size: CGSize(width: ayuSnowmanViewBox.width * self.unit, height: ayuSnowmanViewBox.height * self.unit))
        self.makeParts()
    }

    var size: CGSize {
        return self.container.bounds.size
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let origin = CGPoint(x: self.container.position.x - self.size.width / 2.0, y: self.container.position.y - self.size.height / 2.0)
        return CGPoint(x: origin.x + (x - ayuSnowmanViewBox.minX) * self.unit, y: origin.y + (y - ayuSnowmanViewBox.minY) * self.unit)
    }

    func hitPart(at location: CGPoint) -> Bool? {
        guard self.state == .standing || self.state == .wrecked else {
            return nil
        }
        let head = self.point(50.0, 40.0)
        let body = self.point(50.0, 67.0)
        let headRadius = 13.0 * self.unit
        let bodyRadius = 18.0 * self.unit
        if !self.headGone, hypot(location.x - head.x, location.y - (head.y + (self.bodyGone ? 32.0 * self.unit : 0.0))) < headRadius + 6.0 {
            return false
        }
        if !self.bodyGone, hypot(location.x - body.x, location.y - body.y) < bodyRadius + 6.0 {
            return true
        }
        return nil
    }

    private func render(_ box: CGRect, _ draw: (CGContext) -> Void) -> CALayer {
        let layer = CALayer()
        let unit = self.unit
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let size = CGSize(width: box.width * unit, height: box.height * unit)
        let image = UIGraphicsImageRenderer(size: size, format: format).image(actions: { rendererContext in
            let context = rendererContext.cgContext
            context.scaleBy(x: unit, y: unit)
            context.translateBy(x: -box.minX, y: -box.minY)
            draw(context)
        })
        layer.contents = image.cgImage
        layer.contentsScale = image.scale
        layer.frame = CGRect(x: (box.minX - ayuSnowmanViewBox.minX) * unit, y: (box.minY - ayuSnowmanViewBox.minY) * unit, width: size.width, height: size.height)
        return layer
    }

    private func setAnchor(_ layer: CALayer, _ anchor: CGPoint) {
        let frame = layer.frame
        layer.anchorPoint = anchor
        layer.frame = frame
    }

    private static func ball(_ context: CGContext, center: CGPoint, radius: CGFloat) {
        context.saveGState()
        context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2.0, height: radius * 2.0))
        context.clip()
        let colors = [ayuColor(0xFFFFFF).cgColor, ayuColor(0xF1F5FC).cgColor, ayuColor(0xA7B9DA).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0]) {
            let start = CGPoint(x: center.x - radius + radius * 2.0 * 0.36, y: center.y - radius + radius * 2.0 * 0.3)
            context.drawRadialGradient(gradient, startCenter: start, startRadius: 0.0, endCenter: start, endRadius: radius * 2.0 * 0.8, options: [.drawsAfterEndLocation])
        }
        context.restoreGState()
    }

    private func makeParts() {
        let armColor = ayuColor(0x755236).cgColor
        let armL = self.render(CGRect(x: 18.5, y: 48.0, width: 18.0, height: 15.5), { context in
            context.setStrokeColor(armColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 35.0, y: 62.0))
            context.addLine(to: CGPoint(x: 20.0, y: 52.0))
            context.move(to: CGPoint(x: 26.5, y: 56.3))
            context.addLine(to: CGPoint(x: 22.5, y: 49.6))
            context.strokePath()
        })
        self.setAnchor(armL, CGPoint(x: 1.0, y: 1.0))
        let armR = self.render(CGRect(x: 63.5, y: 44.3, width: 18.0, height: 18.2), { context in
            context.setStrokeColor(armColor)
            context.setLineWidth(2.0)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 65.0, y: 61.0))
            context.addLine(to: CGPoint(x: 80.0, y: 49.0))
            context.move(to: CGPoint(x: 75.6, y: 52.5))
            context.addLine(to: CGPoint(x: 77.8, y: 45.8))
            context.strokePath()
        })
        self.setAnchor(armR, CGPoint(x: 0.0, y: 1.0))
        let body = self.render(CGRect(x: 33.0, y: 50.0, width: 34.0, height: 34.0), { context in
            AyuGramSnowman.ball(context, center: CGPoint(x: 50.0, y: 67.0), radius: 17.0)
        })
        let neck = self.render(CGRect(x: 40.5, y: 48.9, width: 19.0, height: 5.2), { context in
            context.setFillColor(ayuColor(0x1C2C48, 0.16).cgColor)
            context.fillEllipse(in: CGRect(x: 40.5, y: 48.9, width: 19.0, height: 5.2))
        })
        let head = self.render(CGRect(x: 38.0, y: 28.0, width: 24.0, height: 24.0), { context in
            AyuGramSnowman.ball(context, center: CGPoint(x: 50.0, y: 40.0), radius: 12.0)
        })
        let coal = ayuColor(0x2B2A2B).cgColor
        let buttons = self.render(CGRect(x: 48.5, y: 59.5, width: 3.0, height: 15.0), { context in
            context.setFillColor(coal)
            for y in [61.0, 67.0, 73.0] as [CGFloat] {
                context.fillEllipse(in: CGRect(x: 48.5, y: y - 1.5, width: 3.0, height: 3.0))
            }
        })
        let scarf = self.render(CGRect(x: 37.5, y: 49.3, width: 25.0, height: 11.2), { context in
            context.setFillColor(ayuColor(0xDB2129).cgColor)
            context.move(to: CGPoint(x: 38.5, y: 49.5))
            context.addQuadCurve(to: CGPoint(x: 61.5, y: 49.5), control: CGPoint(x: 50.0, y: 55.0))
            context.addLine(to: CGPoint(x: 62.3, y: 54.2))
            context.addQuadCurve(to: CGPoint(x: 37.7, y: 54.2), control: CGPoint(x: 50.0, y: 60.2))
            context.closePath()
            context.fillPath()
        })
        let tail = self.render(CGRect(x: 53.0, y: 54.0, width: 8.8, height: 18.8), { context in
            context.setFillColor(ayuColor(0xB81B24).cgColor)
            context.move(to: CGPoint(x: 53.5, y: 54.8))
            context.addLine(to: CGPoint(x: 59.6, y: 54.2))
            context.addLine(to: CGPoint(x: 61.2, y: 69.0))
            context.addLine(to: CGPoint(x: 55.4, y: 69.8))
            context.closePath()
            context.fillPath()
            context.setStrokeColor(ayuColor(0xF7FAFF).cgColor)
            context.setLineWidth(1.0)
            context.move(to: CGPoint(x: 54.6, y: 61.6))
            context.addLine(to: CGPoint(x: 60.3, y: 61.1))
            context.move(to: CGPoint(x: 55.0, y: 64.8))
            context.addLine(to: CGPoint(x: 60.7, y: 64.3))
            context.strokePath()
            context.setStrokeColor(ayuColor(0xB81B24).cgColor)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 56.0, y: 69.6))
            context.addLine(to: CGPoint(x: 55.8, y: 72.2))
            context.move(to: CGPoint(x: 58.0, y: 69.4))
            context.addLine(to: CGPoint(x: 58.0, y: 72.0))
            context.move(to: CGPoint(x: 60.0, y: 69.2))
            context.addLine(to: CGPoint(x: 60.3, y: 71.8))
            context.strokePath()
        })
        self.setAnchor(tail, CGPoint(x: 0.5, y: 0.0))
        let eyes = self.render(CGRect(x: 43.9, y: 34.4, width: 11.7, height: 3.7), { context in
            context.setFillColor(coal)
            context.fillEllipse(in: CGRect(x: 43.9, y: 34.9, width: 3.2, height: 3.2))
            context.fillEllipse(in: CGRect(x: 52.4, y: 34.4, width: 3.2, height: 3.2))
        })
        let smile = self.render(CGRect(x: 44.4, y: 45.2, width: 10.7, height: 3.0), { context in
            context.setFillColor(coal)
            for (x, y) in [(45.2, 46.0), (47.9, 47.2), (51.2, 47.4), (54.3, 46.5)] as [(CGFloat, CGFloat)] {
                context.fillEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
            }
        })
        let carrot = self.render(CGRect(x: 51.0, y: 41.0, width: 16.0, height: 4.4), { context in
            context.setFillColor(ayuColor(0xFF8724).cgColor)
            context.move(to: CGPoint(x: 51.0, y: 41.0))
            context.addLine(to: CGPoint(x: 67.0, y: 44.0))
            context.addLine(to: CGPoint(x: 51.0, y: 45.4))
            context.closePath()
            context.fillPath()
            context.setStrokeColor(ayuColor(0xD9661A).cgColor)
            context.setLineWidth(0.55)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: 56.0, y: 41.9))
            context.addLine(to: CGPoint(x: 56.4, y: 44.6))
            context.move(to: CGPoint(x: 60.5, y: 42.8))
            context.addLine(to: CGPoint(x: 60.8, y: 44.6))
            context.strokePath()
        })
        self.setAnchor(carrot, CGPoint(x: 0.0, y: 0.5))
        let ordered: [(String, CALayer)] = [("armL", armL), ("armR", armR), ("body", body), ("neck", neck), ("head", head), ("buttons", buttons), ("scarf", scarf), ("tail", tail), ("eyes", eyes), ("smile", smile), ("carrot", carrot)]
        for (name, layer) in ordered {
            self.parts[name] = layer
            self.container.addSublayer(layer)
        }
    }

    private func transform(_ step: AyuSnowmanStep) -> CATransform3D {
        var value = CATransform3DMakeTranslation(step.dx * self.unit, step.dy * self.unit, 0.0)
        value = CATransform3DRotate(value, step.rotation * .pi / 180.0, 0.0, 0.0, 1.0)
        value = CATransform3DScale(value, step.sx, step.sy, 1.0)
        return value
    }

    private func animate(_ name: String, _ steps: [AyuSnowmanStep], duration: Double, delay: Double = 0.0, timing: CAMediaTimingFunction = ayuSnowmanEase, keepEnd: Bool = true) {
        guard let layer = self.parts[name], let last = steps.last else {
            return
        }
        let begin = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        let move = CAKeyframeAnimation(keyPath: "transform")
        move.values = steps.map { NSValue(caTransform3D: self.transform($0)) }
        move.keyTimes = steps.map { NSNumber(value: $0.offset) }
        move.timingFunctions = Array(repeating: timing, count: max(1, steps.count - 1))
        move.duration = duration
        move.beginTime = begin
        move.fillMode = .backwards
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = steps.map { NSNumber(value: $0.opacity) }
        fade.keyTimes = move.keyTimes
        fade.duration = duration
        fade.beginTime = begin
        fade.fillMode = .backwards
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if keepEnd {
            layer.transform = self.transform(last)
            layer.opacity = last.opacity
        }
        layer.add(move, forKey: "move" + String(Int.random(in: 0 ... 1_000_000)))
        layer.add(fade, forKey: "fade" + String(Int.random(in: 0 ... 1_000_000)))
        CATransaction.commit()
    }

    private func later(_ delay: Double, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        self.timers.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelTimers() {
        for item in self.timers {
            item.cancel()
        }
        self.timers = []
    }

    func build(melts: Bool) {
        self.state = .building
        let pop = [AyuSnowmanStep(sx: 0.0, sy: 0.0, offset: 0.0), AyuSnowmanStep(sx: 1.35, sy: 1.35, offset: 0.6), AyuSnowmanStep(offset: 1.0)]
        self.animate("body", [
            AyuSnowmanStep(dx: -58.0, rotation: -320.0, sx: 0.35, sy: 0.35, opacity: 0.0, offset: 0.0),
            AyuSnowmanStep(dx: -51.0, rotation: -282.0, sx: 0.43, sy: 0.43, opacity: 1.0, offset: 0.12),
            AyuSnowmanStep(offset: 1.0)
        ], duration: 1.05, timing: CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1.0))
        self.animate("head", [
            AyuSnowmanStep(dx: 52.0, dy: 33.0, rotation: 300.0, sx: 0.4, sy: 0.4, opacity: 0.0, offset: 0.0),
            AyuSnowmanStep(dx: 48.0, dy: 33.0, rotation: 270.0, sx: 0.46, sy: 0.46, opacity: 1.0, offset: 0.1),
            AyuSnowmanStep(dx: 15.0, dy: 33.0, offset: 0.55),
            AyuSnowmanStep(dx: 2.0, dy: -9.0, offset: 0.8),
            AyuSnowmanStep(offset: 1.0)
        ], duration: 1.3, delay: 0.45)
        self.animate("neck", [AyuSnowmanStep(opacity: 0.0, offset: 0.0), AyuSnowmanStep(offset: 1.0)], duration: 0.3, delay: 1.65)
        self.animate("scarf", [AyuSnowmanStep(sx: 0.0, opacity: 0.0, offset: 0.0), AyuSnowmanStep(offset: 1.0)], duration: 0.38, delay: 1.75)
        self.animate("tail", [AyuSnowmanStep(sy: 0.0, offset: 0.0), AyuSnowmanStep(offset: 1.0)], duration: 0.34, delay: 2.0)
        self.animate("buttons", pop, duration: 0.32, delay: 2.15)
        self.animate("eyes", pop, duration: 0.32, delay: 2.3)
        self.animate("smile", pop, duration: 0.32, delay: 2.45)
        self.animate("carrot", [AyuSnowmanStep(sx: 0.0, offset: 0.0), AyuSnowmanStep(sx: 1.18, offset: 0.7), AyuSnowmanStep(offset: 1.0)], duration: 0.36, delay: 2.6)
        self.animate("armL", [AyuSnowmanStep(rotation: 25.0, sx: 0.0, sy: 0.0, offset: 0.0), AyuSnowmanStep(offset: 1.0)], duration: 0.42, delay: 2.8)
        self.animate("armR", [AyuSnowmanStep(rotation: -25.0, sx: 0.0, sy: 0.0, offset: 0.0), AyuSnowmanStep(offset: 1.0)], duration: 0.42, delay: 2.9)
        self.later(3.35) { [weak self] in
            guard let self else {
                return
            }
            self.state = .standing
            self.wave()
            self.blink()
            self.scheduleThrow()
            if melts {
                self.later(38.0) { [weak self] in
                    self?.melt()
                }
            }
        }
    }

    private func wave() {
        guard self.state == .standing else {
            return
        }
        let steps = [0.0, -24.0, 4.0, -24.0, 4.0, 0.0].enumerated().map { index, angle in
            AyuSnowmanStep(rotation: CGFloat(angle), offset: Double(index) / 5.0)
        }
        self.animate("armR", steps, duration: 1.5, timing: CAMediaTimingFunction(name: .easeInEaseOut))
        self.later(6.5 + Double.random(in: 0.0 ... 3.0)) { [weak self] in
            self?.wave()
        }
    }

    private func blink() {
        guard self.state == .standing else {
            return
        }
        self.animate("eyes", [AyuSnowmanStep(offset: 0.0), AyuSnowmanStep(sy: 0.1, offset: 0.5), AyuSnowmanStep(offset: 1.0)], duration: 0.17, timing: CAMediaTimingFunction(name: .linear))
        self.later(2.8 + Double.random(in: 0.0 ... 3.5)) { [weak self] in
            self?.blink()
        }
    }

    private func scheduleThrow() {
        self.later(14.0 + Double.random(in: 0.0 ... 12.0)) { [weak self] in
            guard let self, self.state == .standing else {
                return
            }
            if self.throwsSnowballs {
                self.animate("armR", [AyuSnowmanStep(offset: 0.0), AyuSnowmanStep(rotation: 40.0, offset: 0.35), AyuSnowmanStep(rotation: -55.0, offset: 0.6), AyuSnowmanStep(offset: 1.0)], duration: 0.7, timing: CAMediaTimingFunction(name: .easeInEaseOut))
                self.later(0.38) { [weak self] in
                    guard let self, self.state == .standing else {
                        return
                    }
                    self.onThrow?(self.point(80.0, 49.0))
                }
            }
            self.scheduleThrow()
        }
    }

    func smash(body: Bool, burst: (CGPoint, CGFloat) -> Void) {
        guard self.state == .standing || self.state == .wrecked else {
            return
        }
        if body ? self.bodyGone : self.headGone {
            return
        }
        self.state = .wrecked
        self.cancelTimers()
        let drop: CGFloat = self.bodyGone ? 32.0 : 0.0
        let fly: (String, CGFloat, CGFloat, CGFloat, CGFloat) -> Void = { name, dx, dy, rotation, from in
            self.animate(name, [AyuSnowmanStep(dy: from, offset: 0.0), AyuSnowmanStep(dx: dx, dy: from + dy, rotation: rotation, opacity: 0.0, offset: 1.0)], duration: 0.8, timing: CAMediaTimingFunction(controlPoints: 0.3, 0.6, 0.6, 1.0))
        }
        let pop: (String, CGFloat) -> Void = { name, from in
            self.animate(name, [AyuSnowmanStep(dy: from, offset: 0.0), AyuSnowmanStep(dy: from, sx: 1.35, sy: 1.35, opacity: 0.0, offset: 1.0)], duration: 0.24, timing: CAMediaTimingFunction(name: .easeOut))
        }
        if body {
            self.bodyGone = true
            burst(self.point(50.0, 67.0), 17.0 * self.unit)
            pop("body", 0.0)
            fly("buttons", -6.0, 26.0, -40.0, 0.0)
            fly("armL", -16.0, 16.0, -120.0, 0.0)
            fly("armR", 16.0, 14.0, 130.0, 0.0)
            if !self.headGone {
                for name in ["head", "eyes", "smile", "carrot", "scarf", "tail", "neck"] {
                    let base = self.parts[name]?.transform ?? CATransform3DIdentity
                    let fall = [AyuSnowmanStep(offset: 0.0), AyuSnowmanStep(dy: 32.0, offset: 0.62), AyuSnowmanStep(dy: 26.0, offset: 0.8), AyuSnowmanStep(dy: 32.0, offset: 1.0)]
                    if CATransform3DIsIdentity(base) {
                        self.animate(name, fall, duration: 0.62, timing: CAMediaTimingFunction(controlPoints: 0.5, 0.0, 0.6, 1.0))
                    }
                }
            }
        } else {
            self.headGone = true
            burst(self.point(50.0, 40.0 + drop), 12.0 * self.unit)
            pop("head", drop)
            fly("eyes", -8.0, 18.0, 0.0, drop)
            fly("smile", 6.0, 20.0, 0.0, drop)
            fly("carrot", 18.0, 22.0, 160.0, drop)
            fly("scarf", 0.0, 14.0, 0.0, drop)
            fly("tail", 0.0, 14.0, 0.0, drop)
            fly("neck", 0.0, 6.0, 0.0, drop)
        }
        if self.bodyGone && self.headGone {
            self.later(1.3) { [weak self] in
                self?.finish(melted: false)
            }
        } else {
            self.later(14.0) { [weak self] in
                guard let self else {
                    return
                }
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1.0
                fade.toValue = 0.0
                fade.duration = 1.2
                self.container.opacity = 0.0
                self.container.add(fade, forKey: "fade")
                self.later(1.2) { [weak self] in
                    self?.finish(melted: false)
                }
            }
        }
    }

    func melt() {
        guard self.state == .standing else {
            return
        }
        self.state = .melting
        self.cancelTimers()
        let fall: (String, CGFloat, CGFloat, CGFloat, Double) -> Void = { name, dx, dy, rotation, delay in
            self.animate(name, [AyuSnowmanStep(offset: 0.0), AyuSnowmanStep(dx: dx, dy: dy, rotation: rotation, opacity: 0.0, offset: 1.0)], duration: 0.9, delay: delay, timing: CAMediaTimingFunction(controlPoints: 0.5, 0.0, 0.8, 0.4))
        }
        fall("armR", 6.0, 34.0, 70.0, 0.0)
        fall("armL", -6.0, 34.0, -70.0, 0.15)
        fall("carrot", 4.0, 40.0, 120.0, 0.35)
        fall("eyes", 0.0, 46.0, 0.0, 0.5)
        fall("smile", 0.0, 40.0, 0.0, 0.6)
        fall("tail", 0.0, 20.0, 0.0, 0.7)
        fall("scarf", 0.0, 24.0, 0.0, 0.75)
        fall("buttons", 0.0, 18.0, 0.0, 0.8)
        self.animate("neck", [AyuSnowmanStep(offset: 0.0), AyuSnowmanStep(opacity: 0.0, offset: 1.0)], duration: 0.4, delay: 0.8)
        self.animate("head", [AyuSnowmanStep(offset: 0.0), AyuSnowmanStep(dx: 7.0, dy: 26.0, sx: 0.62, sy: 0.62, opacity: 0.9, offset: 0.7), AyuSnowmanStep(dx: 7.0, dy: 34.0, sx: 0.3, sy: 0.3, opacity: 0.0, offset: 1.0)], duration: 1.7, delay: 0.9, timing: CAMediaTimingFunction(name: .easeIn))
        if let body = self.parts["body"] {
            self.setAnchor(body, CGPoint(x: 0.5, y: 1.0))
        }
        self.animate("body", [AyuSnowmanStep(offset: 0.0), AyuSnowmanStep(sx: 1.12, sy: 0.3, opacity: 0.6, offset: 0.75), AyuSnowmanStep(sx: 1.2, sy: 0.1, opacity: 0.0, offset: 1.0)], duration: 2.3, delay: 1.3, timing: CAMediaTimingFunction(name: .easeIn))
        self.later(3.6) { [weak self] in
            self?.finish(melted: true)
        }
    }

    private func finish(melted: Bool) {
        self.cancelTimers()
        self.state = .gone
        self.container.removeFromSuperlayer()
        self.onGone?(melted)
    }

    func remove() {
        self.cancelTimers()
        self.state = .gone
        self.container.removeFromSuperlayer()
    }
}
