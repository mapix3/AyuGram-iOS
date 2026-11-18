import Foundation
import UIKit
import AsyncDisplayKit
import Display

private final class LegacyNavigationButtonItemNode: ImmediateTextNode {
    private func fontForCurrentState() -> UIFont {
        return self.bold ? UIFont.boldSystemFont(ofSize: 17.0) : UIFont.systemFont(ofSize: 17.0)
    }

    private func attributesForCurrentState() -> [NSAttributedString.Key: AnyObject] {
        return [
            NSAttributedString.Key.font: self.fontForCurrentState(),
            NSAttributedString.Key.foregroundColor: self.isEnabled ? self.color : self.disabledColor
        ]
    }

    private var setEnabledListener: Int?
    private var setTitleListener: Int?

    var titleUpdated: (() -> Void)?

    var item: UIBarButtonItem? {
        didSet {
            if self.item !== oldValue {
                if let oldValue = oldValue {
                    if let setEnabledListener = self.setEnabledListener {
                        oldValue.removeSetEnabledListener(setEnabledListener)
                        self.setEnabledListener = nil
                    }
                    if let setTitleListener = self.setTitleListener {
                        oldValue.removeSetTitleListener(setTitleListener)
                        self.setTitleListener = nil
                    }
                }

                if let item = self.item {
                    self.setEnabledListener = item.addSetEnabledListener { [weak self] value in
                        self?.isEnabled = value
                    }
                    self.setTitleListener = item.addSetTitleListener { [weak self] _ in
                        self?.titleUpdated?()
                    }
                }
            }
        }
    }

    private var _text: String?
    var text: String {
        get {
            return self._text ?? ""
        }
        set(value) {
            self._text = value

            self.attributedText = NSAttributedString(string: value, attributes: self.attributesForCurrentState())
        }
    }

    private(set) var imageNode: ASImageNode?

    private var _image: UIImage?
    var image: UIImage? {
        get {
            return self._image
        } set(value) {
            self._image = value

            if let _ = value {
                if self.imageNode == nil {
                    let imageNode = ASImageNode()
                    imageNode.displayWithoutProcessing = true
                    imageNode.displaysAsynchronously = false
                    self.imageNode = imageNode

                    self.addSubnode(imageNode)
                }
                self.updateDisplayedImage()
            } else if let imageNode = self.imageNode {
                imageNode.removeFromSupernode()
                self.imageNode = nil
            }

            self.invalidateCalculatedLayout()
            self.setNeedsLayout()
        }
    }

    private func updateDisplayedImage() {
        guard let imageNode = self.imageNode, let image = self._image else {
            return
        }
        if image.renderingMode == .alwaysTemplate {
            imageNode.image = generateTintedImage(image: image, color: self.isEnabled ? self.color : self.disabledColor)
        } else {
            imageNode.image = image
        }
    }

    var node: ASDisplayNode? {
        didSet {
            if self.node !== oldValue {
                if let oldValue = oldValue, oldValue.supernode === self {
                    oldValue.removeFromSupernode()
                }
                if let node = self.node {
                    self.addSubnode(node)
                    self.invalidateCalculatedLayout()
                    self.setNeedsLayout()
                    self.updatePointerInteraction()
                }
            }
        }
    }

    var color: UIColor = UIColor(rgb: 0x007aff) {
        didSet {
            if let text = self._text {
                self.attributedText = NSAttributedString(string: text, attributes: self.attributesForCurrentState())
            }
            self.updateDisplayedImage()
        }
    }

    var rippleColor: UIColor = UIColor(rgb: 0x000000, alpha: 0.05)

    var disabledColor: UIColor = UIColor(rgb: 0xd0d0d0) {
        didSet {
            if let text = self._text {
                self.attributedText = NSAttributedString(string: text, attributes: self.attributesForCurrentState())
            }
            self.updateDisplayedImage()
        }
    }

    private var _bold: Bool = false
    var bold: Bool {
        get {
            return self._bold
        }
        set(value) {
            if self._bold != value {
                self._bold = value

                self.attributedText = NSAttributedString(string: self.text, attributes: self.attributesForCurrentState())
            }
        }
    }

    private var touchCount = 0
    var pressed: () -> Void = { }
    var highlightChanged: (Bool) -> Void = { _ in }

    override var isAccessibilityElement: Bool {
        get {
            return true
        } set(value) {
            super.isAccessibilityElement = true
        }
    }

