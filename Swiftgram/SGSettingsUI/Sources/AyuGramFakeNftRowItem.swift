import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI

final class AyuGramFakeNftRowItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let title: String
    let subtitle: String
    let color: UIColor
    let symbol: String
    let isReordering: Bool
    let enabled: Bool
    let sectionId: ItemListSectionId
    let action: () -> Void

    init(presentationData: ItemListPresentationData, title: String, subtitle: String, color: UIColor, symbol: String, isReordering: Bool, enabled: Bool, sectionId: ItemListSectionId, action: @escaping () -> Void) {
        self.presentationData = presentationData
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.symbol = symbol
        self.isReordering = isReordering
        self.enabled = enabled
        self.sectionId = sectionId
        self.action = action
    }

    var selectable: Bool {
        return self.enabled && !self.isReordering
    }

    func selected(listView: ListView) {
        listView.clearHighlightAnimated(true)
        if self.enabled && !self.isReordering {
            self.action()
        }
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = AyuGramFakeNftRowItemNode()
            let layout = node.applyLayout(item: self, params: params, neighbors: itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            completion(node, {
                return (nil, { _ in })
            })
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let nodeValue = node() as? AyuGramFakeNftRowItemNode else {
                return
            }
            let layout = nodeValue.applyLayout(item: self, params: params, neighbors: itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
            completion(layout, { _ in })
        }
    }
}

private final class AyuGramFakeNftRowItemNode: ListViewItemNode {
    private let backgroundNode = ASDisplayNode()
    private let topStripeNode = ASDisplayNode()
    private let bottomStripeNode = ASDisplayNode()
    private let maskNode = ASImageNode()
    private let highlightedBackgroundNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let titleNode = ImmediateTextNode()
    private let subtitleNode = ImmediateTextNode()
    private let arrowNode = ASImageNode()
    private var reorderControlNode: ItemListEditableReorderControlNode?
    private var iconKey: String?
    private var item: AyuGramFakeNftRowItem?

