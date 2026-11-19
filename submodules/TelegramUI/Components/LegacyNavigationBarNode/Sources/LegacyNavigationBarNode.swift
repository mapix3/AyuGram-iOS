import Foundation
import UIKit
import AsyncDisplayKit
import Display

public final class LegacyNavigationBarNode: ASDisplayNode, NavigationBar {
    struct Layout {
        var size: CGSize
        var defaultHeight: CGFloat
        var additionalTopHeight: CGFloat
        var additionalContentHeight: CGFloat
        var additionalBackgroundHeight: CGFloat
        var leftInset: CGFloat
        var rightInset: CGFloat
        var appearsHidden: Bool
        var isLandscape: Bool
    }

    public static let titleFont = Font.with(size: 17.0, design: .regular, weight: .semibold, traits: [.monospacedNumbers])
    public static let defaultSecondaryContentHeight: CGFloat = 38.0

    private(set) var presentationData: NavigationBarPresentationData

    private(set) var validLayout: Layout?
    private var requestedLayout: Bool = false
    public var requestContainerLayout: ((ContainedViewLayoutTransition) -> Void)?

    public var backPressed: () -> Void = { }

    public var userInfo: Any?

    public let stripeNode: ASDisplayNode
    public let clippingNode: SparseNode
    let buttonsContainerNode: ASDisplayNode
    public let customOverBackgroundContentView: UIView

    public private(set) var contentNode: NavigationBarContentNode?
    public private(set) var secondaryContentNode: ASDisplayNode?

    private var itemTitleListenerKey: Int?
    private var itemTitleViewListenerKey: Int?

    private var itemLeftButtonListenerKey: Int?

    private var itemRightButtonListenerKey: Int?
    private var itemRightButtonsListenerKey: Int?

    private var itemBadgeListenerKey: Int?

