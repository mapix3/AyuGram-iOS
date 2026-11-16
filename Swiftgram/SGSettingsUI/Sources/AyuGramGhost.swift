import Foundation
import UIKit
import QuartzCore

private final class AyuGramGhostTicker: NSObject {
    static let shared = AyuGramGhostTicker()

    private final class Weak {
        weak var ghost: AyuGramGhostView?

        init(_ ghost: AyuGramGhostView) {
            self.ghost = ghost
        }
    }

    private var ghosts: [Weak] = []
    private var link: CADisplayLink?

    func add(_ ghost: AyuGramGhostView) {
        self.ghosts.removeAll(where: { $0.ghost == nil || $0.ghost === ghost })
        self.ghosts.append(Weak(ghost))
        if self.link == nil {
            let link = CADisplayLink(target: self, selector: #selector(self.tick))
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 60.0, preferred: 60.0)
            }
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    func remove(_ ghost: AyuGramGhostView) {
        self.ghosts.removeAll(where: { $0.ghost == nil || $0.ghost === ghost })
        if self.ghosts.isEmpty {
            self.link?.invalidate()
            self.link = nil
        }
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        for item in self.ghosts {
            item.ghost?.step(now: now)
        }
        self.ghosts.removeAll(where: { $0.ghost == nil })
        if self.ghosts.isEmpty {
            self.link?.invalidate()
            self.link = nil
        }
    }
}

public final class AyuGramGhostView: UIView {
    private let floatView = UIView()
    private let gradient = CAGradientLayer()
    private let shape = CAShapeLayer()
    private let eyes = [CALayer(), CALayer()]
    private let seed = Double.random(in: 0.0 ..< 10.0)
    private var look = CGPoint()
    private var winkUntil: Double = 0.0
    private var hopStart: Double = -10.0

    public var lookTarget: CGPoint?
    public var squint = false
    public var idle = true

    public var colors: (UIColor, UIColor) = (.white, UIColor(white: 0.62, alpha: 1.0)) {
        didSet {
            self.gradient.colors = [self.colors.0.cgColor, self.colors.1.cgColor]
        }
    }

    public var eyeColor: UIColor = .black {
        didSet {
            for eye in self.eyes {
                eye.backgroundColor = self.eyeColor.cgColor
            }
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.floatView.isUserInteractionEnabled = false
        self.addSubview(self.floatView)
        self.gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        self.gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.gradient.colors = [self.colors.0.cgColor, self.colors.1.cgColor]
        self.gradient.mask = self.shape
        self.floatView.layer.addSublayer(self.gradient)
        for eye in self.eyes {
            eye.backgroundColor = self.eyeColor.cgColor
            self.floatView.layer.addSublayer(eye)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let size = self.bounds.size
        self.floatView.bounds = CGRect(origin: CGPoint(), size: size)
        self.floatView.center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.gradient.frame = CGRect(origin: CGPoint(), size: size)
        self.shape.frame = self.gradient.bounds
        let s = min(size.width, size.height)
        let ox = (size.width - s) / 2.0
        let oy = (size.height - s) / 2.0
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: ox + x * s, y: oy + y * s)
        }
        let path = UIBezierPath()
        let head = p(0.5, 0.42)
        path.append(UIBezierPath(arcCenter: head, radius: 0.33 * s, startAngle: 0.0, endAngle: .pi * 2.0, clockwise: true))
        path.append(UIBezierPath(rect: CGRect(origin: p(0.17, 0.42), size: CGSize(width: 0.66 * s, height: 0.38 * s))))
        for x in [0.28, 0.5, 0.72] as [CGFloat] {
            path.append(UIBezierPath(arcCenter: p(x, 0.8), radius: 0.11 * s, startAngle: 0.0, endAngle: .pi * 2.0, clockwise: true))
        }
        self.shape.path = path.cgPath
        self.shape.fillRule = .nonZero
        CATransaction.commit()
        self.step(now: CACurrentMediaTime())
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()

        if self.window != nil {
            AyuGramGhostTicker.shared.add(self)
        } else {
            AyuGramGhostTicker.shared.remove(self)
        }
    }

