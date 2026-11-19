import Foundation
import UIKit
import AsyncDisplayKit
import Display

struct LegacyNavigationBarInlineTransitionState {
    weak var counterpart: LegacyNavigationBarNode?
    let role: NavigationBarTransitionRole
    let progress: CGFloat
}

private let legacyInlineTransitionPositionKey = "legacyNavigationBar.inlineTransition.position"
private let legacyInlineTransitionOpacityKey = "legacyNavigationBar.inlineTransition.opacity"

private struct LegacyInlineTransitionItem {
    let layer: CALayer
    let frame: CGRect
    let alpha: CGFloat
}

extension LegacyNavigationBarNode: NavigationBarInlineTransitionParticipant {
    public func updateInlineTransition(counterpart: NavigationBar, role: NavigationBarTransitionRole, progress: CGFloat) {
        self.setInlineTransition(counterpart: counterpart as? LegacyNavigationBarNode, role: role, progress: progress)
        self.removeInlineTransitionAnimations()
        self.applyInlineTransitionLayout()
    }

    public func animateInlineTransition(counterpart: NavigationBar, role: NavigationBarTransitionRole, progresses: [CGFloat], timing: NavigationKeyframeTiming) {
        guard let lastProgress = progresses.last else {
            return
        }
        self.setInlineTransition(counterpart: counterpart as? LegacyNavigationBarNode, role: role, progress: lastProgress)
        self.removeInlineTransitionAnimations()
        guard self.inlineTransitionState != nil else {
            return
        }
        let samples = progresses.map { self.inlineTransitionLayout(progress: $0) }
        guard let finalSample = samples.last else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in finalSample {
            item.layer.frame = item.frame
            item.layer.opacity = Float(item.alpha)
        }
        CATransaction.commit()
        guard samples.allSatisfy({ $0.count == finalSample.count }) else {
            return
        }
        for index in 0 ..< finalSample.count {
            let layer = finalSample[index].layer
            let anchorPoint = layer.anchorPoint
            let positions: [Any] = samples.map { sample -> Any in
                let frame = sample[index].frame
                return NSValue(cgPoint: CGPoint(x: frame.minX + frame.width * anchorPoint.x, y: frame.minY + frame.height * anchorPoint.y))
            }
            let opacities: [Any] = samples.map { sample -> Any in
                return NSNumber(value: Float(sample[index].alpha))
            }
            addNavigationKeyframes(to: layer, key: legacyInlineTransitionPositionKey, keyPath: "position", values: positions, timing: timing)
            addNavigationKeyframes(to: layer, key: legacyInlineTransitionOpacityKey, keyPath: "opacity", values: opacities, timing: timing)
        }
    }

    public func endInlineTransition() {
        self.removeInlineTransitionAnimations()
        self.setInlineTransition(counterpart: nil, role: .top, progress: 0.0)
        if self.validLayout != nil {
            self.requestLayout()
            self.layout()
        }
    }

    func applyInlineTransitionLayout() {
        guard let inlineTransitionState = self.inlineTransitionState else {
            return
        }
        for item in self.inlineTransitionLayout(progress: inlineTransitionState.progress) {
            item.layer.frame = item.frame
            item.layer.opacity = Float(item.alpha)
        }
    }

