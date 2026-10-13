import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import SGSimpleSettings

final class AyuGramAppearancePreviewItem: ListViewItem, ItemListItem {
    let data: ItemListPresentationData
    let scope: AyuGramAppearanceScope
    let settings: AyuGramAppearanceSettings
    let sectionId: ItemListSectionId
    var isAlwaysPlain: Bool { true }
    init(data: ItemListPresentationData, scope: AyuGramAppearanceScope, settings: AyuGramAppearanceSettings, sectionId: ItemListSectionId) {
        self.data = data
        self.scope = scope
        self.settings = settings
        self.sectionId = sectionId
    }
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = AyuGramAppearancePreviewNode(scope: self.scope)
            let layout = node.update(self, params: params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            completion(node, { (nil, { _ in }) })
        }
    }
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? AyuGramAppearancePreviewNode else { return }
            completion(node.update(self, params: params), { _ in })
        }
    }
}

private final class AyuGramPreviewBubble: UIView {
    private let gradient = CAGradientLayer()
    private let shape = CAShapeLayer()
    private let quote = UIView()
    private let stripe = UIView()
    private let author = UILabel()
    private let reply = UILabel()
    private let text = UILabel()
    private let time = UILabel()
    private let checks = CAShapeLayer()
    private let outgoing: Bool

    init(outgoing: Bool) {
        self.outgoing = outgoing
        super.init(frame: .zero)
        layer.addSublayer(gradient)
        gradient.mask = shape
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        addSubview(quote)
        for label in [author, reply] { quote.addSubview(label) }
        quote.addSubview(stripe)
        quote.layer.cornerRadius = 6
        quote.clipsToBounds = true
        stripe.layer.cornerRadius = 1.5
        for label in [text, time] { addSubview(label) }
        text.font = .systemFont(ofSize: 15)
        text.numberOfLines = 0
        text.textAlignment = .natural
        author.font = .systemFont(ofSize: 13, weight: .semibold)
        reply.font = .systemFont(ofSize: 13)
        author.lineBreakMode = .byTruncatingTail
        reply.lineBreakMode = .byTruncatingTail
        time.font = .systemFont(ofSize: 11)
        time.text = "21:20"
        layer.addSublayer(checks)
        checks.fillColor = nil
        checks.lineWidth = 1.3
        checks.lineCap = .round
        checks.lineJoin = .round
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(data: ItemListPresentationData, width: CGFloat) -> CGFloat {
        let colors = outgoing ? data.theme.chat.message.outgoing : data.theme.chat.message.incoming
        gradient.colors = colors.bubble.withWallpaper.fill.map { $0.cgColor }
        text.text = outgoing ? data.strings.Appearance_PreviewOutgoingText : data.strings.Appearance_PreviewIncomingText
        text.textColor = colors.primaryTextColor
        time.textColor = colors.secondaryTextColor
        checks.strokeColor = colors.accentControlColor.cgColor
        checks.isHidden = !outgoing
        quote.isHidden = outgoing
        let inset: CGFloat = 14
        let contentWidth = max(1, width - inset * 2)
        var y: CGFloat = 10
        if !outgoing {
            quote.backgroundColor = colors.accentTextColor.withAlphaComponent(0.12)
            stripe.backgroundColor = colors.accentTextColor
            author.text = "Ducky"
            author.textColor = colors.accentTextColor
            reply.text = data.strings.Appearance_PreviewReplyText
            reply.textColor = colors.primaryTextColor
            quote.frame = CGRect(x: inset, y: y, width: contentWidth, height: 46)
            stripe.frame = CGRect(x: 0, y: 0, width: 3, height: 46)
            author.frame = CGRect(x: 10, y: 4, width: contentWidth - 20, height: 18)
            reply.frame = CGRect(x: 10, y: 22, width: contentWidth - 20, height: 19)
            y += 54
        }
        let textHeight = ceil(text.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude)).height)
        text.frame = CGRect(x: inset, y: y, width: contentWidth, height: textHeight)
        y += textHeight + 4
        let timeWidth = ceil(time.sizeThatFits(CGSize(width: 100, height: 20)).width)
        time.frame = CGRect(x: width - inset - timeWidth - (outgoing ? 21 : 0), y: y, width: timeWidth, height: 15)
        if outgoing {
            let path = UIBezierPath()
            for dx in [CGFloat(0), CGFloat(5)] {
                path.move(to: CGPoint(x: dx, y: 5))
                path.addLine(to: CGPoint(x: dx + 4, y: 9))
                path.addLine(to: CGPoint(x: dx + 11, y: 1))
            }
            checks.frame = CGRect(x: width - inset - 16, y: y + 2, width: 16, height: 11)
            checks.path = path.cgPath
        }
        let height = y + 24
        gradient.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let body = CGRect(x: outgoing ? 0 : 6, y: 0, width: width - 6, height: height - 4)
        let path = UIBezierPath(roundedRect: body, cornerRadius: 17)
        let tail = UIBezierPath()
        let x = outgoing ? width - 6 : 6
        let direction: CGFloat = outgoing ? 1 : -1
        tail.move(to: CGPoint(x: x - direction * 10, y: height - 19))
        tail.addQuadCurve(to: CGPoint(x: x + direction * 6, y: height), controlPoint: CGPoint(x: x, y: height - 3))
        tail.addQuadCurve(to: CGPoint(x: x - direction * 15, y: height - 7), controlPoint: CGPoint(x: x - direction * 8, y: height))
        tail.close()
        path.append(tail)
        shape.frame = gradient.bounds
        shape.path = path.cgPath
        accessibilityLabel = outgoing ? text.text : [author.text, reply.text, text.text].compactMap { $0 }.joined(separator: ". ")
        return height
    }
}