    public func wink() {
        self.winkUntil = CACurrentMediaTime() + 0.22
    }

    public func hop() {
        self.hopStart = CACurrentMediaTime()
        self.wink()
    }

    fileprivate func step(now: Double) {
        let size = self.bounds.size
        let s = min(size.width, size.height)
        guard s > 0.0 else {
            return
        }
        let reduce = UIAccessibility.isReduceMotionEnabled
        let t = now + self.seed
        var bob: CGFloat = 0.0
        var tilt: CGFloat = 0.0
        if self.idle && !reduce {
            bob = CGFloat(sin(t * 2.2)) * max(1.2, s * 0.05)
            tilt = CGFloat(sin(t * 1.1)) * 4.0 * .pi / 180.0
        }
        let hop = now - self.hopStart
        if hop >= 0.0 && hop < 0.5 {
            let k = hop / 0.5
            bob -= CGFloat(sin(k * .pi)) * s * 0.28
        }
        self.floatView.transform = CGAffineTransform(translationX: 0.0, y: bob).rotated(by: tilt)

        var target = CGPoint()
        if let lookTarget = self.lookTarget {
            target = lookTarget
        } else if self.idle && !reduce {
            target = CGPoint(x: CGFloat((sin(t * 0.45) * 2.5).rounded()) * 0.2, y: 0.0)
        }
        self.look.x += (target.x - self.look.x) * 0.18
        self.look.y += (target.y - self.look.y) * 0.18

        let blink = !reduce && (t.truncatingRemainder(dividingBy: 3.7)) < 0.13
        let ox = (size.width - s) / 2.0
        let oy = (size.height - s) / 2.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, eye) in self.eyes.enumerated() {
            var width = 0.12 * s
            var height = 0.18 * s
            if self.squint {
                width = 0.13 * s
                height = 0.045 * s
            } else if index == 1 && now < self.winkUntil {
                width = 0.14 * s
                height = 0.03 * s
            } else if blink {
                height = 0.025 * s
            }
            let cx = ox + ((index == 0 ? 0.4 : 0.62) + self.look.x * 0.05) * s
            let cy = oy + (0.45 + self.look.y * 0.045) * s
            eye.frame = CGRect(x: cx - width / 2.0, y: cy - height / 2.0, width: width, height: height)
            eye.cornerRadius = min(width, height) / 2.0
        }
        CATransaction.commit()
    }
}

public final class AyuGramGhostIntroView: UIView {
    private struct Dust {
        let layer: CALayer
        let x: CGFloat
        let y: CGFloat
        let phase: Double
        let speed: Double
        let drift: CGFloat
    }

    private let backdrop = UIView()
    private let stage = UIView()
    private let glow = CAGradientLayer()
    private let warm = CAGradientLayer()
    private let shadow = UIView()
    private let ghost = AyuGramGhostView()
    private let status = UILabel()
    private let percent = UILabel()
    private let caret = CAShapeLayer()
    private var ticks: [CALayer] = []
    private var dust: [Dust] = []
    private var letters: [UILabel] = []
    private let tagline = UILabel()
    private var link: CADisplayLink?
    private var started: Double = 0.0
    private var progressFrom: CGFloat = 0.0
    private var progressTo: CGFloat = 0.0
    private var progressStart: Double = 0.0
    private var progress: CGFloat = 0.0
    private var loaderVisible = false
    private var ticksDropped = false
    private var finished = false
    private let accent: UIColor
    private let word: String
    private let steps: [(String, CGFloat)]
    private let ghostSize: CGFloat = 64.0
    private let rulerWidth: CGFloat = 240.0
    private let tickCount = 41
    private var completion: (() -> Void)?