    override var accessibilityLabel: String? {
        get {
            if let item = self.item, let accessibilityLabel = item.accessibilityLabel, !accessibilityLabel.isEmpty, !accessibilityLabel.hasPrefix("___") {
                return accessibilityLabel
            } else if let string = self.attributedText?.string, !string.isEmpty {
                return string
            } else if let title = self.item?.title, !title.isEmpty, !title.hasPrefix("___") {
                return title
            } else {
                return nil
            }
        } set(value) {
        }
    }

    override var accessibilityHint: String? {
        get {
            if let item = self.item, let accessibilityHint = item.accessibilityHint {
                return accessibilityHint
            } else {
                return nil
            }
        } set(value) {
        }
    }

    private var pointerInteraction: PointerInteraction?

    override init() {
        super.init()

        self.isAccessibilityElement = true

        self.isUserInteractionEnabled = true
        self.isExclusiveTouch = true
        self.hitTestSlop = UIEdgeInsets(top: -16.0, left: -10.0, bottom: -16.0, right: -10.0)
        self.displaysAsynchronously = false

        self.verticalAlignment = .middle

        self.accessibilityTraits = .button
    }

    deinit {
        if let item = self.item {
            if let setEnabledListener = self.setEnabledListener {
                item.removeSetEnabledListener(setEnabledListener)
            }
            if let setTitleListener = self.setTitleListener {
                item.removeSetTitleListener(setTitleListener)
            }
        }
    }

    override func didLoad() {
        super.didLoad()
        self.updatePointerInteraction()
    }

    private func updatePointerInteraction() {
        guard self.isNodeLoaded else {
            return
        }
        let pointerStyle: PointerStyle
        if self.node != nil {
            pointerStyle = .lift
        } else {
            pointerStyle = .insetRectangle(-8.0, 2.0)
        }
        self.pointerInteraction = PointerInteraction(node: self, style: pointerStyle)
    }