    init() {
        super.init(layerBacked: false)
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode.isLayerBacked = true
        self.highlightedBackgroundNode.isLayerBacked = true
        self.maskNode.isUserInteractionEnabled = false
        self.iconNode.isLayerBacked = true
        self.iconNode.displaysAsynchronously = false
        self.arrowNode.isLayerBacked = true
        self.arrowNode.displaysAsynchronously = false
        self.titleNode.maximumNumberOfLines = 1
        self.titleNode.isUserInteractionEnabled = false
        self.subtitleNode.maximumNumberOfLines = 1
        self.subtitleNode.isUserInteractionEnabled = false
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.topStripeNode)
        self.addSubnode(self.bottomStripeNode)
        self.addSubnode(self.maskNode)
        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
        self.addSubnode(self.arrowNode)
    }

    func applyLayout(item: AyuGramFakeNftRowItem, params: ListViewItemLayoutParams, neighbors: ItemListNeighbors) -> ListViewItemNodeLayout {
        self.item = item
        let theme = item.presentationData.theme
        let separatorHeight = UIScreenPixel
        let leftInset: CGFloat = params.leftInset + 59.0
        let rightControlWidth: CGFloat = item.isReordering ? 40.0 : 30.0
        let textWidth = max(10.0, params.width - params.rightInset - leftInset - rightControlWidth - 12.0)

        self.titleNode.attributedText = NSAttributedString(string: item.title, font: Font.regular(item.presentationData.fontSize.itemListBaseFontSize), textColor: item.enabled ? theme.list.itemPrimaryTextColor : theme.list.itemDisabledTextColor)
        let titleSize = self.titleNode.updateLayout(CGSize(width: textWidth, height: 100.0))
        var subtitleSize = CGSize()
        if !item.subtitle.isEmpty {
            self.subtitleNode.attributedText = NSAttributedString(string: item.subtitle, font: Font.regular(floor(item.presentationData.fontSize.itemListBaseFontSize * 13.0 / 17.0)), textColor: theme.list.itemAccentColor)
            subtitleSize = self.subtitleNode.updateLayout(CGSize(width: textWidth, height: 100.0))
            self.subtitleNode.isHidden = false
        } else {
            self.subtitleNode.isHidden = true
        }

        let verticalInset: CGFloat = item.subtitle.isEmpty ? 15.0 : 10.0
        let height = verticalInset * 2.0 + titleSize.height + (item.subtitle.isEmpty ? 0.0 : 1.0 + subtitleSize.height)
        let contentSize = CGSize(width: params.width, height: height)
        let insets = itemListNeighborsGroupedInsets(neighbors, params)

        self.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.topStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
        self.bottomStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
        self.highlightedBackgroundNode.backgroundColor = theme.list.itemHighlightedBackgroundColor

        let hasCorners = itemListHasRoundedBlockLayout(params)
        var hasTopCorners = false
        var hasBottomCorners = false
        switch neighbors.top {
        case .sameSection(false):
            self.topStripeNode.isHidden = true
        default:
            hasTopCorners = true
            self.topStripeNode.isHidden = hasCorners
        }
        let bottomStripeInset: CGFloat
        switch neighbors.bottom {
        case .sameSection(false):
            bottomStripeInset = leftInset
            self.bottomStripeNode.isHidden = false
        default:
            bottomStripeInset = 0.0
            hasBottomCorners = true
            self.bottomStripeNode.isHidden = hasCorners
        }
        self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: true) : nil

        let backgroundFrame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
        self.backgroundNode.frame = backgroundFrame
        self.highlightedBackgroundNode.frame = backgroundFrame
        self.maskNode.frame = backgroundFrame.inset(by: UIEdgeInsets(top: 0.0, left: params.leftInset, bottom: 0.0, right: params.rightInset))
        self.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
        self.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: max(0.0, params.width - params.rightInset - bottomStripeInset - 16.0), height: separatorHeight))

        let iconKey = item.symbol + "_" + item.color.description
        if self.iconKey != iconKey {
            self.iconKey = iconKey
            self.iconNode.image = ayuGramRowIcon(item.symbol, color: item.color)
        }
        if let image = self.iconNode.image {
            self.iconNode.frame = CGRect(origin: CGPoint(x: params.leftInset + floor((59.0 - image.size.width) / 2.0), y: floor((height - image.size.height) / 2.0)), size: image.size)
        }
        self.iconNode.alpha = item.enabled ? 1.0 : 0.5

        self.titleNode.frame = CGRect(origin: CGPoint(x: leftInset, y: verticalInset), size: titleSize)
        self.subtitleNode.frame = CGRect(origin: CGPoint(x: leftInset, y: verticalInset + titleSize.height + 1.0), size: subtitleSize)

        if item.isReordering {
            self.arrowNode.isHidden = true
            let (controlWidth, controlApply) = ItemListEditableReorderControlNode.asyncLayout(self.reorderControlNode)(theme)
            let controlNode = controlApply(height, false, .immediate)
            if self.reorderControlNode == nil {
                self.reorderControlNode = controlNode
                self.addSubnode(controlNode)
            }
            controlNode.frame = CGRect(origin: CGPoint(x: params.width - params.rightInset - controlWidth, y: 0.0), size: CGSize(width: controlWidth, height: height))
        } else {
            if let reorderControlNode = self.reorderControlNode {
                self.reorderControlNode = nil
                reorderControlNode.removeFromSupernode()
            }
            self.arrowNode.isHidden = false
            self.arrowNode.image = PresentationResourcesItemList.disclosureArrowImage(theme)
            if let arrow = self.arrowNode.image {
                self.arrowNode.frame = CGRect(origin: CGPoint(x: params.width - params.rightInset - 16.0 - arrow.size.width, y: floor((height - arrow.size.height) / 2.0)), size: arrow.size)
            }
        }

        return ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
    }

    override func isReorderable(at point: CGPoint) -> Bool {
        if let reorderControlNode = self.reorderControlNode, reorderControlNode.frame.contains(point) {
            return true
        }
        return false
    }

    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        super.setHighlighted(highlighted, at: point, animated: animated)
        if highlighted, let item = self.item, item.selectable {
            self.highlightedBackgroundNode.alpha = 1.0
            if self.highlightedBackgroundNode.supernode == nil {
                self.insertSubnode(self.highlightedBackgroundNode, aboveSubnode: self.bottomStripeNode)
            }
        } else if self.highlightedBackgroundNode.supernode != nil {
            if animated {
                self.highlightedBackgroundNode.layer.animateAlpha(from: self.highlightedBackgroundNode.alpha, to: 0.0, duration: 0.4, completion: { [weak self] completed in
                    if completed {
                        self?.highlightedBackgroundNode.removeFromSupernode()
                    }
                })
                self.highlightedBackgroundNode.alpha = 0.0
            } else {
                self.highlightedBackgroundNode.removeFromSupernode()
            }
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
