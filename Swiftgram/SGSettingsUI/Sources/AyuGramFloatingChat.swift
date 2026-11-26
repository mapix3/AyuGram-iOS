import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import SGStrings

private func ayuFloatingContainsFirstResponder(_ view: UIView) -> Bool {
    if view.isFirstResponder {
        return true
    }
    for subview in view.subviews {
        if ayuFloatingContainsFirstResponder(subview) {
            return true
        }
    }
    return false
}

private final class AyuGramFloatingHostNode: ASDisplayNode {
    var panels: [AyuGramFloatingPanel] = []

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for panel in self.panels.reversed() where !panel.isHidden && panel.alpha > 0.01 {
            if let result = panel.hitTest(self.view.convert(point, to: panel), with: event) {
                return result
            }
        }
        return nil
    }
}

private final class AyuGramFloatingHostController: ViewController {
    private var hostNode: AyuGramFloatingHostNode {
        return self.displayNode as! AyuGramFloatingHostNode
    }

    private(set) var validLayout: ContainerViewLayout?
    private var pendingPanels: [AyuGramFloatingPanel] = []

    var panels: [AyuGramFloatingPanel] {
        return self.isNodeLoaded ? self.hostNode.panels : self.pendingPanels
    }

    init() {
        super.init(navigationBarPresentationData: nil)
        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        let node = AyuGramFloatingHostNode()
        self.displayNode = node
        self.displayNodeDidLoad()
        for panel in self.pendingPanels {
            self.attach(panel)
        }
        self.pendingPanels = []
    }

    private func attach(_ panel: AyuGramFloatingPanel) {
        self.hostNode.panels.append(panel)
        self.hostNode.view.addSubview(panel)
        self.addChild(panel.navigation)
        panel.navigation.didMove(toParent: self)
        if let layout = self.validLayout {
            panel.hostLayoutUpdated(layout, transition: .immediate)
        }
    }

    func add(_ panel: AyuGramFloatingPanel) {
        if self.isNodeLoaded {
            self.attach(panel)
        } else {
            self.pendingPanels.append(panel)
        }
    }

    func remove(_ panel: AyuGramFloatingPanel) {
        panel.navigation.willMove(toParent: nil)
        panel.removeFromSuperview()
        panel.navigation.removeFromParent()
        if self.isNodeLoaded {
            self.hostNode.panels.removeAll(where: { $0 === panel })
        }
        self.pendingPanels.removeAll(where: { $0 === panel })
    }

    func bringToFront(_ panel: AyuGramFloatingPanel) {
        guard self.isNodeLoaded, let index = self.hostNode.panels.firstIndex(where: { $0 === panel }) else {
            return
        }
        self.hostNode.panels.remove(at: index)
        self.hostNode.panels.append(panel)
        self.hostNode.view.bringSubviewToFront(panel)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.validLayout = layout
        for panel in self.panels {
            panel.hostLayoutUpdated(layout, transition: transition)
        }
    }
}

private final class AyuGramFloatingButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return self.bounds.insetBy(dx: -8.0, dy: -8.0).contains(point)
    }
}

final class AyuGramFloatingPanel: UIView, UIGestureRecognizerDelegate {
    let key: String
    let navigation: NavigationController
    private let context: AccountContext
    private let openFull: (() -> Void)?
    private let close: (AyuGramFloatingPanel) -> Void
    private let focus: (AyuGramFloatingPanel) -> Void

    private let shadowView = UIView()
    private let card = UIView()
    private let bar = UIVisualEffectView(effect: nil)
    private let grabber = UIView()
    private let titleLabel = UILabel()
    private let closeButton = AyuGramFloatingButton(type: .system)
    private let minimizeButton = AyuGramFloatingButton(type: .system)
    private let expandButton = AyuGramFloatingButton(type: .system)
    private let contentClip = UIView()
    private let contentHost = UIView()
    private let resizeHandle = UIView()
    private let resizeGlyph = UIImageView()
    private let bubble = UIControl()
    private let bubbleBlur = UIVisualEffectView(effect: nil)
    private let bubbleLabel = UILabel()
    private let badge = UIView()

    private var hostLayout: ContainerViewLayout?
    private var cardFrame = CGRect()
    private var bubbleCenter: CGPoint?
    private var keyboardLift: CGFloat = 0.0
    private(set) var minimized = false
    private var placed = false
    private let barHeight: CGFloat = 30.0
    private let bubbleSize: CGFloat = 58.0
    private var resizeStart: CGRect?
    private var messagesDisposable: Disposable?
    private var lastSeenMessage: EngineMessage.Id?
    private var latestMessage: EngineMessage.Id?

