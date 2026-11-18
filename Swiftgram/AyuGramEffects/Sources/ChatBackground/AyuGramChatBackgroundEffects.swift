import Foundation
import UIKit
import AsyncDisplayKit
import SGSimpleSettings

public final class AyuGramChatBackgroundEffects {
    private weak var hostNode: ASDisplayNode?
    private var observer: AyuGramEffectsObserver?
    private var applicationObservers: [NSObjectProtocol] = []

    private var rippleNode: AyuGramRippleNode?

    private var size: CGSize?
    private var isVisible = false
    private var isInForeground = true

    private var isTrackingRippleTouch = false
    private var lastRipplePoint: CGPoint?

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
        if let rippleNode = self.rippleNode {
            let remove = {
                rippleNode.removeFromSupernode()
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
        return self.rippleNode != nil
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
    }

    public func touchEnded() {
        self.isTrackingRippleTouch = false
        self.lastRipplePoint = nil
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