    private var _item: UINavigationItem?
    public var item: UINavigationItem? {
        get {
            return self._item
        } set(value) {
            if let previousValue = self._item {
                if let itemTitleListenerKey = self.itemTitleListenerKey {
                    previousValue.removeSetTitleListener(itemTitleListenerKey)
                    self.itemTitleListenerKey = nil
                }

                if let itemTitleViewListenerKey = self.itemTitleViewListenerKey {
                    previousValue.removeSetTitleViewListener(itemTitleViewListenerKey)
                    self.itemTitleViewListenerKey = nil
                }

                if let itemLeftButtonListenerKey = self.itemLeftButtonListenerKey {
                    previousValue.removeSetLeftBarButtonItemListener(itemLeftButtonListenerKey)
                    self.itemLeftButtonListenerKey = nil
                }

                if let itemRightButtonListenerKey = self.itemRightButtonListenerKey {
                    previousValue.removeSetRightBarButtonItemListener(itemRightButtonListenerKey)
                    self.itemRightButtonListenerKey = nil
                }

                if let itemRightButtonsListenerKey = self.itemRightButtonsListenerKey {
                    previousValue.removeSetMultipleRightBarButtonItemsListener(itemRightButtonsListenerKey)
                    self.itemRightButtonsListenerKey = nil
                }

                if let itemBadgeListenerKey = self.itemBadgeListenerKey {
                    previousValue.removeSetBadgeListener(itemBadgeListenerKey)
                    self.itemBadgeListenerKey = nil
                }
            }
            self._item = value

            self.leftButtonNode.removeFromSupernode()
            self.rightButtonNode.removeFromSupernode()

            if let item = value {
                self.title = item.title
                self.itemTitleListenerKey = item.addSetTitleListener { [weak self] text, animated in
                    if let strongSelf = self {
                        let animateIn = animated && (strongSelf.title?.isEmpty ?? true)
                        strongSelf.title = text
                        if animateIn {
                            strongSelf.titleNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                        }
                    }
                }

                self.setTitleView(item.titleView)
                self.itemTitleViewListenerKey = item.addSetTitleViewListener { [weak self] titleView in
                    if let strongSelf = self {
                        strongSelf.setTitleView(titleView)
                    }
                }

                self.itemLeftButtonListenerKey = item.addSetLeftBarButtonItemListener { [weak self] _, _, animated in
                    if let strongSelf = self {
                        strongSelf.updateLeftButton(animated: animated)
                        strongSelf.invalidateCalculatedLayout()
                        strongSelf.requestLayout()
                    }
                }

                self.itemRightButtonListenerKey = item.addSetRightBarButtonItemListener { [weak self] _, _, animated in
                    if let strongSelf = self {
                        strongSelf.updateRightButton(animated: animated)
                        strongSelf.invalidateCalculatedLayout()
                        strongSelf.requestLayout()
                    }
                }

                self.itemRightButtonsListenerKey = item.addSetMultipleRightBarButtonItemsListener { [weak self] _, animated in
                    if let strongSelf = self {
                        strongSelf.updateRightButton(animated: animated)
                        strongSelf.invalidateCalculatedLayout()
                        strongSelf.requestLayout()
                    }
                }

                self.itemBadgeListenerKey = item.addSetBadgeListener { [weak self] text in
                    if let strongSelf = self {
                        strongSelf.updateBadgeText(text: text)
                    }
                }
                self.updateBadgeText(text: item.badge)

                self.updateLeftButton(animated: false)
                self.updateRightButton(animated: false)
            } else {
                self.title = nil
                self.setTitleView(nil)
                self.updateLeftButton(animated: false)
                self.updateRightButton(animated: false)
            }
            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }

    private(set) var title: String? {
        didSet {
            if let title = self.title {
                self.titleNode.attributedText = NSAttributedString(string: title, font: LegacyNavigationBarNode.titleFont, textColor: self.presentationData.theme.primaryTextColor)
                self.titleNode.accessibilityLabel = title
                if self.titleNode.supernode == nil {
                    self.buttonsContainerNode.addSubnode(self.titleNode)
                }
            } else {
                self.titleNode.removeFromSupernode()
            }

            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }

    public private(set) var titleView: UIView?

    private func setTitleView(_ titleView: UIView?) {
        if self.titleView === titleView {
            return
        }
        if let previous = self.titleView {
            (previous as? NavigationBarTitleView)?.requestUpdate = nil
            if previous.superview === self.buttonsContainerNode.view {
                previous.removeFromSuperview()
            }
        }
        self.titleView = titleView
        if let titleView = titleView {
            self.buttonsContainerNode.view.addSubview(titleView)
            if let titleView = titleView as? NavigationBarTitleView {
                titleView.requestUpdate = { [weak self, weak titleView] transition in
                    guard let strongSelf = self, let titleView = titleView, strongSelf.titleView === titleView else {
                        return
                    }
                    if let requestContainerLayout = strongSelf.requestContainerLayout {
                        requestContainerLayout(transition)
                    } else {
                        strongSelf.requestLayout()
                    }
                }
            }
        }

        self.invalidateCalculatedLayout()
        self.requestLayout()
    }

    let titleNode: ImmediateTextNode

    var inlineTransitionState: LegacyNavigationBarInlineTransitionState?
    var inlineTransitionTitleNode: ASDisplayNode?
    var inlineTransitionBackButtonNode: LegacyNavigationButtonNode?
    var inlineTransitionBackArrowNode: ASDisplayNode?
    var inlineTransitionBadgeNode: ASDisplayNode?

    private var previousItemListenerKey: Int?
    private var previousItemBackListenerKey: Int?

    override public var accessibilityElements: [Any]? {
        get {
            var accessibilityElements: [Any] = []
            if !self.buttonsContainerNode.alpha.isZero {
                if self.backButtonNode.supernode != nil {
                    addAccessibilityChildren(of: self.backButtonNode, container: self, to: &accessibilityElements)
                }
                if self.leftButtonNode.supernode != nil {
                    addAccessibilityChildren(of: self.leftButtonNode, container: self, to: &accessibilityElements)
                }
                if self.titleNode.supernode != nil {
                    addAccessibilityChildren(of: self.titleNode, container: self, to: &accessibilityElements)
                    accessibilityElements.append(self.titleNode)
                }
                if let titleView = self.titleView, titleView.superview != nil {
                    titleView.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(titleView.bounds, in: titleView)
                    accessibilityElements.append(titleView)
                }
                if self.rightButtonNode.supernode != nil {
                    addAccessibilityChildren(of: self.rightButtonNode, container: self, to: &accessibilityElements)
                }
            }
            if let contentNode = self.contentNode {
                addAccessibilityChildren(of: contentNode, container: self, to: &accessibilityElements)
            }
            if let secondaryContentNode = self.secondaryContentNode {
                addAccessibilityChildren(of: secondaryContentNode, container: self, to: &accessibilityElements)
            }
            if !self.customOverBackgroundContentView.isHidden, self.customOverBackgroundContentView.alpha > 0.01 {
                var overBackgroundElements: [UIView] = []
                LegacyNavigationBarNode.collectAccessibilityElements(in: self.customOverBackgroundContentView, to: &overBackgroundElements)
                overBackgroundElements.sort { lhs, rhs in
                    let lhsFrame = lhs.convert(lhs.bounds, to: nil)
                    let rhsFrame = rhs.convert(rhs.bounds, to: nil)
                    if abs(lhsFrame.minY - rhsFrame.minY) > 1.0 {
                        return lhsFrame.minY < rhsFrame.minY
                    }
                    return lhsFrame.minX < rhsFrame.minX
                }
                accessibilityElements.append(contentsOf: overBackgroundElements)
            }
            return accessibilityElements
        } set(value) {
        }
    }

    private static func collectAccessibilityElements(in view: UIView, to elements: inout [UIView]) {
        for subview in view.subviews {
            if subview.isHidden || subview.alpha < 0.01 || subview.accessibilityElementsHidden {
                continue
            }
            if subview.isAccessibilityElement || subview.accessibilityElements != nil {
                elements.append(subview)
            } else {
                LegacyNavigationBarNode.collectAccessibilityElements(in: subview, to: &elements)
            }
        }
    }

    public var enableAutomaticBackButton: Bool = true

    public var hidesBackButton: Bool = false {
        didSet {
            if self.hidesBackButton != oldValue {
                self.updateLeftButton(animated: false)
                self.invalidateCalculatedLayout()
                self.requestLayout()
            }
        }
    }

    private var _previousItem: NavigationPreviousAction?
    public var previousItem: NavigationPreviousAction? {
        get {
            if !self.enableAutomaticBackButton {
                return nil
            }
            return self._previousItem
        } set(value) {
            if !self.enableAutomaticBackButton {
                self._previousItem = nil
                return
            }
            if self._previousItem != value {
                if let previousValue = self._previousItem, case let .item(itemValue) = previousValue {
                    if let previousItemListenerKey = self.previousItemListenerKey {
                        itemValue.removeSetTitleListener(previousItemListenerKey)
                        self.previousItemListenerKey = nil
                    }
                    if let previousItemBackListenerKey = self.previousItemBackListenerKey {
                        itemValue.removeSetBackBarButtonItemListener(previousItemBackListenerKey)
                        self.previousItemBackListenerKey = nil
                    }
                }
                self._previousItem = value

                if let previousItem = value {
                    switch previousItem {
                    case let .item(itemValue):
                        self.previousItemListenerKey = itemValue.addSetTitleListener { [weak self] _, _ in
                            if let strongSelf = self, let previousItem = strongSelf.previousItem, case let .item(itemValue) = previousItem {
                                if let backBarButtonItem = itemValue.backBarButtonItem {
                                    strongSelf.backButtonNode.updateManualText(backBarButtonItem.title ?? "", isBack: true)
                                } else {
                                    strongSelf.backButtonNode.updateManualText(itemValue.title ?? "", isBack: true)
                                }
                                strongSelf.invalidateCalculatedLayout()
                                strongSelf.requestLayout()
                            }
                        }

                        self.previousItemBackListenerKey = itemValue.addSetBackBarButtonItemListener { [weak self] _, _, _ in
                            if let strongSelf = self, let previousItem = strongSelf.previousItem, case let .item(itemValue) = previousItem {
                                if let backBarButtonItem = itemValue.backBarButtonItem {
                                    strongSelf.backButtonNode.updateManualText(backBarButtonItem.title ?? "", isBack: true)
                                } else {
                                    strongSelf.backButtonNode.updateManualText(itemValue.title ?? "", isBack: true)
                                }
                                strongSelf.invalidateCalculatedLayout()
                                strongSelf.requestLayout()
                            }
                        }
                    case .close:
                        break
                    }
                }
                self.updateLeftButton(animated: false)

                self.invalidateCalculatedLayout()
                self.requestLayout()
            }
        }
    }

    private var effectivePreviousItem: NavigationPreviousAction? {
        if self.hidesBackButton {
            return nil
        }
        return self.previousItem
    }

    private func updateBadgeText(text: String?) {
        let actualText = text ?? ""
        if self.badgeNode.text != actualText {
            self.badgeNode.text = actualText
            self.badgeNode.isHidden = actualText.isEmpty
            self.backButtonNode.manualAlpha = self.badgeNode.isHidden ? 1.0 : 0.0

            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }

    private func fadeOutSnapshot(of node: ASDisplayNode) {
        if node.isNodeLoaded, node.view.superview != nil {
            if let snapshotView = node.view.snapshotContentTree() {
                snapshotView.frame = node.frame
                node.view.superview?.insertSubview(snapshotView, aboveSubview: node.view)
                snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                    snapshotView?.removeFromSuperview()
                })
            }
        }
    }

    private func updateLeftButton(animated: Bool) {
        if let item = self.item {
            let previousItem = self.effectivePreviousItem

            var needsLeftButton = false
            if let leftBarButtonItem = item.leftBarButtonItem, !leftBarButtonItem.backButtonAppearance {
                needsLeftButton = true
            } else if item.leftBarButtonItem == nil, let previousItem = previousItem, case .close = previousItem {
                needsLeftButton = true
            }

            if needsLeftButton {
                if animated {
                    self.fadeOutSnapshot(of: self.backButtonNode)
                    self.fadeOutSnapshot(of: self.backButtonArrow)
                    self.fadeOutSnapshot(of: self.badgeNode)
                }

                self.backButtonNode.removeFromSupernode()
                self.backButtonArrow.removeFromSupernode()
                self.badgeNode.removeFromSupernode()

                if let leftBarButtonItem = item.leftBarButtonItem {
                    self.leftButtonNode.updateItems([], animated: animated)
                    self.leftButtonNode.updateItems([leftBarButtonItem], animated: animated)
                } else {
                    self.leftButtonNode.updateItems([], animated: animated)
                    self.leftButtonNode.updateItems([UIBarButtonItem(title: self.presentationData.strings.close, style: .plain, target: nil, action: nil)], animated: animated)
                }

                if self.leftButtonNode.supernode == nil {
                    self.buttonsContainerNode.addSubnode(self.leftButtonNode)
                }

                if animated {
                    self.leftButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                }
            } else {
                if animated {
                    self.fadeOutSnapshot(of: self.leftButtonNode)
                }
                self.leftButtonNode.removeFromSupernode()

                var backTitle: String?
                if let leftBarButtonItem = item.leftBarButtonItem, leftBarButtonItem.backButtonAppearance {
                    backTitle = leftBarButtonItem.title
                } else if let previousItem = previousItem {
                    switch previousItem {
                    case let .item(itemValue):
                        if let backBarButtonItem = itemValue.backBarButtonItem {
                            backTitle = backBarButtonItem.title ?? self.presentationData.strings.back
                        } else {
                            backTitle = itemValue.title ?? self.presentationData.strings.back
                        }
                    case .close:
                        backTitle = nil
                    }
                }

                if let backTitle = backTitle {
                    self.backButtonNode.updateManualText(backTitle, isBack: true)
                    if self.backButtonNode.supernode == nil {
                        self.buttonsContainerNode.addSubnode(self.backButtonNode)
                        self.buttonsContainerNode.addSubnode(self.backButtonArrow)
                        self.buttonsContainerNode.addSubnode(self.badgeNode)
                    }

                    if animated {
                        self.backButtonNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                        self.backButtonArrow.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                        self.badgeNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                    }
                } else {
                    self.backButtonNode.removeFromSupernode()
                    self.backButtonArrow.removeFromSupernode()
                    self.badgeNode.removeFromSupernode()
                }
            }
        } else {
            self.leftButtonNode.removeFromSupernode()
            self.backButtonNode.removeFromSupernode()
            self.backButtonArrow.removeFromSupernode()
            self.badgeNode.removeFromSupernode()
        }
    }

    private func updateRightButton(animated: Bool) {
        if let item = self.item {
            var items: [UIBarButtonItem] = []
            if let rightBarButtonItems = item.rightBarButtonItems, !rightBarButtonItems.isEmpty {
                items = rightBarButtonItems
            } else if let rightBarButtonItem = item.rightBarButtonItem {
                items = [rightBarButtonItem]
            }

            self.rightButtonNodeUpdated = true

            if !items.isEmpty {
                self.rightButtonNode.updateItems([], animated: animated)
                self.rightButtonNode.updateItems(items, animated: animated)
                if self.rightButtonNode.supernode == nil {
                    self.buttonsContainerNode.addSubnode(self.rightButtonNode)
                }
            } else {
                if animated {
                    self.fadeOutSnapshot(of: self.rightButtonNode)
                }
                self.rightButtonNode.updateItems([], animated: false)
                self.rightButtonNode.removeFromSupernode()
            }
        } else {
            if animated {
                self.fadeOutSnapshot(of: self.rightButtonNode)
            }
            self.rightButtonNode.updateItems([], animated: false)
            self.rightButtonNode.removeFromSupernode()
        }
    }

    public let backgroundNode: NavigationBackgroundNode
    public let backButtonNode: LegacyNavigationButtonNode
    public let badgeNode: LegacyNavigationBarBadgeNode
    public let backButtonArrow: ASImageNode
    public let leftButtonNode: LegacyNavigationButtonNode
    public let rightButtonNode: LegacyNavigationButtonNode
    private var rightButtonNodeUpdated: Bool = false
    public let additionalContentNode: SparseNode

    public var secondaryContentHeight: CGFloat

    public var sideColumnPlacement: NavigationBarSideColumnPlacement?
    public var sideColumnExtentUpdated: ((ContainedViewLayoutTransition) -> Void)?

    public var isBackInSideColumn: Bool {
        return false
    }

    public func sideColumnExtent(placement: NavigationBarSideColumnPlacement) -> NavigationBarSideColumnExtent? {
        return nil
    }

    public var backButtonContextAction: ((UIView, ContextGesture) -> Void)? {
        didSet {
            self.backButtonNode.isGestureEnabled = self.backButtonContextAction != nil
        }
    }

    public var trailingButtonsInset: CGFloat = 0.0 {
        didSet {
            if self.trailingButtonsInset != oldValue {
                self.requestLayout()
            }
        }
    }

    public var transitionContentFrameUpdated: ((CGRect) -> Void)?

    private var isRowHiddenByController: Bool = false
    private var isRowHiddenByScreen: Bool = false

    private var hasReplacementContentNode: Bool {
        if let contentNode = self.contentNode, case .replacement = contentNode.mode {
            return true
        }
        return false
    }

    private var buttonsContainerTargetAlpha: CGFloat {
        if self.hasReplacementContentNode {
            return 0.0
        }
        return (self.isRowHiddenByController || self.isRowHiddenByScreen) ? 0.0 : 1.0
    }

    private var overBackgroundContentTargetAlpha: CGFloat {
        if self.hasReplacementContentNode {
            return 0.0
        }
        return self.isRowHiddenByScreen ? 0.0 : 1.0
    }

    public init(presentationData: NavigationBarPresentationData) {
        self.presentationData = presentationData
        self.stripeNode = ASDisplayNode()

        self.titleNode = ImmediateTextNode()
        self.titleNode.isAccessibilityElement = true
        self.titleNode.accessibilityTraits = .header

        self.backButtonNode = LegacyNavigationButtonNode(strings: presentationData.strings)
        self.backButtonNode.hitTestSlop = UIEdgeInsets(top: 0.0, left: -20.0, bottom: 0.0, right: 0.0)

        self.badgeNode = LegacyNavigationBarBadgeNode(fillColor: LegacyNavigationBarNode.badgeFillColor(theme: presentationData.theme), strokeColor: LegacyNavigationBarNode.badgeFillColor(theme: presentationData.theme), textColor: presentationData.theme.badgeTextColor)
        self.badgeNode.isUserInteractionEnabled = false
        self.badgeNode.isHidden = true
        self.backButtonArrow = ASImageNode()
        self.backButtonArrow.displayWithoutProcessing = true
        self.backButtonArrow.displaysAsynchronously = false
        self.backButtonArrow.isUserInteractionEnabled = false
        self.leftButtonNode = LegacyNavigationButtonNode(strings: presentationData.strings)
        self.rightButtonNode = LegacyNavigationButtonNode(strings: presentationData.strings)
        self.rightButtonNode.hitTestSlop = UIEdgeInsets(top: -4.0, left: -4.0, bottom: -4.0, right: -10.0)

        self.clippingNode = SparseNode()
        self.clippingNode.clipsToBounds = true

        self.buttonsContainerNode = ASDisplayNode()
        self.buttonsContainerNode.clipsToBounds = true

        self.customOverBackgroundContentView = SparseContainerView()

        self.backButtonNode.color = presentationData.theme.buttonColor
        self.backButtonNode.disabledColor = presentationData.theme.disabledButtonColor
        self.leftButtonNode.color = presentationData.theme.buttonColor
        self.leftButtonNode.disabledColor = presentationData.theme.disabledButtonColor
        self.rightButtonNode.color = presentationData.theme.buttonColor
        self.rightButtonNode.disabledColor = presentationData.theme.disabledButtonColor
        self.rightButtonNode.rippleColor = presentationData.theme.primaryTextColor.withAlphaComponent(0.05)
        self.backButtonArrow.image = navigationBarBackArrowImage(color: presentationData.theme.buttonColor)
        self.stripeNode.backgroundColor = presentationData.theme.separatorColor

        self.backgroundNode = NavigationBackgroundNode(color: presentationData.theme.backgroundColor, enableBlur: presentationData.theme.enableBackgroundBlur)
        self.backgroundNode.isUserInteractionEnabled = false
        self.additionalContentNode = SparseNode()

        self.secondaryContentHeight = LegacyNavigationBarNode.defaultSecondaryContentHeight

        super.init()

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.buttonsContainerNode)
        self.addSubnode(self.clippingNode)
        self.addSubnode(self.additionalContentNode)

        self.backgroundColor = nil
        self.isOpaque = false

        self.stripeNode.isLayerBacked = true
        self.stripeNode.displaysAsynchronously = false
        self.addSubnode(self.stripeNode)

        self.titleNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.truncationType = .end
        self.titleNode.isOpaque = false

        self.backButtonNode.highlightChanged = { [weak self] index, highlighted in
            if let strongSelf = self, index == 0 {
                strongSelf.backButtonArrow.alpha = (highlighted ? 0.4 : 1.0)
                strongSelf.badgeNode.alpha = (highlighted ? 0.4 : 1.0)
            }
        }
        self.backButtonNode.pressed = { [weak self] index in
            if let strongSelf = self, index == 0 {
                if let leftBarButtonItem = strongSelf.item?.leftBarButtonItem, leftBarButtonItem.backButtonAppearance {
                    leftBarButtonItem.performActionOnTarget()
                } else {
                    strongSelf.backPressed()
                }
            }
        }
        self.backButtonNode.activated = { [weak self] gesture, _ in
            guard let strongSelf = self, let backButtonContextAction = strongSelf.backButtonContextAction else {
                gesture.cancel()
                return
            }
            backButtonContextAction(strongSelf.backButtonNode.view, gesture)
        }

        self.leftButtonNode.pressed = { [weak self] index in
            if let item = self?.item {
                if index == 0 {
                    if let leftBarButtonItem = item.leftBarButtonItem {
                        leftBarButtonItem.performActionOnTarget()
                    } else if let previousItem = self?.effectivePreviousItem, case .close = previousItem {
                        self?.backPressed()
                    }
                }
            }
        }

        self.rightButtonNode.pressed = { [weak self] index in
            if let item = self?.item {
                if let rightBarButtonItems = item.rightBarButtonItems, !rightBarButtonItems.isEmpty {
                    if index < rightBarButtonItems.count {
                        rightBarButtonItems[index].performActionOnTarget()
                    }
                } else if let rightBarButtonItem = item.rightBarButtonItem {
                    rightBarButtonItem.performActionOnTarget()
                }
            }
        }

        let contentUpdated: () -> Void = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.invalidateCalculatedLayout()
            strongSelf.requestLayout()
        }
        self.leftButtonNode.contentUpdated = contentUpdated
        self.rightButtonNode.contentUpdated = contentUpdated
    }

    override public func didLoad() {
        super.didLoad()

        self.view.insertSubview(self.customOverBackgroundContentView, aboveSubview: self.backgroundNode.view)
    }

    private static func badgeFillColor(theme: NavigationBarTheme) -> UIColor {
        if theme.badgeBackgroundColor.alpha.isZero {
            return .clear
        }
        return theme.buttonColor
    }

    public var isBackdropVisible: Bool {
        return self.backgroundNode.alpha == 1.0
    }

    public func setBackdropAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        let alpha = max(0.0, min(1.0, alpha))
        transition.updateAlpha(node: self.backgroundNode, alpha: alpha, delay: 0.15)
        transition.updateAlpha(node: self.stripeNode, alpha: alpha, delay: 0.15)
    }

    public func updatePresentationData(_ presentationData: NavigationBarPresentationData, transition: ContainedViewLayoutTransition) {
        if presentationData.theme !== self.presentationData.theme || presentationData.strings !== self.presentationData.strings {
            self.presentationData = presentationData

            self.backgroundNode.updateColor(color: presentationData.theme.backgroundColor, enableBlur: presentationData.theme.enableBackgroundBlur, transition: transition)

            self.backButtonNode.updateStrings(presentationData.strings)
            self.leftButtonNode.updateStrings(presentationData.strings)
            self.rightButtonNode.updateStrings(presentationData.strings)

            self.backButtonNode.color = presentationData.theme.buttonColor
            self.backButtonNode.disabledColor = presentationData.theme.disabledButtonColor
            self.leftButtonNode.color = presentationData.theme.buttonColor
            self.leftButtonNode.disabledColor = presentationData.theme.disabledButtonColor
            self.rightButtonNode.color = presentationData.theme.buttonColor
            self.rightButtonNode.disabledColor = presentationData.theme.disabledButtonColor
            self.rightButtonNode.rippleColor = presentationData.theme.primaryTextColor.withAlphaComponent(0.05)
            self.backButtonArrow.image = navigationBarBackArrowImage(color: presentationData.theme.buttonColor)
            if let title = self.title {
                self.titleNode.attributedText = NSAttributedString(string: title, font: LegacyNavigationBarNode.titleFont, textColor: presentationData.theme.primaryTextColor)
                self.titleNode.accessibilityLabel = title
            }
            self.stripeNode.backgroundColor = presentationData.theme.separatorColor

            self.badgeNode.updateTheme(fillColor: LegacyNavigationBarNode.badgeFillColor(theme: presentationData.theme), strokeColor: LegacyNavigationBarNode.badgeFillColor(theme: presentationData.theme), textColor: presentationData.theme.badgeTextColor)

            self.updateLeftButton(animated: false)
            self.updateRightButton(animated: false)
            self.invalidateCalculatedLayout()
            self.requestLayout()
        }
    }

    func requestLayout() {
        self.requestedLayout = true
        self.setNeedsLayout()
    }

    override public func layout() {
        super.layout()

        if let validLayout = self.validLayout, self.requestedLayout {
            self.requestedLayout = false
            self.update(layout: validLayout, transition: .immediate)
        }
    }

    private func currentIsLandscape() -> Bool {
        guard self.isNodeLoaded, let window = self.view.window else {
            return false
        }
        if window.traitCollection.horizontalSizeClass == .regular {
            return false
        }
        return window.bounds.width > window.bounds.height
    }

    public func updateLayout(size: CGSize, defaultHeight: CGFloat, additionalTopHeight: CGFloat, additionalContentHeight: CGFloat, additionalBackgroundHeight: CGFloat, leftInset: CGFloat, rightInset: CGFloat, appearsHidden: Bool, transition: ContainedViewLayoutTransition) {
        let layout = Layout(size: size, defaultHeight: defaultHeight, additionalTopHeight: additionalTopHeight, additionalContentHeight: additionalContentHeight, additionalBackgroundHeight: additionalBackgroundHeight, leftInset: leftInset, rightInset: rightInset, appearsHidden: appearsHidden, isLandscape: self.currentIsLandscape())
        self.requestedLayout = false
        self.update(layout: layout, transition: transition)
    }

    private func update(layout: Layout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout

        let size = layout.size
        let defaultHeight = layout.defaultHeight
        let leftInset = layout.leftInset
        let rightInset = layout.rightInset
        let isLandscape = layout.isLandscape

        let backgroundFrame = CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: size.height + layout.additionalBackgroundHeight))
        if self.backgroundNode.frame != backgroundFrame {
            transition.updateFrame(node: self.backgroundNode, frame: backgroundFrame)
            self.backgroundNode.update(size: backgroundFrame.size, transition: transition)
        }

        transition.updateFrame(view: self.customOverBackgroundContentView, frame: CGRect(origin: CGPoint(), size: size))

        let apparentAdditionalHeight: CGFloat = self.secondaryContentNode != nil ? self.secondaryContentHeight : 0.0

        let leftButtonInset: CGFloat = leftInset + 16.0
        let backButtonInset: CGFloat = leftInset + 27.0

        let nominalHeight: CGFloat = defaultHeight
        let contentVerticalOrigin = layout.additionalTopHeight

        transition.updateFrame(node: self.clippingNode, frame: CGRect(origin: CGPoint(), size: size))
        transition.updateFrame(node: self.additionalContentNode, frame: CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: size.height + layout.additionalBackgroundHeight)))
        transition.updateFrame(node: self.buttonsContainerNode, frame: CGRect(origin: CGPoint(), size: size))
        if let contentNode = self.contentNode {
            switch contentNode.mode {
            case .replacement:
                let contentNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: contentVerticalOrigin), size: CGSize(width: size.width, height: contentNode.nominalHeight))
                transition.updateFrame(node: contentNode, frame: contentNodeFrame)
                let _ = contentNode.updateLayout(size: contentNodeFrame.size, leftInset: leftInset, rightInset: rightInset + self.trailingButtonsInset, transition: transition)
            case .expansion:
                let expansionHeight = contentNode.height

                let additionalExpansionHeight: CGFloat = self.secondaryContentNode != nil && layout.appearsHidden ? self.secondaryContentHeight : 0.0
                var contentNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: size.height - (layout.appearsHidden ? 0.0 : layout.additionalContentHeight) - expansionHeight - apparentAdditionalHeight - additionalExpansionHeight), size: CGSize(width: size.width, height: expansionHeight))
                if layout.appearsHidden {
                    if self.secondaryContentNode != nil {
                        contentNodeFrame.origin.y += self.secondaryContentHeight
                    }
                }
                transition.updateFrame(node: contentNode, frame: contentNodeFrame)
                let _ = contentNode.updateLayout(size: contentNodeFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)
            }
        }

        transition.updateFrame(node: self.stripeNode, frame: CGRect(x: 0.0, y: size.height + layout.additionalBackgroundHeight, width: size.width, height: UIScreenPixel))

        var leftTitleInset: CGFloat = leftInset + 1.0
        var rightTitleInset: CGFloat = rightInset + 1.0
        if self.backButtonNode.supernode != nil {
            let backButtonSize = self.backButtonNode.updateLayout(constrainedSize: CGSize(width: size.width, height: nominalHeight), isLandscape: isLandscape, isLeftAligned: true)
            leftTitleInset = backButtonSize.width + backButtonInset + 1.0

            let topHitTestSlop = (nominalHeight - backButtonSize.height) * 0.5
            self.backButtonNode.hitTestSlop = UIEdgeInsets(top: -topHitTestSlop, left: -27.0, bottom: -topHitTestSlop, right: -8.0)

            self.backButtonNode.alpha = 1.0
            transition.updateFrame(node: self.backButtonNode, frame: CGRect(origin: CGPoint(x: backButtonInset, y: contentVerticalOrigin + floor((nominalHeight - backButtonSize.height) / 2.0)), size: backButtonSize))

            self.backButtonArrow.alpha = 1.0
            transition.updateFrame(node: self.backButtonArrow, frame: CGRect(origin: CGPoint(x: leftInset + 8.0, y: contentVerticalOrigin + floor((nominalHeight - 22.0) / 2.0)), size: CGSize(width: 13.0, height: 22.0)))
            self.badgeNode.alpha = 1.0
        } else if self.leftButtonNode.supernode != nil {
            let leftButtonSize = self.leftButtonNode.updateLayout(constrainedSize: CGSize(width: size.width, height: nominalHeight), isLandscape: isLandscape, isLeftAligned: true)
            leftTitleInset = leftButtonSize.width + leftButtonInset + 1.0

            var leftButtonTransition = transition
            if self.leftButtonNode.frame.width.isZero {
                leftButtonTransition = .immediate
            }

            self.leftButtonNode.alpha = 1.0
            leftButtonTransition.updateFrame(node: self.leftButtonNode, frame: CGRect(origin: CGPoint(x: leftButtonInset, y: contentVerticalOrigin + floor((nominalHeight - leftButtonSize.height) / 2.0)), size: leftButtonSize))
        }

        let badgeSize = self.badgeNode.measure(CGSize(width: 200.0, height: 100.0))
        let backButtonArrowFrame = self.backButtonArrow.frame
        transition.updateFrame(node: self.badgeNode, frame: CGRect(origin: backButtonArrowFrame.origin.offsetBy(dx: 16.0, dy: 2.0), size: badgeSize))

        if self.rightButtonNode.supernode != nil {
            let rightButtonSize = self.rightButtonNode.updateLayout(constrainedSize: CGSize(width: size.width, height: nominalHeight), isLandscape: isLandscape, isLeftAligned: false)
            rightTitleInset = rightButtonSize.width + leftButtonInset + 1.0 + self.trailingButtonsInset
            self.rightButtonNode.alpha = 1.0

            var rightButtonTransition = transition
            if self.rightButtonNode.frame.width.isZero || self.rightButtonNodeUpdated {
                rightButtonTransition = .immediate
            }

            rightButtonTransition.updateFrame(node: self.rightButtonNode, frame: CGRect(origin: CGPoint(x: size.width - leftButtonInset - self.trailingButtonsInset - rightButtonSize.width, y: contentVerticalOrigin + floor((nominalHeight - rightButtonSize.height) / 2.0)), size: rightButtonSize))
        }
        self.rightButtonNodeUpdated = false

        leftTitleInset = floor(leftTitleInset)
        if Int(leftTitleInset) % 2 != 0 {
            leftTitleInset -= 1.0
        }

        if self.titleNode.supernode != nil {
            let titleSize = self.titleNode.updateLayout(CGSize(width: max(1.0, size.width - max(leftTitleInset, rightTitleInset) * 2.0), height: nominalHeight))

            var titleTransition = transition
            if self.titleNode.frame.width.isZero {
                titleTransition = .immediate
            }
            self.titleNode.alpha = 1.0
            titleTransition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize))
        }

        if let titleView = self.titleView {
            let availableWidth = max(1.0, size.width - max(leftTitleInset, rightTitleInset) * 2.0)
            var titleViewTransition = transition
            if titleView.frame.isEmpty {
                titleViewTransition = .immediate
            }
            let titleFrame: CGRect
            if let titleView = titleView as? NavigationBarTitleView {
                let titleSize = titleView.updateLayout(availableSize: CGSize(width: availableWidth, height: nominalHeight), transition: titleViewTransition)
                titleFrame = CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: contentVerticalOrigin + floorToScreenPixels((nominalHeight - titleSize.height) / 2.0)), size: titleSize)
            } else {
                titleFrame = CGRect(origin: CGPoint(x: floor((size.width - availableWidth) / 2.0), y: contentVerticalOrigin), size: CGSize(width: availableWidth, height: nominalHeight))
            }
            if titleView.frame.isEmpty {
                titleView.frame = titleFrame
            }
            titleView.alpha = 1.0
            titleViewTransition.updateFrame(view: titleView, frame: titleFrame)
        }

        self.applyInlineTransitionLayout()

        self.transitionContentFrameUpdated?(CGRect(origin: CGPoint(), size: size))
    }

    public var intrinsicCanTransitionInline: Bool = true

    public var passthroughTouches: Bool = true

    public var canTransitionInline: Bool {
        if let contentNode = self.contentNode, case .replacement = contentNode.mode {
            return false
        } else {
            return self.intrinsicCanTransitionInline
        }
    }

    public func contentHeight(defaultHeight: CGFloat) -> CGFloat {
        var result: CGFloat = 0.0
        if let contentNode = self.contentNode {
            switch contentNode.mode {
            case .expansion:
                result += defaultHeight + contentNode.height
            case .replacement:
                result += contentNode.height
            }
        } else {
            result += defaultHeight
        }

        if let _ = self.secondaryContentNode {
            result += self.secondaryContentHeight
        }

        return result
    }

    public func setContentNode(_ contentNode: NavigationBarContentNode?, animated: Bool) {
        if self.contentNode !== contentNode {
            if let previous = self.contentNode {
                if animated {
                    previous.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak self, weak previous] _ in
                        if let strongSelf = self, let previous = previous {
                            if previous !== strongSelf.contentNode {
                                previous.removeFromSupernode()
                            }
                        }
                    })
                } else {
                    previous.removeFromSupernode()
                }
            }
            self.contentNode = contentNode
            self.contentNode?.requestContainerLayout = { [weak self] transition in
                guard let strongSelf = self else {
                    return
                }
                if let requestContainerLayout = strongSelf.requestContainerLayout {
                    requestContainerLayout(transition)
                } else {
                    strongSelf.requestLayout()
                }
            }
            if let contentNode = contentNode {
                contentNode.clipsToBounds = true
                contentNode.layer.removeAnimation(forKey: "opacity")
                self.insertSubnode(contentNode, belowSubnode: self.stripeNode)
                if animated {
                    contentNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }

            self.applyRowAlpha(animated: animated)

            if contentNode != nil && !self.bounds.size.width.isZero {
                self.requestedLayout = true
                self.layout()
            } else {
                self.requestLayout()
            }
        }
    }

    private func applyRowAlpha(animated: Bool) {
        let buttonsTargetAlpha = self.buttonsContainerTargetAlpha
        let buttonsPreviousAlpha = self.buttonsContainerNode.alpha
        if buttonsPreviousAlpha != buttonsTargetAlpha {
            self.buttonsContainerNode.alpha = buttonsTargetAlpha
            if animated {
                self.buttonsContainerNode.layer.animateAlpha(from: buttonsPreviousAlpha, to: buttonsTargetAlpha, duration: 0.2)
            }
        }

        let overBackgroundTargetAlpha = self.overBackgroundContentTargetAlpha
        let overBackgroundPreviousAlpha = self.customOverBackgroundContentView.alpha
        if overBackgroundPreviousAlpha != overBackgroundTargetAlpha {
            self.customOverBackgroundContentView.alpha = overBackgroundTargetAlpha
            if animated {
                self.customOverBackgroundContentView.layer.animateAlpha(from: overBackgroundPreviousAlpha, to: overBackgroundTargetAlpha, duration: 0.2)
            }
        }
    }

    public func setSecondaryContentNode(_ secondaryContentNode: ASDisplayNode?, animated: Bool) {
        if self.secondaryContentNode !== secondaryContentNode {
            if let previous = self.secondaryContentNode, previous.supernode === self.clippingNode {
                if animated {
                    previous.layer.animateAlpha(from: previous.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak previous] finished in
                        if finished {
                            previous?.removeFromSupernode()
                            previous?.layer.removeAllAnimations()
                        }
                    })
                } else {
                    previous.removeFromSupernode()
                }
            }
            self.secondaryContentNode = secondaryContentNode
            if let secondaryContentNode = secondaryContentNode {
                self.clippingNode.addSubnode(secondaryContentNode)

                if animated {
                    secondaryContentNode.layer.animateAlpha(from: 0.0, to: secondaryContentNode.alpha, duration: 0.3)
                }
            }
        }
    }

    public func executeBack() -> Bool {
        if self.backButtonNode.supernode != nil {
            self.backButtonNode.pressed(0)
        } else if self.leftButtonNode.supernode != nil {
            self.leftButtonNode.pressed(0)
        } else {
            self.backButtonNode.pressed(0)
        }
        return true
    }

    public func setHidden(_ hidden: Bool, animated: Bool) {
        self.isRowHiddenByController = hidden
        self.applyRowAlpha(animated: animated)
    }

    public func setRowHiddenByScreen(_ hidden: Bool, transition: ContainedViewLayoutTransition) {
        if self.isRowHiddenByScreen == hidden {
            return
        }
        self.isRowHiddenByScreen = hidden
        transition.updateAlpha(node: self.buttonsContainerNode, alpha: self.buttonsContainerTargetAlpha)
        transition.updateAlpha(view: self.customOverBackgroundContentView, alpha: self.overBackgroundContentTargetAlpha)
    }

    public func animateButtonsIn(duration: Double) {
        for node in [self.backButtonNode, self.backButtonArrow, self.badgeNode, self.leftButtonNode, self.rightButtonNode] as [ASDisplayNode] where node.supernode != nil {
            node.layer.animateAlpha(from: 0.0, to: node.alpha, duration: duration)
        }
    }

    public func rightButtonView(for item: UIBarButtonItem) -> UIView? {
        if self.rightButtonNode.supernode != nil, let view = self.rightButtonNode.itemView(for: item) {
            return view
        }
        if self.leftButtonNode.supernode != nil, let view = self.leftButtonNode.itemView(for: item) {
            return view
        }
        return nil
    }

    public func updateEdgeEffectExtension(value: CGFloat, transition: ContainedViewLayoutTransition) {
    }

    public func navigationButtonContextContainer(sourceView: UIView) -> ContextExtractableContainer? {
        return nil
    }

    public func takeView() -> NavigationBarTransitionTakeViewInfo? {
        return nil
    }

    public func putBack() {
    }

    public func updateTransition(role: NavigationBarTransitionRole?, fraction: CGFloat, transition: ContainedViewLayoutTransition) {
    }

    public func backButtonFrame(in view: UIView) -> CGRect? {
        guard self.backButtonNode.supernode != nil, self.backButtonNode.isNodeLoaded, self.backButtonNode.view.window != nil, view.window != nil else {
            return nil
        }
        return self.backButtonNode.view.convert(self.backButtonNode.bounds, to: view)
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let result = self.additionalContentNode.view.hitTest(self.view.convert(point, to: self.additionalContentNode.view), with: event) {
            return result
        }

        guard let result = super.hitTest(point, with: event) else {
            if !self.bounds.contains(point) {
                if let result = self.customOverBackgroundContentView.hitTest(self.view.convert(point, to: self.customOverBackgroundContentView), with: event) {
                    return result
                }
            }
            return nil
        }

        if result === self.view || result === self.buttonsContainerNode.view || result === self.clippingNode.view || result === self.customOverBackgroundContentView {
            if let result = self.customOverBackgroundContentView.hitTest(self.view.convert(point, to: self.customOverBackgroundContentView), with: event) {
                return result
            }
            if self.passthroughTouches {
                return nil
            }
        }

        return result
    }
}
