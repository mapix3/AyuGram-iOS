import Foundation
import UIKit
import AsyncDisplayKit
import SGSimpleSettings

public final class AyuGramChatBackgroundEffects {
    private weak var hostNode: ASDisplayNode?
    private var observer: AyuGramEffectsObserver?
    private var applicationObservers: [NSObjectProtocol] = []

    private var particlesNode: AyuGramParticlesNode?
    private var rippleNode: AyuGramRippleNode?

    private var size: CGSize?
    private var isVisible = false
    private var isInForeground = true
    private var particlesReactToTouch = false

    private var isTrackingRippleTouch = false
    private var lastRipplePoint: CGPoint?
    private var lastBurstPoint: CGPoint?

    public init(hostNode: ASDisplayNode) {
        self.hostNode = hostNode

        self.observer = AyuGramEffectsRuntime.observe({ [weak self] in
            self?.update()
        })

        let center = NotificationCenter.default
        self.applicationObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isInForeground = false
            strongSelf.update()
        }))
        self.applicationObservers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isInForeground = true
            strongSelf.update()
        }))
    }

    deinit {
        for token in self.applicationObservers {
            NotificationCenter.default.removeObserver(token)
        }
        let particlesNode = self.particlesNode
        let rippleNode = self.rippleNode
        if particlesNode != nil || rippleNode != nil {
            let remove = {
                particlesNode?.removeFromSupernode()
                rippleNode?.removeFromSupernode()
            }
            if Thread.isMainThread {
                remove()
            } else {
                DispatchQueue.main.async(execute: remove)
            }
        }
    }

    public func updateLayout(size: CGSize) {
        if self.size == size {
            return
        }
        self.size = size
        self.update()
    }

    public func updateIsVisible(_ isVisible: Bool) {
        if self.isVisible == isVisible {
            return
        }
        self.isVisible = isVisible
        if !isVisible {
            self.touchEnded()
        }
        self.update()
    }

    public var handlesTouches: Bool {
        if !self.isVisible || !self.isInForeground {
            return false
        }
        return self.rippleNode != nil || (self.particlesNode != nil && self.particlesReactToTouch)
    }

    public func touchBegan(at point: CGPoint, isEmptyBackground: Bool) {
        guard self.handlesTouches else {
            return
        }
        if isEmptyBackground, let rippleNode = self.rippleNode {
            self.isTrackingRippleTouch = true
            self.lastRipplePoint = point
            rippleNode.addRipple(at: point, radius: 96.0, duration: 1.1)
        } else {
            self.isTrackingRippleTouch = false
            self.lastRipplePoint = nil
        }
        if self.particlesReactToTouch, let particlesNode = self.particlesNode {
            self.lastBurstPoint = point
            particlesNode.burst(at: point, strength: 1.0)
        } else {
            self.lastBurstPoint = nil
        }
    }

    public func touchMoved(to point: CGPoint) {
        guard self.handlesTouches else {
            return
        }
        if self.isTrackingRippleTouch, let rippleNode = self.rippleNode, let lastRipplePoint = self.lastRipplePoint {
            if AyuGramChatBackgroundEffects.distance(lastRipplePoint, point) >= 36.0 {
                self.lastRipplePoint = point
                rippleNode.addRipple(at: point, radius: 54.0, duration: 0.8)
            }
        }
        if let particlesNode = self.particlesNode, let lastBurstPoint = self.lastBurstPoint {
            if AyuGramChatBackgroundEffects.distance(lastBurstPoint, point) >= 12.0 {
                self.lastBurstPoint = point
                particlesNode.burst(at: point, strength: 0.5)
            }
        }
    }

    public func touchEnded() {
        self.isTrackingRippleTouch = false
        self.lastRipplePoint = nil
        self.lastBurstPoint = nil
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func update() {
        guard let hostNode = self.hostNode, let size = self.size, size.width > 0.0, size.height > 0.0 else {
            return
        }
        let settings = AyuGramEffectsRuntime.settings
        let frame = CGRect(origin: CGPoint(), size: size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let style = settings.activeParticles
        if style != .off && AyuGramEffectsRuntime.continuousEffectsAllowed {
            let particlesNode: AyuGramParticlesNode
            if let current = self.particlesNode {
                particlesNode = current
            } else {
                particlesNode = AyuGramParticlesNode()
                self.particlesNode = particlesNode
                if let rippleNode = self.rippleNode, rippleNode.supernode === hostNode {
                    hostNode.insertSubnode(particlesNode, belowSubnode: rippleNode)
                } else {
                    hostNode.addSubnode(particlesNode)
                }
            }
            particlesNode.frame = frame
            particlesNode.update(configuration: AyuGramParticlesNode.Configuration(
                style: style,
                density: CGFloat(settings.particleDensity),
                speed: CGFloat(settings.particleSpeed)
            ), size: size)
            particlesNode.setPaused(!(self.isVisible && self.isInForeground))
            self.particlesReactToTouch = settings.particlesReactToTouch
        } else if let particlesNode = self.particlesNode {
            self.particlesNode = nil
            self.lastBurstPoint = nil
            particlesNode.removeFromSupernode()
        }

        if settings.activeBackgroundRipple && AyuGramEffectsRuntime.motionAllowed {
            let rippleNode: AyuGramRippleNode
            if let current = self.rippleNode {
                rippleNode = current
            } else {
                rippleNode = AyuGramRippleNode()
                self.rippleNode = rippleNode
                hostNode.addSubnode(rippleNode)
            }
            rippleNode.frame = frame
        } else if let rippleNode = self.rippleNode {
            self.rippleNode = nil
            self.isTrackingRippleTouch = false
            self.lastRipplePoint = nil
            rippleNode.removeFromSupernode()
        }

        CATransaction.commit()
    }
}