    private func setInlineTransition(counterpart: LegacyNavigationBarNode?, role: NavigationBarTransitionRole, progress: CGFloat) {
        let previousState = self.inlineTransitionState
        let updateNodes = previousState?.counterpart !== counterpart || previousState?.role != role

        if let counterpart = counterpart {
            self.inlineTransitionState = LegacyNavigationBarInlineTransitionState(counterpart: counterpart, role: role, progress: progress)
        } else {
            self.inlineTransitionState = nil
        }

        if !updateNodes {
            return
        }

        if let inlineTransitionTitleNode = self.inlineTransitionTitleNode {
            inlineTransitionTitleNode.removeFromSupernode()
            self.inlineTransitionTitleNode = nil
        }
        if let inlineTransitionBackButtonNode = self.inlineTransitionBackButtonNode {
            inlineTransitionBackButtonNode.removeFromSupernode()
            self.inlineTransitionBackButtonNode = nil
        }
        if let inlineTransitionBackArrowNode = self.inlineTransitionBackArrowNode {
            inlineTransitionBackArrowNode.removeFromSupernode()
            self.inlineTransitionBackArrowNode = nil
        }
        if let inlineTransitionBadgeNode = self.inlineTransitionBadgeNode {
            inlineTransitionBadgeNode.removeFromSupernode()
            self.inlineTransitionBadgeNode = nil
        }

        guard let counterpart = counterpart else {
            return
        }

        switch role {
        case .top:
            if let transitionTitleNode = counterpart.makeInlineTransitionTitleNode(foregroundColor: self.presentationData.theme.primaryTextColor) {
                self.inlineTransitionTitleNode = transitionTitleNode
                if self.leftButtonNode.supernode != nil {
                    self.buttonsContainerNode.insertSubnode(transitionTitleNode, belowSubnode: self.leftButtonNode)
                } else if self.backButtonNode.supernode != nil {
                    self.buttonsContainerNode.insertSubnode(transitionTitleNode, belowSubnode: self.backButtonNode)
                } else {
                    self.buttonsContainerNode.addSubnode(transitionTitleNode)
                }
            }
        case .bottom:
            if let transitionBackButtonNode = counterpart.makeInlineTransitionBackButtonNode(accentColor: self.presentationData.theme.buttonColor) {
                self.inlineTransitionBackButtonNode = transitionBackButtonNode
                self.buttonsContainerNode.addSubnode(transitionBackButtonNode)
            }
            if let transitionBackArrowNode = counterpart.makeInlineTransitionBackArrowNode(accentColor: self.presentationData.theme.buttonColor) {
                self.inlineTransitionBackArrowNode = transitionBackArrowNode
                self.buttonsContainerNode.addSubnode(transitionBackArrowNode)
            }
            if let transitionBadgeNode = counterpart.makeInlineTransitionBadgeNode() {
                self.inlineTransitionBadgeNode = transitionBadgeNode
                self.buttonsContainerNode.addSubnode(transitionBadgeNode)
            }
        }
    }

    private func removeInlineTransitionAnimations() {
        var layers: [CALayer] = [self.backButtonNode.layer, self.backButtonArrow.layer, self.badgeNode.layer, self.titleNode.layer]
        if let titleView = self.titleView {
            layers.append(titleView.layer)
        }
        if let inlineTransitionTitleNode = self.inlineTransitionTitleNode {
            layers.append(inlineTransitionTitleNode.layer)
        }
        if let inlineTransitionBackButtonNode = self.inlineTransitionBackButtonNode {
            layers.append(inlineTransitionBackButtonNode.layer)
        }
        if let inlineTransitionBackArrowNode = self.inlineTransitionBackArrowNode {
            layers.append(inlineTransitionBackArrowNode.layer)
        }
        if let inlineTransitionBadgeNode = self.inlineTransitionBadgeNode {
            layers.append(inlineTransitionBadgeNode.layer)
        }
        for layer in layers {
            layer.removeAnimation(forKey: legacyInlineTransitionPositionKey)
            layer.removeAnimation(forKey: legacyInlineTransitionOpacityKey)
        }
    }