    init(context: AccountContext, key: String, title: String, root: ViewController, watchPeerId: EnginePeer.Id?, theme: PresentationTheme, openFull: (() -> Void)?, close: @escaping (AyuGramFloatingPanel) -> Void, focus: @escaping (AyuGramFloatingPanel) -> Void) {
        self.context = context
        self.key = key
        self.openFull = openFull
        self.close = close
        self.focus = focus
        self.navigation = NavigationController(mode: .single, theme: NavigationControllerTheme(presentationTheme: theme))
        self.navigation.setViewControllers([root], animated: false)
        super.init(frame: CGRect())

        self.shadowView.layer.shadowColor = UIColor.black.cgColor
        self.shadowView.layer.shadowOpacity = 0.35
        self.shadowView.layer.shadowRadius = 24.0
        self.shadowView.layer.shadowOffset = CGSize(width: 0.0, height: 10.0)
        self.shadowView.isUserInteractionEnabled = false
        self.addSubview(self.shadowView)

        self.card.clipsToBounds = true
        self.card.layer.cornerRadius = 22.0
        self.card.layer.cornerCurve = .continuous
        self.card.layer.borderWidth = 1.0 / UIScreen.main.scale
        self.addSubview(self.card)

        self.contentClip.clipsToBounds = true
        self.card.addSubview(self.contentClip)
        self.contentHost.layer.anchorPoint = CGPoint()
        self.contentClip.addSubview(self.contentHost)
        self.contentHost.addSubview(self.navigation.view)

        self.card.addSubview(self.bar)
        self.grabber.layer.cornerRadius = 2.0
        self.bar.contentView.addSubview(self.grabber)
        self.titleLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
        self.titleLabel.text = title
        self.titleLabel.textAlignment = .center
        self.bar.contentView.addSubview(self.titleLabel)
        let symbol = UIImage.SymbolConfiguration(pointSize: 11.0, weight: .bold)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: symbol), for: .normal)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.minimizeButton.setImage(UIImage(systemName: "minus", withConfiguration: symbol), for: .normal)
        self.minimizeButton.addTarget(self, action: #selector(self.minimizePressed), for: .touchUpInside)
        self.expandButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: symbol), for: .normal)
        self.expandButton.addTarget(self, action: #selector(self.expandPressed), for: .touchUpInside)
        self.expandButton.isHidden = openFull == nil
        for button in [self.closeButton, self.minimizeButton, self.expandButton] {
            self.bar.contentView.addSubview(button)
        }
        let drag = UIPanGestureRecognizer(target: self, action: #selector(self.dragged(_:)))
        self.bar.addGestureRecognizer(drag)
        let sizeToggle = UITapGestureRecognizer(target: self, action: #selector(self.barDoubleTapped))
        sizeToggle.numberOfTapsRequired = 2
        self.bar.addGestureRecognizer(sizeToggle)

        self.resizeGlyph.image = UIImage(systemName: "arrow.up.left.and.arrow.down.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10.0, weight: .bold))
        self.resizeGlyph.contentMode = .center
        self.resizeHandle.addSubview(self.resizeGlyph)
        self.resizeHandle.layer.cornerRadius = 13.0
        self.resizeHandle.clipsToBounds = true
        let resize = UIPanGestureRecognizer(target: self, action: #selector(self.resized(_:)))
        self.resizeHandle.addGestureRecognizer(resize)
        self.addSubview(self.resizeHandle)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.pinched(_:)))
        pinch.delegate = self
        self.bar.addGestureRecognizer(pinch)

        let touch = UITapGestureRecognizer(target: self, action: #selector(self.touched))
        touch.cancelsTouchesInView = false
        touch.delegate = self
        self.card.addGestureRecognizer(touch)

        self.bubble.isHidden = true
        self.bubbleBlur.isUserInteractionEnabled = false
        self.bubbleBlur.clipsToBounds = true
        self.bubbleBlur.layer.cornerRadius = self.bubbleSize / 2.0
        self.bubble.addSubview(self.bubbleBlur)
        self.bubbleLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.bubbleLabel.textAlignment = .center
        self.bubbleLabel.text = String(title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        self.bubble.addSubview(self.bubbleLabel)
        self.badge.layer.cornerRadius = 7.0
        self.badge.isHidden = true
        self.bubble.addSubview(self.badge)
        self.bubble.layer.shadowColor = UIColor.black.cgColor
        self.bubble.layer.shadowOpacity = 0.3
        self.bubble.layer.shadowRadius = 10.0
        self.bubble.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)
        self.bubble.addTarget(self, action: #selector(self.restorePressed), for: .touchUpInside)
        self.bubble.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.dragged(_:))))
        self.addSubview(self.bubble)

        self.apply(theme: theme)

        if let watchPeerId {
            self.messagesDisposable = (context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: watchPeerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 3, fixedCombinedReadStates: nil)
            |> map { view, _, _ -> EngineMessage.Id? in
                return view.entries.last(where: { $0.message.flags.contains(.Incoming) })?.message.id
            }
            |> distinctUntilChanged
            |> deliverOnMainQueue).startStrict(next: { [weak self] id in
                guard let self else {
                    return
                }
                self.latestMessage = id
                if self.minimized, let id, id != self.lastSeenMessage {
                    self.showBadge()
                }
            })
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.messagesDisposable?.dispose()
    }

    private func apply(theme: PresentationTheme) {
        let dark = theme.overallDarkAppearance
        self.card.backgroundColor = theme.list.plainBackgroundColor
        self.card.layer.borderColor = UIColor(white: dark ? 1.0 : 0.0, alpha: 0.12).cgColor
        self.bar.effect = UIBlurEffect(style: dark ? .systemThickMaterialDark : .systemThickMaterialLight)
        self.grabber.backgroundColor = theme.list.itemSecondaryTextColor.withAlphaComponent(0.5)
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        for button in [self.closeButton, self.minimizeButton, self.expandButton] {
            button.tintColor = theme.list.itemSecondaryTextColor
        }
        self.resizeHandle.backgroundColor = theme.list.itemBlocksBackgroundColor.withAlphaComponent(0.92)
        self.resizeGlyph.tintColor = theme.list.itemSecondaryTextColor
        self.bubbleBlur.effect = UIBlurEffect(style: dark ? .systemThickMaterialDark : .systemThickMaterialLight)
        self.bubbleLabel.textColor = theme.list.itemAccentColor
        self.badge.backgroundColor = theme.list.itemDestructiveColor
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func touched() {
        self.focus(self)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.minimized {
            guard !self.bubble.isHidden, self.bubble.frame.insetBy(dx: -6.0, dy: -6.0).contains(point) else {
                return nil
            }
            return self.bubble
        }
        if !self.resizeHandle.isHidden, self.resizeHandle.frame.insetBy(dx: -10.0, dy: -10.0).contains(point) {
            return self.resizeHandle
        }
        guard self.card.frame.contains(point) else {
            return nil
        }
        return super.hitTest(point, with: event) ?? self.card
    }

    private func limits(_ layout: ContainerViewLayout) -> (min: CGSize, max: CGSize) {
        let maxSize = CGSize(width: max(220.0, layout.size.width - layout.safeInsets.left - layout.safeInsets.right - 16.0), height: max(300.0, layout.size.height - (layout.statusBarHeight ?? 20.0) - layout.intrinsicInsets.bottom - 24.0))
        return (CGSize(width: min(200.0, maxSize.width), height: min(260.0, maxSize.height)), maxSize)
    }

    private func clamp(_ frame: CGRect, layout: ContainerViewLayout) -> CGRect {
        let (minSize, maxSize) = self.limits(layout)
        var result = frame
        result.size.width = min(max(result.width, minSize.width), maxSize.width)
        result.size.height = min(max(result.height, minSize.height), maxSize.height)
        let top = (layout.statusBarHeight ?? 20.0) + 6.0
        let bottom = layout.size.height - max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom) - 6.0
        let left = layout.safeInsets.left + 6.0
        let right = layout.size.width - layout.safeInsets.right - 6.0
        result.origin.x = min(max(result.minX, left), max(left, right - result.width))
        result.origin.y = min(max(result.minY, top), max(top, bottom - result.height))
        return result
    }

    func hostLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.hostLayout = layout
        self.frame = CGRect(origin: CGPoint(), size: layout.size)
        if !self.placed {
            self.placed = true
            let width = min(330.0, floor(layout.size.width * 0.78))
            let height = min(floor(width * 1.62), floor(layout.size.height * 0.62))
            let offset = CGFloat((self.superview?.subviews.count ?? 1) - 1) * 22.0
            self.cardFrame = CGRect(x: layout.size.width - layout.safeInsets.right - width - 12.0 - offset, y: (layout.statusBarHeight ?? 20.0) + 56.0 + offset, width: width, height: height)
        }
        self.cardFrame = self.clamp(self.cardFrame, layout: layout)
        var lift: CGFloat = 0.0
        if let inputHeight = layout.inputHeight, inputHeight > 0.0, !self.minimized, ayuFloatingContainsFirstResponder(self.contentHost) {
            let keyboardTop = layout.size.height - inputHeight - 8.0
            if self.cardFrame.maxY > keyboardTop {
                lift = self.cardFrame.maxY - keyboardTop
                lift = min(lift, max(0.0, self.cardFrame.minY - (layout.statusBarHeight ?? 20.0) - 6.0))
            }
        }
        self.keyboardLift = lift
        self.layoutCard(transition: transition)
    }

    private func layoutCard(transition: ContainedViewLayoutTransition) {
        guard let layout = self.hostLayout else {
            return
        }
        var frame = self.cardFrame
        frame.origin.y -= self.keyboardLift
        transition.updateFrame(view: self.card, frame: frame)
        transition.updateFrame(view: self.shadowView, frame: frame)
        self.shadowView.layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: frame.size), cornerRadius: 22.0).cgPath
        let size = frame.size
        self.bar.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: self.barHeight)
        self.grabber.frame = CGRect(x: (size.width - 36.0) / 2.0, y: 4.0, width: 36.0, height: 4.0)
        self.closeButton.frame = CGRect(x: 8.0, y: 6.0, width: 22.0, height: 22.0)
        self.minimizeButton.frame = CGRect(x: 34.0, y: 6.0, width: 22.0, height: 22.0)
        self.expandButton.frame = CGRect(x: size.width - 30.0, y: 6.0, width: 22.0, height: 22.0)
        self.titleLabel.frame = CGRect(x: 62.0, y: 11.0, width: max(0.0, size.width - 124.0), height: 16.0)
        let contentFrame = CGRect(x: 0.0, y: self.barHeight, width: size.width, height: max(1.0, size.height - self.barHeight))
        self.contentClip.frame = contentFrame
        let reference = max(320.0, min(layout.size.width, 430.0))
        let scale = min(1.0, contentFrame.width / reference)
        let virtual = CGSize(width: floor(contentFrame.width / scale), height: floor(contentFrame.height / scale))
        self.contentHost.transform = .identity
        self.contentHost.frame = CGRect(origin: CGPoint(), size: virtual)
        self.contentHost.transform = CGAffineTransform(scaleX: scale, y: scale)
        self.contentHost.layer.position = CGPoint()
        self.navigation.view.frame = CGRect(origin: CGPoint(), size: virtual)
        var inner = layout
        inner.size = virtual
        inner.metrics = LayoutMetrics(widthClass: .compact, heightClass: .regular, orientation: layout.metrics.orientation)
        inner.intrinsicInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 6.0, right: 0.0)
        inner.safeInsets = .zero
        inner.additionalInsets = .zero
        inner.reservedCorners = .none
        inner.division = nil
        inner.statusBarHeight = 0.0
        inner.inputHeight = nil
        inner.inputHeightIsInteractivellyChanging = false
        inner.presentedInFormSheet = false
        self.navigation.containerLayoutUpdated(inner, transition: transition)
        let handleFrame = CGRect(x: frame.maxX - 30.0, y: frame.maxY - 30.0, width: 26.0, height: 26.0)
        transition.updateFrame(view: self.resizeHandle, frame: handleFrame)
        self.resizeGlyph.frame = self.resizeHandle.bounds
        self.resizeGlyph.transform = CGAffineTransform(rotationAngle: .pi / 2.0)
        self.bubble.bounds = CGRect(x: 0.0, y: 0.0, width: self.bubbleSize, height: self.bubbleSize)
        self.bubbleBlur.frame = self.bubble.bounds
        self.bubbleLabel.frame = self.bubble.bounds
        self.badge.frame = CGRect(x: self.bubbleSize - 14.0, y: 0.0, width: 14.0, height: 14.0)
        self.bubble.layer.shadowPath = UIBezierPath(ovalIn: self.bubble.bounds).cgPath
        if self.bubbleCenter == nil {
            self.bubble.center = CGPoint(x: frame.maxX - self.bubbleSize / 2.0, y: frame.minY + self.bubbleSize / 2.0)
        }
    }

    func appear() {
        self.card.alpha = 0.0
        self.shadowView.alpha = 0.0
        self.card.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
            self.card.alpha = 1.0
            self.shadowView.alpha = 1.0
            self.card.transform = .identity
        })
    }

    private func showBadge() {
        guard self.badge.isHidden else {
            return
        }
        self.badge.isHidden = false
        self.badge.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: [], animations: {
            self.badge.transform = .identity
        })
        let jump = CAKeyframeAnimation(keyPath: "transform.translation.y")
        jump.values = [0.0, -8.0, 0.0, -4.0, 0.0]
        jump.duration = 0.6
        self.bubble.layer.add(jump, forKey: "jump")
    }

    @objc private func closePressed() {
        self.endEditing(true)
        UIView.animate(withDuration: 0.22, animations: {
            self.alpha = 0.0
            self.card.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        }, completion: { _ in
            self.close(self)
        })
    }

    @objc private func minimizePressed() {
        self.endEditing(true)
        self.minimized = true
        self.lastSeenMessage = self.latestMessage
        self.badge.isHidden = true
        self.bubble.isHidden = false
        self.bubble.alpha = 0.0
        self.bubble.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        if self.bubbleCenter == nil, let layout = self.hostLayout {
            let margin = self.bubbleSize / 2.0 + 8.0
            let center = CGPoint(x: layout.size.width - layout.safeInsets.right - margin, y: min(max(self.cardFrame.minY + margin, (layout.statusBarHeight ?? 20.0) + margin), layout.size.height - layout.intrinsicInsets.bottom - margin))
            self.bubbleCenter = center
            self.bubble.center = center
        }
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.0, options: [], animations: {
            self.card.alpha = 0.0
            self.shadowView.alpha = 0.0
            self.resizeHandle.alpha = 0.0
            self.card.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            self.bubble.alpha = 1.0
            self.bubble.transform = .identity
        }, completion: { _ in
            if self.minimized {
                self.card.isHidden = true
                self.shadowView.isHidden = true
                self.resizeHandle.isHidden = true
            }
        })
    }

    @objc private func restorePressed() {
        self.minimized = false
        self.badge.isHidden = true
        self.card.isHidden = false
        self.shadowView.isHidden = false
        self.resizeHandle.isHidden = false
        self.focus(self)
        UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [], animations: {
            self.card.alpha = 1.0
            self.shadowView.alpha = 1.0
            self.resizeHandle.alpha = 1.0
            self.card.transform = .identity
            self.bubble.alpha = 0.0
            self.bubble.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        }, completion: { _ in
            if !self.minimized {
                self.bubble.isHidden = true
            }
        })
    }

    @objc private func expandPressed() {
        guard let openFull = self.openFull else {
            return
        }
        self.endEditing(true)
        openFull()
        self.close(self)
    }

    @objc private func barDoubleTapped() {
        guard let layout = self.hostLayout else {
            return
        }
        let (minSize, maxSize) = self.limits(layout)
        let large = self.cardFrame.width < maxSize.width * 0.8
        var frame = self.cardFrame
        if large {
            frame.size = CGSize(width: maxSize.width, height: min(maxSize.height, floor(maxSize.width * 1.6)))
        } else {
            let width = max(minSize.width, min(330.0, floor(layout.size.width * 0.78)))
            frame.size = CGSize(width: width, height: min(floor(width * 1.62), floor(layout.size.height * 0.62)))
        }
        self.cardFrame = self.clamp(frame, layout: layout)
        self.layoutCard(transition: .animated(duration: 0.35, curve: .spring))
    }

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        guard let layout = self.hostLayout else {
            return
        }
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(CGPoint(), in: self)
        if recognizer.state == .began {
            self.focus(self)
        }
        if self.minimized {
            self.bubble.center = CGPoint(x: self.bubble.center.x + translation.x, y: self.bubble.center.y + translation.y)
            if recognizer.state == .ended || recognizer.state == .cancelled {
                let margin = self.bubbleSize / 2.0 + 8.0
                let left = self.bubble.center.x < layout.size.width / 2.0
                let x = left ? layout.safeInsets.left + margin : layout.size.width - layout.safeInsets.right - margin
                let y = min(max(self.bubble.center.y, (layout.statusBarHeight ?? 20.0) + margin), layout.size.height - layout.intrinsicInsets.bottom - margin)
                self.bubbleCenter = CGPoint(x: x, y: y)
                UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.0, options: [], animations: {
                    self.bubble.center = CGPoint(x: x, y: y)
                })
            }
            return
        }
        self.cardFrame.origin.x += translation.x
        self.cardFrame.origin.y += translation.y
        if recognizer.state == .ended || recognizer.state == .cancelled {
            self.cardFrame = self.clamp(self.cardFrame, layout: layout)
            self.layoutCard(transition: .animated(duration: 0.35, curve: .spring))
        } else {
            self.layoutCard(transition: .immediate)
        }
    }

    @objc private func resized(_ recognizer: UIPanGestureRecognizer) {
        guard let layout = self.hostLayout else {
            return
        }
        switch recognizer.state {
        case .began:
            self.focus(self)
            self.resizeStart = self.cardFrame
        case .changed:
            guard let start = self.resizeStart else {
                return
            }
            let translation = recognizer.translation(in: self)
            let (minSize, maxSize) = self.limits(layout)
            var frame = start
            frame.size.width = min(max(start.width + translation.x, minSize.width), maxSize.width)
            frame.size.height = min(max(start.height + translation.y, minSize.height), maxSize.height)
            self.cardFrame = frame
            self.layoutCard(transition: .immediate)
        default:
            self.resizeStart = nil
            self.cardFrame = self.clamp(self.cardFrame, layout: layout)
            self.layoutCard(transition: .animated(duration: 0.3, curve: .spring))
        }
    }

    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        guard let layout = self.hostLayout else {
            return
        }
        switch recognizer.state {
        case .began:
            self.resizeStart = self.cardFrame
        case .changed:
            guard let start = self.resizeStart else {
                return
            }
            let (minSize, maxSize) = self.limits(layout)
            let width = min(max(start.width * recognizer.scale, minSize.width), maxSize.width)
            let height = min(max(start.height * recognizer.scale, minSize.height), maxSize.height)
            self.cardFrame = CGRect(x: start.midX - width / 2.0, y: start.midY - height / 2.0, width: width, height: height)
            self.layoutCard(transition: .immediate)
        default:
            self.resizeStart = nil
            self.cardFrame = self.clamp(self.cardFrame, layout: layout)
            self.layoutCard(transition: .animated(duration: 0.3, curve: .spring))
        }
    }
}