    public init(accent: UIColor, word: String, tagline: String, steps: [String], completion: @escaping () -> Void) {
        self.accent = accent
        self.word = word
        let values: [CGFloat] = [0.22, 0.5, 0.82, 1.0]
        self.steps = steps.enumerated().map { ($0.element, values[min($0.offset, values.count - 1)]) }
        self.completion = completion
        super.init(frame: CGRect())

        self.backdrop.backgroundColor = UIColor(white: 0.02, alpha: 1.0)
        self.backdrop.alpha = 0.0
        self.addSubview(self.backdrop)
        self.addSubview(self.stage)

        let white = UIColor.white
        for layer in [self.glow, self.warm] {
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1.0, y: 1.0)
            layer.opacity = 0.0
            self.stage.layer.addSublayer(layer)
        }
        self.glow.colors = [white.withAlphaComponent(0.16).cgColor, white.withAlphaComponent(0.0).cgColor]
        self.warm.colors = [accent.withAlphaComponent(0.26).cgColor, accent.withAlphaComponent(0.0).cgColor]

        for index in 0 ..< 26 {
            let layer = CALayer()
            let size = CGFloat(1 + index % 3)
            layer.bounds = CGRect(x: 0.0, y: 0.0, width: size, height: size)
            layer.cornerRadius = size / 2.0
            layer.backgroundColor = (index % 5 == 0 ? accent : white).cgColor
            layer.opacity = 0.0
            self.stage.layer.addSublayer(layer)
            self.dust.append(Dust(layer: layer, x: CGFloat.random(in: -0.15 ... 1.15), y: CGFloat.random(in: -0.1 ... 1.1), phase: Double.random(in: 0.0 ... 6.28), speed: 0.8 + Double.random(in: 0.0 ... 2.2), drift: 2.0 + CGFloat.random(in: 0.0 ... 5.0)))
        }

        self.shadow.backgroundColor = .black
        self.shadow.alpha = 0.0
        self.stage.addSubview(self.shadow)

        self.ghost.colors = (white, accent.ayuMix(white, alpha: 0.35))
        self.ghost.eyeColor = UIColor(white: 0.04, alpha: 1.0)
        self.ghost.idle = true
        self.ghost.alpha = 0.0
        self.stage.addSubview(self.ghost)

        self.status.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        self.status.textColor = UIColor(white: 0.6, alpha: 1.0)
        self.status.alpha = 0.0
        self.stage.addSubview(self.status)
        self.percent.textAlignment = .right
        self.percent.alpha = 0.0
        self.stage.addSubview(self.percent)

        for _ in 0 ..< self.tickCount {
            let tick = CALayer()
            tick.backgroundColor = accent.cgColor
            tick.opacity = 0.0
            self.stage.layer.addSublayer(tick)
            self.ticks.append(tick)
        }
        let caretPath = UIBezierPath()
        caretPath.move(to: CGPoint(x: 0.0, y: 6.0))
        caretPath.addLine(to: CGPoint(x: 5.0, y: 1.0))
        caretPath.addLine(to: CGPoint(x: 10.0, y: 6.0))
        self.caret.path = caretPath.cgPath
        self.caret.strokeColor = accent.cgColor
        self.caret.fillColor = UIColor.clear.cgColor
        self.caret.lineWidth = 1.7
        self.caret.lineCap = .round
        self.caret.lineJoin = .round
        self.caret.opacity = 0.0
        self.stage.layer.addSublayer(self.caret)