private final class AyuGramPreviewChatRow: UIView {
    private let avatar = UILabel()
    private let name = UILabel()
    private let message = UILabel()
    private let tagLabel = UILabel()
    private let date = UILabel()
    private let pin = UIImageView()
    private let separator = UIView()
    private let index: Int

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        for child in [avatar, name, message, tagLabel, date, pin, separator] { addSubview(child) }
        avatar.text = "🦆"
        avatar.textAlignment = .center
        avatar.font = .systemFont(ofSize: 30)
        avatar.layer.cornerRadius = 27
        avatar.clipsToBounds = true
        name.font = .systemFont(ofSize: 16, weight: .medium)
        message.font = .systemFont(ofSize: 14)
        message.lineBreakMode = .byTruncatingTail
        tagLabel.font = .systemFont(ofSize: 10, weight: .medium)
        tagLabel.layer.cornerRadius = 4
        tagLabel.clipsToBounds = true
        tagLabel.textAlignment = .center
        date.font = .systemFont(ofSize: 11)
        date.textAlignment = .right
        pin.image = UIImage(systemName: index == 0 ? "pin.fill" : "checkmark")
        pin.contentMode = .scaleAspectFit
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(data: ItemListPresentationData, opacity: CGFloat, width: CGFloat) {
        let theme = data.theme.chatList
        backgroundColor = (index == 0 ? theme.pinnedItemBackgroundColor : theme.itemBackgroundColor).withAlphaComponent(opacity)
        avatar.backgroundColor = index == 0 ? UIColor(red: 0.36, green: 0.68, blue: 0.88, alpha: 1) : UIColor(red: 0.66, green: 0.52, blue: 0.85, alpha: 1)
        name.text = index == 0 ? "Ducky" : "Duck Club"
        name.textColor = theme.titleColor
        message.text = index == 0 ? data.strings.Appearance_PreviewIncomingText : data.strings.Appearance_PreviewOutgoingText
        message.textColor = theme.messageTextColor
        date.text = index == 0 ? "21:20" : "21:18"
        date.textColor = theme.dateTextColor
        pin.tintColor = index == 0 ? theme.pinnedBadgeColor : theme.checkmarkColor
        tagLabel.text = index == 0 ? data.strings.Notifications_PrivateChats : data.strings.IntentsSettings_SuggestedChatsGroups
        tagLabel.textColor = data.theme.list.itemAccentColor
        tagLabel.backgroundColor = data.theme.list.itemAccentColor.withAlphaComponent(0.15)
        separator.backgroundColor = theme.itemSeparatorColor
        avatar.frame = CGRect(x: 12, y: 15, width: 54, height: 54)
        let textX: CGFloat = 78
        name.frame = CGRect(x: textX, y: 10, width: max(1, width - textX - 62), height: 21)
        message.frame = CGRect(x: textX, y: 33, width: max(1, width - textX - 35), height: 20)
        let tagWidth = min(max(1, width - textX - 40), ceil(tagLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: 20)).width) + 10)
        tagLabel.frame = CGRect(x: textX, y: 57, width: tagWidth, height: 17)
        date.frame = CGRect(x: width - 59, y: 13, width: 47, height: 16)
        pin.frame = CGRect(x: width - 28, y: 37, width: 16, height: 16)
        separator.frame = CGRect(x: textX, y: 83, width: max(1, width - textX - 12), height: 0.5)
        separator.isHidden = index == 1
        accessibilityLabel = [name.text, message.text, tagLabel.text].compactMap { $0 }.joined(separator: ". ")
    }
}