private var ayuGramFloatingHost: AyuGramFloatingHostController?

private func ayuGramFloatingPresent(context: AccountContext, key: String, title: String, watchPeerId: EnginePeer.Id?, makeRoot: () -> ViewController?, openFull: (() -> Void)?) {
    guard let rootNavigation = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return
    }
    if let host = ayuGramFloatingHost, let existing = host.panels.first(where: { $0.key == key }) {
        host.bringToFront(existing)
        return
    }
    guard let root = makeRoot() else {
        return
    }
    let host: AyuGramFloatingHostController
    if let current = ayuGramFloatingHost {
        host = current
    } else {
        host = AyuGramFloatingHostController()
        ayuGramFloatingHost = host
        rootNavigation.presentOverlay(controller: host, inGlobal: false, blockInteraction: false)
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let panel = AyuGramFloatingPanel(context: context, key: key, title: title, root: root, watchPeerId: watchPeerId, theme: presentationData.theme, openFull: openFull, close: { panel in
        guard let host = ayuGramFloatingHost else {
            return
        }
        host.remove(panel)
        if host.panels.isEmpty {
            ayuGramFloatingHost = nil
            host.dismiss()
        }
    }, focus: { panel in
        ayuGramFloatingHost?.bringToFront(panel)
    })
    host.add(panel)
    panel.appear()
}

public func ayuGramOpenFloatingChat(context: AccountContext, peerId: EnginePeer.Id, title: String, isGroup: Bool, openChat: @escaping () -> Void) {
    ayuGramFloatingPresent(context: context, key: "chat:\(peerId.toInt64())", title: title, watchPeerId: peerId, makeRoot: {
        return context.sharedContext.makeChatController(context: context, chatLocation: .peer(id: peerId), subject: nil, botStart: nil, mode: .standard(.default), params: nil)
    }, openFull: openChat)
}

public func ayuGramOpenFloatingProfile(context: AccountContext, peer: EnginePeer, openFull: @escaping () -> Void) {
    ayuGramFloatingPresent(context: context, key: "profile:\(peer.id.toInt64())", title: peer.compactDisplayTitle, watchPeerId: nil, makeRoot: {
        return context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil)
    }, openFull: openFull)
}