        for character in word {
            let label = UILabel()
            label.text = String(character)
            label.font = UIFont.systemFont(ofSize: 34.0, weight: .bold)
            label.textColor = white
            label.alpha = 0.0
            label.sizeToFit()
            self.stage.addSubview(label)
            self.letters.append(label)
        }
        self.tagline.text = tagline
        self.tagline.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        self.tagline.textColor = UIColor(white: 0.6, alpha: 1.0)
        self.tagline.alpha = 0.0
        self.tagline.sizeToFit()
        self.stage.addSubview(self.tagline)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.skip))
        self.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var centerY: CGFloat {
        return self.bounds.height / 2.0 - 40.0
    }

    private var wordWidth: CGFloat {
        return self.letters.reduce(0.0, { $0 + $1.bounds.width + 1.0 }) - 1.0
    }

    private var lockup: (markX: CGFloat, wordX: CGFloat, lineY: CGFloat) {
        let mark: CGFloat = 46.0
        let gap: CGFloat = 8.0
        let total = mark + gap + self.wordWidth
        let startX = (self.bounds.width - total) / 2.0
        return (startX + mark / 2.0, startX + mark + gap, self.bounds.height / 2.0 - 10.0)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        self.backdrop.frame = self.bounds
        self.stage.frame = self.bounds
        guard self.started == 0.0 else {
            return
        }
        let w = self.bounds.width
        let cy = self.centerY
        self.glow.frame = CGRect(x: w / 2.0 - 150.0, y: cy - 150.0, width: 300.0, height: 300.0)
        self.warm.frame = CGRect(x: w / 2.0 - 90.0, y: cy - 90.0, width: 180.0, height: 180.0)
        self.ghost.bounds = CGRect(x: 0.0, y: 0.0, width: self.ghostSize, height: self.ghostSize)
        self.ghost.center = CGPoint(x: w / 2.0, y: cy + 16.0)
        self.ghost.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        self.shadow.bounds = CGRect(x: 0.0, y: 0.0, width: self.ghostSize * 0.55, height: 7.0)
        self.shadow.layer.cornerRadius = 3.5
        self.shadow.center = CGPoint(x: w / 2.0, y: cy + self.ghostSize * 0.62)
        let rx = (w - self.rulerWidth) / 2.0
        let ry = cy + 80.0
        for (index, tick) in self.ticks.enumerated() {
            let x = rx + CGFloat(index) * self.rulerWidth / CGFloat(self.tickCount - 1)
            tick.frame = CGRect(x: x - 1.0, y: ry, width: 2.0, height: 14.0)
        }
        self.caret.frame = CGRect(x: rx - 5.0, y: ry + 22.0, width: 10.0, height: 7.0)
        self.status.frame = CGRect(x: rx, y: ry - 26.0, width: self.rulerWidth * 0.7, height: 16.0)
        self.percent.frame = CGRect(x: rx + self.rulerWidth - 120.0, y: ry - 31.0, width: 120.0, height: 22.0)
        let lockup = self.lockup
        var x = lockup.wordX
        for label in self.letters {
            label.center = CGPoint(x: x + label.bounds.width / 2.0, y: lockup.lineY + 16.0)
            label.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            x += label.bounds.width + 1.0
        }
        self.tagline.frame.origin = CGPoint(x: lockup.wordX - 6.0, y: lockup.lineY + 30.0)
    }

    public func play() {
        guard self.started == 0.0 else {
            return
        }
        self.layoutIfNeeded()
        self.started = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(self.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link

        UIView.animate(withDuration: 0.35, animations: {
            self.backdrop.alpha = 1.0
        })
        self.fade(self.glow, to: 0.9, duration: 1.0)
        self.fade(self.warm, to: 0.9, duration: 1.2)

        self.after(0.15) {
            UIView.animate(withDuration: 0.3, animations: {
                self.ghost.alpha = 1.0
                self.shadow.alpha = 0.45
            })
            UIView.animate(withDuration: 0.6, delay: 0.0, usingSpringWithDamping: 0.58, initialSpringVelocity: 0.0, options: [], animations: {
                self.ghost.center = CGPoint(x: self.bounds.width / 2.0, y: self.centerY)
                self.ghost.transform = .identity
            })
            self.shockwave(at: CGPoint(x: self.bounds.width / 2.0, y: self.centerY), delay: 0.12)
            self.wisps(count: 6, spread: 46.0, origin: CGPoint(x: self.bounds.width / 2.0, y: self.centerY + self.ghostSize * 0.3))
        }
        self.after(0.7) {
            self.loaderVisible = true
            UIView.animate(withDuration: 0.3, animations: {
                self.status.alpha = 1.0
                self.percent.alpha = 1.0
            })
            self.ghost.lookTarget = CGPoint(x: -0.6, y: 0.9)
            self.runSteps(index: 0)
        }
    }

    private func runSteps(index: Int) {
        guard !self.finished else {
            return
        }
        guard index < self.steps.count else {
            self.status.textColor = self.accent
            self.after(0.12) {
                self.dropLoader()
            }
            return
        }
        let step = self.steps[index]
        self.type(step.0)
        self.progressFrom = self.progress
        self.progressTo = step.1
        self.progressStart = CACurrentMediaTime()
        self.after(0.4) {
            self.runSteps(index: index + 1)
        }
    }

    private func type(_ text: String) {
        let characters = Array(text)
        self.status.text = ""
        for count in 1 ... max(1, characters.count) {
            self.after(Double(count) * 0.02) {
                self.status.text = String(characters.prefix(count))
            }
        }
    }

    private func dropLoader() {
        guard !self.finished else {
            return
        }
        self.ticksDropped = true
        self.ghost.lookTarget = nil
        UIView.animate(withDuration: 0.2, animations: {
            self.status.alpha = 0.0
            self.percent.alpha = 0.0
        })
        self.fade(self.caret, to: 0.0, duration: 0.2)
        for (index, tick) in self.ticks.enumerated() {
            let delay = Double(index) * 0.006
            self.after(delay) {
                let move = CABasicAnimation(keyPath: "position.y")
                move.fromValue = tick.position.y
                move.toValue = tick.position.y + 14.0
                move.duration = 0.35
                tick.position.y += 14.0
                tick.add(move, forKey: "drop")
                self.fade(tick, to: 0.0, duration: 0.35)
            }
        }
        let lockup = self.lockup
        UIView.animate(withDuration: 0.55, delay: 0.0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0, options: [], animations: {
            self.ghost.center = CGPoint(x: lockup.markX, y: lockup.lineY)
            self.ghost.transform = CGAffineTransform(scaleX: 46.0 / self.ghostSize, y: 46.0 / self.ghostSize)
            self.shadow.center = CGPoint(x: lockup.markX, y: lockup.lineY + 46.0 * 0.62)
            self.shadow.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        })
        for (index, label) in self.letters.enumerated() {
            self.after(0.18 + Double(index) * 0.04) {
                UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0, options: [], animations: {
                    label.alpha = 1.0
                    label.center.y = lockup.lineY
                    label.transform = .identity
                })
                if index % 3 == 0 {
                    self.wisps(count: 2, spread: 10.0, origin: CGPoint(x: label.center.x, y: lockup.lineY - 8.0))
                }
            }
        }
        self.after(0.5) {
            UIView.animate(withDuration: 0.45, animations: {
                self.tagline.alpha = 0.9
                self.tagline.frame.origin.x = lockup.wordX + 2.0
            })
        }
        self.after(0.6) {
            self.ghost.lookTarget = CGPoint(x: 1.0, y: 0.1)
            self.shine()
        }
        self.after(1.35) {
            self.ghost.lookTarget = nil
            self.ghost.wink()
        }
        self.after(1.75) {
            self.finish(animated: true)
        }
    }

    private func shine() {
        for (index, label) in self.letters.enumerated() {
            self.after(Double(index) * 0.05) {
                UIView.transition(with: label, duration: 0.18, options: .transitionCrossDissolve, animations: {
                    label.textColor = self.accent.ayuMix(.white, alpha: 0.35)
                }, completion: { _ in
                    UIView.transition(with: label, duration: 0.3, options: .transitionCrossDissolve, animations: {
                        label.textColor = .white
                    })
                })
            }
        }
    }

    @objc private func skip() {
        self.finish(animated: true)
    }

    private func finish(animated: Bool) {
        guard !self.finished else {
            return
        }
        self.finished = true
        self.ghost.squint = true
        UIView.animate(withDuration: animated ? 0.35 : 0.0, animations: {
            self.ghost.transform = self.ghost.transform.scaledBy(x: 0.3, y: 0.3)
            self.ghost.alpha = 0.0
            for label in self.letters {
                label.alpha = 0.0
                label.center.y += 10.0
            }
            self.tagline.alpha = 0.0
            self.status.alpha = 0.0
            self.percent.alpha = 0.0
            self.shadow.alpha = 0.0
        })
        self.fade(self.glow, to: 0.0, duration: 0.4)
        self.fade(self.warm, to: 0.0, duration: 0.4)
        for tick in self.ticks {
            self.fade(tick, to: 0.0, duration: 0.2)
        }
        self.fade(self.caret, to: 0.0, duration: 0.2)
        UIView.animate(withDuration: animated ? 0.45 : 0.0, delay: animated ? 0.15 : 0.0, options: [.curveEaseInOut], animations: {
            self.alpha = 0.0
        }, completion: { _ in
            self.link?.invalidate()
            self.link = nil
            self.removeFromSuperview()
            let completion = self.completion
            self.completion = nil
            completion?()
        })
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let t = now - self.started
        let w = self.bounds.width
        let h = self.bounds.height
        let dustAlpha = Float(min(1.0, t / 1.4)) * (self.finished ? 0.0 : 1.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in self.dust {
            let twinkle = Float(0.5 + 0.5 * sin(t * item.speed + item.phase))
            item.layer.opacity = dustAlpha * (0.1 + 0.5 * twinkle)
            item.layer.position = CGPoint(x: item.x * w + CGFloat(sin(t * 0.35 + item.phase)) * item.drift, y: item.y * h - CGFloat(t) * item.drift)
        }
        let breathe = CGFloat(sin(t * 1.4))
        self.glow.setAffineTransform(CGAffineTransform(scaleX: 1.0 + breathe * 0.03, y: 1.0 + breathe * 0.03))
        self.warm.setAffineTransform(CGAffineTransform(scaleX: 1.0 - breathe * 0.04, y: 1.0 - breathe * 0.04))

        if self.progressStart > 0.0 {
            var k = CGFloat(min(1.0, (now - self.progressStart) / 0.36))
            k = k * k * (3.0 - 2.0 * k)
            self.progress = self.progressFrom + (self.progressTo - self.progressFrom) * k
        }
        if self.loaderVisible && !self.ticksDropped {
            let head = self.progress * CGFloat(self.tickCount - 1)
            let headIndex = Int(head.rounded())
            let rx = (w - self.rulerWidth) / 2.0
            let ry = self.centerY + 80.0
            let cream = self.accent.ayuMix(.white, alpha: 0.86)
            for (index, tick) in self.ticks.enumerated() {
                let x = rx + CGFloat(index) * self.rulerWidth / CGFloat(self.tickCount - 1)
                if index == headIndex {
                    tick.backgroundColor = UIColor.white.cgColor
                    tick.frame = CGRect(x: x - 1.0, y: ry - 2.0, width: 2.0, height: 18.0)
                    tick.opacity = 1.0
                } else if CGFloat(index) < head {
                    let distance = head - CGFloat(index)
                    tick.backgroundColor = self.accent.ayuMix(cream, alpha: max(0.0, min(1.0, 1.0 - distance / 6.0))).cgColor
                    tick.frame = CGRect(x: x - 1.0, y: ry, width: 2.0, height: 14.0)
                    tick.opacity = Float(1.0 - max(0.0, min(0.7, distance / CGFloat(self.tickCount))))
                } else {
                    tick.backgroundColor = self.accent.cgColor
                    tick.frame = CGRect(x: x - 1.0, y: ry, width: 2.0, height: 14.0)
                    tick.opacity = 0.22
                }
            }
            self.caret.opacity = 1.0
            self.caret.position = CGPoint(x: rx + CGFloat(headIndex) * self.rulerWidth / CGFloat(self.tickCount - 1), y: ry + 25.5)
            let value = Int((self.progress * 100.0).rounded())
            let text = NSMutableAttributedString(string: "\(value)", attributes: [.font: UIFont.systemFont(ofSize: 18.0, weight: .bold), .foregroundColor: UIColor.white])
            text.append(NSAttributedString(string: " %", attributes: [.font: UIFont.systemFont(ofSize: 11.0, weight: .medium), .foregroundColor: UIColor(white: 0.6, alpha: 1.0)]))
            self.percent.attributedText = text
            let ghostCenter = self.ghost.center
            let dx = self.caret.position.x - ghostCenter.x
            let dy = self.caret.position.y - ghostCenter.y
            let length = max(1.0, sqrt(dx * dx + dy * dy))
            self.ghost.lookTarget = CGPoint(x: dx / length, y: dy / length)
        }
        CATransaction.commit()
    }

    private func fade(_ layer: CALayer, to value: Float, duration: Double) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = value
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.opacity = value
        layer.add(animation, forKey: "fade")
    }

    private func shockwave(at point: CGPoint, delay: Double) {
        self.after(delay) {
            let ring = CAShapeLayer()
            let radius = self.ghostSize * 0.35
            ring.path = UIBezierPath(arcCenter: CGPoint(), radius: radius, startAngle: 0.0, endAngle: .pi * 2.0, clockwise: true).cgPath
            ring.position = point
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = UIColor.white.cgColor
            ring.lineWidth = 2.0
            ring.opacity = 0.0
            self.stage.layer.addSublayer(ring)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 3.6
            scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.8
            fade.toValue = 0.0
            let width = CABasicAnimation(keyPath: "lineWidth")
            width.fromValue = 2.0
            width.toValue = 0.5
            let group = CAAnimationGroup()
            group.animations = [scale, fade, width]
            group.duration = 0.7
            ring.add(group, forKey: "wave")
            self.after(0.75) {
                ring.removeFromSuperlayer()
            }
        }
    }

    private func wisps(count: Int, spread: CGFloat, origin: CGPoint) {
        for index in 0 ..< count {
            let dot = CALayer()
            let size = CGFloat(2 + index % 3)
            dot.bounds = CGRect(x: 0.0, y: 0.0, width: size, height: size)
            dot.cornerRadius = size / 2.0
            dot.backgroundColor = (Bool.random() && index % 3 == 0 ? self.accent : UIColor.white).cgColor
            let start = CGPoint(x: origin.x + (CGFloat.random(in: 0.0 ... 1.0) - 0.5) * spread, y: origin.y)
            let end = CGPoint(x: start.x + (CGFloat.random(in: 0.0 ... 1.0) - 0.5) * 50.0, y: start.y - 50.0 - CGFloat.random(in: 0.0 ... 50.0))
            dot.position = end
            dot.opacity = 0.0
            self.stage.layer.addSublayer(dot)
            let life = 0.8 + Double.random(in: 0.0 ... 0.6)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: start)
            move.toValue = NSValue(cgPoint: end)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.85
            fade.toValue = 0.0
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.0
            shrink.toValue = 0.3
            let group = CAAnimationGroup()
            group.animations = [move, fade, shrink]
            group.duration = life
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            dot.add(group, forKey: "wisp")
            self.after(life + 0.05) {
                dot.removeFromSuperlayer()
            }
        }
    }

    private func after(_ delay: Double, _ f: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: f)
    }
}

extension UIColor {
    func ayuMix(_ other: UIColor, alpha: CGFloat) -> UIColor {
        var r1: CGFloat = 0.0, g1: CGFloat = 0.0, b1: CGFloat = 0.0, a1: CGFloat = 0.0
        var r2: CGFloat = 0.0, g2: CGFloat = 0.0, b2: CGFloat = 0.0, a2: CGFloat = 0.0
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = max(0.0, min(1.0, alpha))
        return UIColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k, alpha: a1 + (a2 - a1) * k)
    }
}