    override func updateLayout(_ constrainedSize: CGSize) -> CGSize {
        var superSize = super.updateLayout(constrainedSize)

        if let node = self.node {
            let nodeSize = node.measure(constrainedSize)
            let size = CGSize(width: max(nodeSize.width, superSize.width), height: max(nodeSize.height, superSize.height))
            node.frame = CGRect(origin: CGPoint(), size: nodeSize)
            return size
        } else if let imageNode = self.imageNode {
            let nodeSize = imageNode.image?.size ?? CGSize()
            let size = CGSize(width: max(nodeSize.width, superSize.width), height: max(44.0, max(nodeSize.height, superSize.height)))
            let imageFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - nodeSize.width) / 2.0), y: floorToScreenPixels((size.height - nodeSize.height) / 2.0)), size: nodeSize)
            imageNode.frame = imageFrame
            return size
        } else {
            superSize.height = max(44.0, superSize.height)
        }
        return superSize
    }

    private func touchInsideApparentBounds(_ touch: UITouch) -> Bool {
        var apparentBounds = self.bounds
        let hitTestSlop = self.hitTestSlop
        apparentBounds.origin.x += hitTestSlop.left
        apparentBounds.size.width += -hitTestSlop.left - hitTestSlop.right
        apparentBounds.origin.y += hitTestSlop.top
        apparentBounds.size.height += -hitTestSlop.top - hitTestSlop.bottom

        return apparentBounds.contains(touch.location(in: self.view))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        self.touchCount += touches.count
        self.updateHighlightedState(true, animated: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        self.updateHighlightedState(false, animated: false)

        let previousTouchCount = self.touchCount
        self.touchCount = max(0, self.touchCount - touches.count)

        var touchInside = true
        if let touch = touches.first {
            touchInside = self.touchInsideApparentBounds(touch)
        }
        if previousTouchCount != 0 && self.touchCount == 0 && self.isEnabled && touchInside {
            self.pressed()
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let node = self.node as? HighlightableButtonNode {
            let result = node.view.hitTest(self.view.convert(point, to: node.view), with: event)
            return result
        } else {
            let previousAlpha = self.alpha
            self.alpha = 1.0
            let result = super.hitTest(point, with: event)
            self.alpha = previousAlpha
            return result
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)

        self.touchCount = max(0, self.touchCount - (touches?.count ?? 0))
        self.updateHighlightedState(false, animated: false)
    }

    private var _highlighted = false
    private func updateHighlightedState(_ highlighted: Bool, animated: Bool) {
        if self._highlighted != highlighted {
            self._highlighted = highlighted

            var shouldChangeHighlight = true
            if let node = self.node as? NavigationButtonCustomDisplayNode {
                shouldChangeHighlight = node.isHighlightable
            }

            if shouldChangeHighlight {
                if self.alpha > 0.0 {
                    self.alpha = !self.isEnabled ? 1.0 : (highlighted ? 0.4 : 1.0)
                }
                self.highlightChanged(highlighted)
            }
        }
    }

    var isEnabled: Bool = true {
        didSet {
            if self.isEnabled != oldValue {
                self.attributedText = NSAttributedString(string: self.text, attributes: self.attributesForCurrentState())
                self.updateDisplayedImage()
                if let constrainedSize = self.constrainedSize {
                    let _ = self.updateLayout(constrainedSize)
                }
            }
        }
    }
}

public final class LegacyNavigationButtonNode: ContextControllerSourceNode {
    private var nodes: [LegacyNavigationButtonItemNode] = []

    private var disappearingNodes: [(frame: CGRect, size: CGSize, node: LegacyNavigationButtonItemNode)] = []

    public var pressed: (Int) -> Void = { _ in }
    public var highlightChanged: (Int, Bool) -> Void = { _, _ in }
    var contentUpdated: (() -> Void)?

    private var strings: NavigationBarStrings

    public var color: UIColor = UIColor(rgb: 0x007aff) {
        didSet {
            if !self.color.isEqual(oldValue) {
                for node in self.nodes {
                    node.color = self.color
                }
            }
        }
    }

    public var rippleColor: UIColor = UIColor(rgb: 0x000000, alpha: 0.05) {
        didSet {
            if !self.rippleColor.isEqual(oldValue) {
                for node in self.nodes {
                    node.rippleColor = self.rippleColor
                }
            }
        }
    }

    public var disabledColor: UIColor = UIColor(rgb: 0xd0d0d0) {
        didSet {
            if !self.disabledColor.isEqual(oldValue) {
                for node in self.nodes {
                    node.disabledColor = self.disabledColor
                }
            }
        }
    }

    override public var accessibilityElements: [Any]? {
        get {
            return self.nodes
        } set(value) {
        }
    }

    public init(strings: NavigationBarStrings) {
        self.strings = strings

        super.init()

        self.isAccessibilityElement = false
        self.isGestureEnabled = false
    }

    var manualText: String {
        return self.nodes.first?.text ?? ""
    }

    var manualAlpha: CGFloat = 1.0 {
        didSet {
            for node in self.nodes {
                node.alpha = self.manualAlpha
            }
        }
    }

    func updateStrings(_ strings: NavigationBarStrings) {
        self.strings = strings
    }

    static func legacyText(for item: UIBarButtonItem, strings: NavigationBarStrings) -> (text: String, bold: Bool) {
        let title = item.title ?? ""
        switch title {
        case "___close":
            return (strings.close.isEmpty ? "Close" : strings.close, false)
        case "___done":
            return (strings.done.isEmpty ? "Done" : strings.done, true)
        case "___clear":
            return (strings.close.isEmpty ? "Close" : strings.close, false)
        default:
            return (title, item.style == .done)
        }
    }

    private func makeItemNode() -> LegacyNavigationButtonItemNode {
        let node = LegacyNavigationButtonItemNode()
        node.color = self.color
        node.disabledColor = self.disabledColor
        node.rippleColor = self.rippleColor
        node.highlightChanged = { [weak node, weak self] value in
            if let strongSelf = self, let node = node {
                if let index = strongSelf.nodes.firstIndex(where: { $0 === node }) {
                    strongSelf.highlightChanged(index, value)
                }
            }
        }
        node.pressed = { [weak self, weak node] in
            if let strongSelf = self, let node = node {
                if let index = strongSelf.nodes.firstIndex(where: { $0 === node }) {
                    strongSelf.pressed(index)
                }
            }
        }
        node.titleUpdated = { [weak self, weak node] in
            guard let strongSelf = self, let node = node, let item = node.item else {
                return
            }
            if item.customDisplayNode == nil && item.image == nil {
                let (text, bold) = LegacyNavigationButtonNode.legacyText(for: item, strings: strongSelf.strings)
                node.text = text
                node.bold = bold
                node.invalidateCalculatedLayout()
                strongSelf.contentUpdated?()
            }
        }
        return node
    }

    func updateManualText(_ text: String, isBack: Bool = true) {
        let node: LegacyNavigationButtonItemNode
        if self.nodes.count > 0 {
            node = self.nodes[0]
        } else {
            node = self.makeItemNode()
            self.nodes.append(node)
            self.addSubnode(node)
        }
        node.alpha = self.manualAlpha
        node.item = nil
        node.image = nil
        node.text = text
        node.bold = false
        node.isEnabled = true
        node.node = nil
        node.hitTestSlop = isBack ? UIEdgeInsets(top: 0.0, left: -20.0, bottom: 0.0, right: 0.0) : UIEdgeInsets()

        if 1 < self.nodes.count {
            for i in 1 ..< self.nodes.count {
                self.nodes[i].removeFromSupernode()
            }
            self.nodes.removeSubrange(1...)
        }
    }

    func updateItems(_ items: [UIBarButtonItem], animated: Bool) {
        for i in 0 ..< items.count {
            let node: LegacyNavigationButtonItemNode
            if self.nodes.count > i {
                node = self.nodes[i]
            } else {
                node = self.makeItemNode()
                self.nodes.append(node)
                self.addSubnode(node)
            }
            let item = items[i]
            node.alpha = self.manualAlpha
            node.item = item
            if let customDisplayNode = item.customDisplayNode {
                node.image = nil
                node.text = ""
                node.bold = false
                node.isEnabled = item.isEnabled
                node.node = customDisplayNode
            } else if let image = item.image {
                node.node = nil
                node.text = ""
                node.bold = false
                node.isEnabled = item.isEnabled
                node.image = image
            } else {
                let (text, bold) = LegacyNavigationButtonNode.legacyText(for: item, strings: self.strings)
                node.node = nil
                node.image = nil
                node.text = text
                node.bold = bold
                node.isEnabled = item.isEnabled
            }

            if animated {
                node.layer.animateAlpha(from: 0.0, to: self.manualAlpha, duration: 0.16)
                node.layer.animateScale(from: 0.001, to: 1.0, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring)
            }
        }
        if items.count < self.nodes.count {
            for i in items.count ..< self.nodes.count {
                let itemNode = self.nodes[i]
                itemNode.item = nil
                if animated {
                    self.disappearingNodes.append((itemNode.frame, self.bounds.size, itemNode))
                    itemNode.layer.animateAlpha(from: self.manualAlpha, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { [weak self, weak itemNode] _ in
                        guard let itemNode else {
                            return
                        }

                        itemNode.removeFromSupernode()

                        guard let self else {
                            return
                        }
                        if let index = self.disappearingNodes.firstIndex(where: { $0.node === itemNode }) {
                            self.disappearingNodes.remove(at: index)
                        }
                    })
                    itemNode.layer.animateScale(from: 1.0, to: 0.001, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
                } else {
                    itemNode.removeFromSupernode()
                }
            }
            self.nodes.removeSubrange(items.count...)
        }
    }

    func itemView(for item: UIBarButtonItem) -> UIView? {
        guard let node = self.nodes.first(where: { $0.item === item }) else {
            return nil
        }
        if let customNode = node.node {
            return customNode.view
        }
        return node.view
    }

    func animateIn(duration: Double) {
        for node in self.nodes {
            node.layer.animateAlpha(from: 0.0, to: node.alpha, duration: duration)
        }
    }

    public func updateLayout(constrainedSize: CGSize, isLandscape: Bool, isLeftAligned: Bool) -> CGSize {
        var nodeOrigin = CGPoint()
        var totalHeight: CGFloat = 0.0
        for i in 0 ..< self.nodes.count {
            if i != 0 {
                nodeOrigin.x += 15.0
            }

            let node = self.nodes[i]

            var nodeSize = node.updateLayout(constrainedSize)

            nodeSize.width = ceil(nodeSize.width)
            nodeSize.height = ceil(nodeSize.height)
            totalHeight = max(totalHeight, nodeSize.height)
            node.frame = CGRect(origin: CGPoint(x: nodeOrigin.x, y: floor((totalHeight - nodeSize.height) / 2.0)), size: nodeSize)
            nodeOrigin.x += node.bounds.width
            if isLandscape {
                nodeOrigin.x += 16.0
            }

            if node.node == nil && node.imageNode != nil && i == self.nodes.count - 1 {
                nodeOrigin.x -= 5.0
            }
        }

        if !isLeftAligned {
            for disappearingNode in self.disappearingNodes {
                disappearingNode.node.frame = disappearingNode.frame.offsetBy(dx: nodeOrigin.x - disappearingNode.size.width, dy: (totalHeight - disappearingNode.size.height) * 0.5)
            }
        }

        return CGSize(width: nodeOrigin.x, height: totalHeight)
    }
}