    private func inlineTransitionLayout(progress: CGFloat) -> [LegacyInlineTransitionItem] {
        guard let inlineTransitionState = self.inlineTransitionState, let layout = self.validLayout else {
            return []
        }
        let size = layout.size
        let nominalHeight = layout.defaultHeight
        let leftInset = layout.leftInset
        let contentVerticalOrigin = layout.additionalTopHeight
        let leftButtonInset: CGFloat = leftInset + 16.0
        let backButtonInset: CGFloat = leftInset + 27.0

        var result: [LegacyInlineTransitionItem] = []

        switch inlineTransitionState.role {
        case .top:
            if self.backButtonNode.supernode != nil {
                let backButtonSize = self.backButtonNode.bounds.size
                let backButtonInitialX: CGFloat = backButtonInset
                let backButtonFinalX: CGFloat = floor((size.width - backButtonSize.width) / 2.0) - size.width
                result.append(LegacyInlineTransitionItem(layer: self.backButtonNode.layer, frame: CGRect(origin: CGPoint(x: backButtonInitialX * (1.0 - progress) + backButtonFinalX * progress, y: contentVerticalOrigin + floor((nominalHeight - backButtonSize.height) / 2.0)), size: backButtonSize), alpha: 1.0))

                if let inlineTransitionTitleNode = self.inlineTransitionTitleNode {
                    let transitionTitleSize = inlineTransitionTitleNode.bounds.size
                    let initialX: CGFloat = backButtonInset + floor((backButtonSize.width - transitionTitleSize.width) / 2.0)
                    let finalX: CGFloat = floor((size.width - transitionTitleSize.width) / 2.0) - size.width
                    result.append(LegacyInlineTransitionItem(layer: inlineTransitionTitleNode.layer, frame: CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floor((nominalHeight - transitionTitleSize.height) / 2.0)), size: transitionTitleSize), alpha: progress * progress))
                }

                let arrowFrame = CGRect(origin: CGPoint(x: leftInset + 8.0 - progress * size.width, y: contentVerticalOrigin + floor((nominalHeight - 22.0) / 2.0)), size: CGSize(width: 13.0, height: 22.0))
                let arrowAlpha = max(0.0, 1.0 - progress * 1.3)
                result.append(LegacyInlineTransitionItem(layer: self.backButtonArrow.layer, frame: arrowFrame, alpha: arrowAlpha))
                result.append(LegacyInlineTransitionItem(layer: self.badgeNode.layer, frame: CGRect(origin: arrowFrame.origin.offsetBy(dx: 16.0, dy: 2.0), size: self.badgeNode.bounds.size), alpha: arrowAlpha))
            }