private final class AyuGramAppearancePreviewNode: ListViewItemNode {
    private let card = UIView()
    private let backdrop: AyuGramBackdropView
    private let incoming = AyuGramPreviewBubble(outgoing: false)
    private let outgoing = AyuGramPreviewBubble(outgoing: true)
    private let rows = [AyuGramPreviewChatRow(index: 0), AyuGramPreviewChatRow(index: 1)]
    private let scope: AyuGramAppearanceScope
    init(scope: AyuGramAppearanceScope) {
        self.scope = scope
        self.backdrop = AyuGramBackdropView(scope: scope)
        super.init(layerBacked: false)
        card.isUserInteractionEnabled = false
        card.clipsToBounds = true
        card.layer.cornerRadius = 20
        view.addSubview(card)
        for child in [backdrop, incoming, outgoing] { card.addSubview(child) }
        for row in rows { card.addSubview(row) }
    }
    func update(_ item: AyuGramAppearancePreviewItem, params: ListViewItemLayoutParams) -> ListViewItemNodeLayout {
        let width = max(160, params.width - params.leftInset - params.rightInset - 32)
        let isChatList = scope == .chatList
        incoming.isHidden = isChatList
        outgoing.isHidden = isChatList
        for row in rows { row.isHidden = !isChatList }
        let height: CGFloat
        if isChatList {
            height = 168
            for (index, row) in rows.enumerated() {
                row.frame = CGRect(x: 0, y: CGFloat(index) * 84, width: width, height: 84)
                row.update(data: item.data, opacity: CGFloat(item.settings.rowOpacity), width: width)
            }
        } else {
            let bubbleWidth = min(width - 32, width * 0.86)
            let incomingHeight = incoming.update(data: item.data, width: bubbleWidth)
            let outgoingHeight = outgoing.update(data: item.data, width: bubbleWidth)
            incoming.frame = CGRect(x: 10, y: 14, width: bubbleWidth, height: incomingHeight)
            outgoing.frame = CGRect(x: width - bubbleWidth - 10, y: incomingHeight + 24, width: bubbleWidth, height: outgoingHeight)
            height = incomingHeight + outgoingHeight + 38
        }
        card.frame = CGRect(x: params.leftInset + 16, y: 12, width: width, height: height)
        card.backgroundColor = isChatList ? item.data.theme.chatList.backgroundColor : item.data.theme.list.blocksBackgroundColor
        backdrop.frame = card.bounds
        backdrop.overlayColor = item.data.theme.list.blocksBackgroundColor
        backdrop.reload()
        return ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height + 24), insets: .zero)
    }
}