            if self.titleNode.supernode != nil {
                let titleSize = self.titleNode.bounds.size
                let initialX = floor((size.width - titleSize.width) / 2.0)
                let finalX: CGFloat = leftButtonInset
                result.append(LegacyInlineTransitionItem(layer: self.titleNode.layer, frame: CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize), alpha: (1.0 - progress) * (1.0 - progress)))
            }

            if let titleView = self.titleView {
                let titleViewFrame = titleView.layer.frame
                let initialX = floor((size.width - titleViewFrame.width) / 2.0)
                let finalX: CGFloat = leftButtonInset
                result.append(LegacyInlineTransitionItem(layer: titleView.layer, frame: CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: titleViewFrame.minY), size: titleViewFrame.size), alpha: (1.0 - progress) * (1.0 - progress)))
            }
        case .bottom:
            if let inlineTransitionBackButtonNode = self.inlineTransitionBackButtonNode {
                let transitionBackButtonSize = inlineTransitionBackButtonNode.bounds.size
                let initialX: CGFloat = backButtonInset + size.width * 0.3
                let finalX: CGFloat = floor((size.width - transitionBackButtonSize.width) / 2.0)
                result.append(LegacyInlineTransitionItem(layer: inlineTransitionBackButtonNode.layer, frame: CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floor((nominalHeight - transitionBackButtonSize.height) / 2.0)), size: transitionBackButtonSize), alpha: (1.0 - progress) * (1.0 - progress)))
            }

            if let inlineTransitionBackArrowNode = self.inlineTransitionBackArrowNode {
                let initialX: CGFloat = leftInset + 8.0 + size.width * 0.3
                let finalX: CGFloat = leftInset + 8.0
                let arrowFrame = CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floor((nominalHeight - 22.0) / 2.0)), size: CGSize(width: 13.0, height: 22.0))
                let arrowAlpha = max(0.0, 1.0 - progress * 1.3)
                result.append(LegacyInlineTransitionItem(layer: inlineTransitionBackArrowNode.layer, frame: arrowFrame, alpha: arrowAlpha))
                if let inlineTransitionBadgeNode = self.inlineTransitionBadgeNode {
                    result.append(LegacyInlineTransitionItem(layer: inlineTransitionBadgeNode.layer, frame: CGRect(origin: arrowFrame.origin.offsetBy(dx: 16.0, dy: 2.0), size: inlineTransitionBadgeNode.bounds.size), alpha: arrowAlpha))
                }
            }

            var counterpartBackButtonWidth: CGFloat?
            if let counterpart = inlineTransitionState.counterpart, counterpart.backButtonNode.supernode != nil {
                counterpartBackButtonWidth = counterpart.backButtonNode.bounds.width
            }

            if self.titleNode.supernode != nil {
                let titleSize = self.titleNode.bounds.size
                var initialX: CGFloat = backButtonInset
                if let counterpartBackButtonWidth = counterpartBackButtonWidth {
                    initialX += floor((counterpartBackButtonWidth - titleSize.width) / 2.0)
                }
                initialX += size.width * 0.3
                let finalX: CGFloat = floor((size.width - titleSize.width) / 2.0)
                result.append(LegacyInlineTransitionItem(layer: self.titleNode.layer, frame: CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize), alpha: progress * progress))
            }

            if let titleView = self.titleView {
                let titleViewFrame = titleView.layer.frame
                var initialX: CGFloat = backButtonInset
                if let counterpartBackButtonWidth = counterpartBackButtonWidth {
                    initialX += floor((counterpartBackButtonWidth - titleViewFrame.width) / 2.0)
                }
                initialX += size.width * 0.3
                let finalX: CGFloat = floor((size.width - titleViewFrame.width) / 2.0)
                result.append(LegacyInlineTransitionItem(layer: titleView.layer, frame: CGRect(origin: CGPoint(x: initialX * (1.0 - progress) + finalX * progress, y: titleViewFrame.minY), size: titleViewFrame.size), alpha: progress * progress))
            }
        }

        return result
    }

    func makeInlineTransitionTitleNode(foregroundColor: UIColor) -> ASDisplayNode? {
        guard let validLayout = self.validLayout else {
            return nil
        }
        let constrainedSize = CGSize(width: validLayout.size.width, height: validLayout.defaultHeight)
        if let titleView = self.titleView {
            guard let transitionView = titleView as? NavigationBarTitleTransitionNode else {
                return nil
            }
            let node = transitionView.makeTransitionMirrorNode()
            let nodeSize = node.measure(constrainedSize)
            node.frame = CGRect(origin: CGPoint(), size: nodeSize)
            return node
        } else if let title = self.title {
            let node = ImmediateTextNode()
            node.displaysAsynchronously = false
            node.maximumNumberOfLines = 1
            node.attributedText = NSAttributedString(string: title, font: LegacyNavigationBarNode.titleFont, textColor: foregroundColor)
            let nodeSize = node.updateLayout(constrainedSize)
            node.frame = CGRect(origin: CGPoint(), size: nodeSize)
            return node
        } else {
            return nil
        }
    }

    func makeInlineTransitionBackButtonNode(accentColor: UIColor) -> LegacyNavigationButtonNode? {
        guard self.backButtonNode.supernode != nil else {
            return nil
        }
        let node = LegacyNavigationButtonNode(strings: self.presentationData.strings)
        node.isUserInteractionEnabled = false
        node.manualAlpha = self.backButtonNode.manualAlpha
        node.updateManualText(self.backButtonNode.manualText)
        node.color = accentColor
        if let validLayout = self.validLayout {
            let _ = node.updateLayout(constrainedSize: CGSize(width: validLayout.size.width, height: validLayout.defaultHeight), isLandscape: validLayout.isLandscape, isLeftAligned: true)
            node.frame = self.backButtonNode.frame
        }
        return node
    }

    func makeInlineTransitionBackArrowNode(accentColor: UIColor) -> ASDisplayNode? {
        guard self.backButtonArrow.supernode != nil else {
            return nil
        }
        let node = ASImageNode()
        node.image = navigationBarBackArrowImage(color: accentColor)
        node.frame = self.backButtonArrow.frame
        node.displayWithoutProcessing = true
        node.displaysAsynchronously = false
        node.isUserInteractionEnabled = false
        return node
    }

    func makeInlineTransitionBadgeNode() -> ASDisplayNode? {
        guard self.badgeNode.supernode != nil, !self.badgeNode.isHidden else {
            return nil
        }
        let node = LegacyNavigationBarBadgeNode(fillColor: self.presentationData.theme.buttonColor, strokeColor: self.presentationData.theme.buttonColor, textColor: self.presentationData.theme.badgeTextColor)
        node.isUserInteractionEnabled = false
        node.text = self.badgeNode.text
        let nodeSize = node.measure(CGSize(width: 200.0, height: 100.0))
        node.frame = CGRect(origin: CGPoint(), size: nodeSize)
        return node
    }
}
