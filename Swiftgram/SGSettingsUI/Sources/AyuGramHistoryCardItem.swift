import Foundation
import UIKit
import ImageIO
import AVFoundation
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import AvatarNode
import SGStrings

func ayuGramArchivedImage(_ url: URL, maximumPixels: Int) -> UIImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [String: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways as String: true,
        kCGImageSourceCreateThumbnailWithTransform as String: true,
        kCGImageSourceThumbnailMaxPixelSize as String: max(1, maximumPixels),
        kCGImageSourceShouldCacheImmediately as String: true
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

// Decoded previews are cached so list updates never decode the same archive file twice.
private let ayuGramPreviewCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 60
    return cache
}()

private let ayuGramAvatarColors: [(UInt32, UInt32)] = [
    (0xFF516A, 0xFF885E), (0xFFA85C, 0xFFCD6A), (0x665FFF, 0x82B1FF), (0x54CB68, 0xA0DE7E),
    (0x4ACCCD, 0x00FCFD), (0x2A9EF1, 0x72D5FD), (0xD669ED, 0xE0A2F3)
]

private func ayuGramInitials(_ title: String) -> String {
    let words = title.split(whereSeparator: { $0 == " " || $0 == "\n" }).prefix(2)
    let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
    return letters.isEmpty ? "?" : letters.joined()
}

private func ayuGramTextHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    return ceil((text as NSString).boundingRect(with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height)
}

private func ayuGramSymbol(_ name: String, size: CGFloat, weight: UIImage.SymbolWeight = .semibold) -> UIImage? {
    return UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))?.withRenderingMode(.alwaysTemplate)
}

private func ayuGramEditedColor(_ theme: PresentationTheme) -> UIColor {
    return theme.overallDarkAppearance ? UIColor(rgb: 0xFF9F0A) : UIColor(rgb: 0xF09000)
}

/// One list item backed by a single main-thread layout pass; subclasses only lay out content.
class AyuGramHistoryBaseItem: ListViewItem, ItemListItem {
    let sectionId: ItemListSectionId
    var isAlwaysPlain: Bool { true }
    init(sectionId: ItemListSectionId) {
        self.sectionId = sectionId
    }
    func makeNode() -> AyuGramHistoryBaseNode {
        preconditionFailure()
    }
    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        Queue.mainQueue().async {
            let node = self.makeNode()
            let layout = node.layoutHistory(self, params: params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            completion(node, { (nil, { _ in }) })
        }
    }
    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            guard let node = node() as? AyuGramHistoryBaseNode else { return }
            let layout = node.layoutHistory(self, params: params)
            completion(layout, { _ in })
        }
    }
}

class AyuGramHistoryBaseNode: ListViewItemNode {
    init() {
        super.init(layerBacked: false)
    }
    func layoutHistory(_ item: AyuGramHistoryBaseItem, params: ListViewItemLayoutParams) -> ListViewItemNodeLayout {
        preconditionFailure()
    }
}

// MARK: - Summary header

struct AyuGramHistorySummary: Equatable {
    var total: Int
    var deleted: Int
    var edited: Int
    var filter: Int
}

final class AyuGramHistoryHeroItem: AyuGramHistoryBaseItem {
    let data: ItemListPresentationData
    let summary: AyuGramHistorySummary
    let select: (Int) -> Void
    init(data: ItemListPresentationData, summary: AyuGramHistorySummary, sectionId: ItemListSectionId, select: @escaping (Int) -> Void) {
        self.data = data
        self.summary = summary
        self.select = select
        super.init(sectionId: sectionId)
    }
    override func makeNode() -> AyuGramHistoryBaseNode { AyuGramHistoryHeroNode() }
}

private final class AyuGramHistoryHeroNode: AyuGramHistoryBaseNode {
    private let card = UIView()
    private let iconBackground = CAGradientLayer()
    private let icon = UIImageView()
    private let title = UILabel()
    private let subtitle = UILabel()
    private var tiles: [(button: UIButton, count: UILabel, label: UILabel)] = []
    private var select: ((Int) -> Void)?

    override init() {
        super.init()
        view.addSubview(card)
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.layer.addSublayer(iconBackground)
        iconBackground.startPoint = CGPoint(x: 0, y: 0)
        iconBackground.endPoint = CGPoint(x: 1, y: 1)
        iconBackground.cornerRadius = 30
        icon.contentMode = .center
        icon.tintColor = .white
        icon.image = ayuGramSymbol("clock.arrow.circlepath", size: 26)
        title.font = UIFont.systemFont(ofSize: 21, weight: .bold)
        title.textAlignment = .center
        subtitle.font = UIFont.systemFont(ofSize: 14)
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        for view in [icon, title, subtitle] { card.addSubview(view) }
        for index in 0 ..< 3 {
            let button = UIButton(type: .custom)
            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            button.tag = index
            button.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
            let count = UILabel()
            count.font = UIFont.systemFont(ofSize: 22, weight: .bold)
            count.textAlignment = .center
            let label = UILabel()
            label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            for child in [count, label] {
                child.isUserInteractionEnabled = false
                button.addSubview(child)
            }
            card.addSubview(button)
            tiles.append((button, count, label))
        }
    }

    @objc private func tileTapped(_ sender: UIButton) {
        UISelectionFeedbackGenerator().selectionChanged()
        select?(sender.tag)
    }

    override func layoutHistory(_ item: AyuGramHistoryBaseItem, params: ListViewItemLayoutParams) -> ListViewItemNodeLayout {
        guard let item = item as? AyuGramHistoryHeroItem else { preconditionFailure() }
        select = item.select
        let theme = item.data.theme
        let locale = item.data.strings.baseLanguageCode
        let summary = item.summary
        let width = max(120, params.width - params.leftInset - params.rightInset - 32)
        let inner = width - 32
        card.backgroundColor = theme.list.itemBlocksBackgroundColor
        let accent = theme.list.itemAccentColor
        iconBackground.colors = [accent.withMultipliedAlpha(0.75).cgColor, accent.cgColor]
        iconBackground.frame = CGRect(x: floor((width - 60) / 2), y: 20, width: 60, height: 60)
        icon.frame = iconBackground.frame
        title.text = i18n("Ayu.History", locale)
        title.textColor = theme.list.itemPrimaryTextColor
        title.frame = CGRect(x: 16, y: 92, width: inner, height: 26)
        subtitle.text = i18n("Ayu.HistorySubtitle", locale)
        subtitle.textColor = theme.list.itemSecondaryTextColor
        let subtitleHeight = ayuGramTextHeight(subtitle.text ?? "", font: subtitle.font, width: inner)
        subtitle.frame = CGRect(x: 16, y: 122, width: inner, height: subtitleHeight)
        let values = [
            (summary.total, i18n("Ayu.HistoryAll", locale), accent),
            (summary.deleted, i18n("Ayu.Deleted", locale), theme.list.itemDestructiveColor),
            (summary.edited, i18n("Ayu.HistoryEdited", locale), ayuGramEditedColor(theme))
        ]
        let spacing: CGFloat = 8
        let tileWidth = floor((inner - spacing * 2) / 3)
        let tileY = subtitle.frame.maxY + 18
        for (index, tile) in tiles.enumerated() {
            let (value, text, color) = values[index]
            let selected = summary.filter == index
            tile.button.frame = CGRect(x: 16 + CGFloat(index) * (tileWidth + spacing), y: tileY, width: tileWidth, height: 64)
            tile.button.backgroundColor = selected ? color : color.withMultipliedAlpha(theme.overallDarkAppearance ? 0.18 : 0.1)
            tile.count.text = "\(value)"
            tile.count.textColor = selected ? .white : color
            tile.count.frame = CGRect(x: 4, y: 10, width: tileWidth - 8, height: 26)
            tile.label.text = text
            tile.label.textColor = selected ? UIColor.white.withAlphaComponent(0.9) : theme.list.itemSecondaryTextColor
            tile.label.frame = CGRect(x: 4, y: 38, width: tileWidth - 8, height: 16)
            tile.button.accessibilityLabel = "\(text), \(value)"
            tile.button.accessibilityTraits = selected ? [.button, .selected] : .button
        }
        let height = tileY + 64 + 16
        card.frame = CGRect(x: params.leftInset + 16, y: 12, width: width, height: height)
        return ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: height + 12), insets: .zero)
    }
}

// MARK: - Empty state

final class AyuGramHistoryEmptyItem: AyuGramHistoryBaseItem {
    let data: ItemListPresentationData
    let text: String
    let buttonTitle: String?
    let action: () -> Void
    init(data: ItemListPresentationData, text: String, buttonTitle: String?, sectionId: ItemListSectionId, action: @escaping () -> Void) {
        self.data = data
        self.text = text
        self.buttonTitle = buttonTitle
        self.action = action
        super.init(sectionId: sectionId)
    }
    override func makeNode() -> AyuGramHistoryBaseNode { AyuGramHistoryEmptyNode() }
}

private final class AyuGramHistoryEmptyNode: AyuGramHistoryBaseNode {
    private let icon = UIImageView()
    private let title = UILabel()
    private let text = UILabel()
    private let button = UIButton(type: .system)
    private var action: (() -> Void)?

    override init() {
        super.init()
        icon.contentMode = .center
        icon.image = ayuGramSymbol("tray", size: 40, weight: .regular)
        title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        title.textAlignment = .center
        text.font = UIFont.systemFont(ofSize: 14)
        text.textAlignment = .center
        text.numberOfLines = 0
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.addTarget(self, action: #selector(emptyButtonTapped), for: .touchUpInside)
        for child in [icon, title, text, button] { view.addSubview(child) }
    }

    @objc private func emptyButtonTapped() { action?() }

    override func layoutHistory(_ item: AyuGramHistoryBaseItem, params: ListViewItemLayoutParams) -> ListViewItemNodeLayout {
        guard let item = item as? AyuGramHistoryEmptyItem else { preconditionFailure() }
        action = item.action
        let theme = item.data.theme
        let x = params.leftInset + 32
        let width = max(80, params.width - params.leftInset - params.rightInset - 64)
        icon.tintColor = theme.list.itemSecondaryTextColor.withMultipliedAlpha(0.7)
        icon.frame = CGRect(x: x, y: 24, width: width, height: 48)
        title.text = i18n("Ayu.EmptyHistory", item.data.strings.baseLanguageCode)
        title.textColor = theme.list.itemPrimaryTextColor
        title.frame = CGRect(x: x, y: 82, width: width, height: 22)
        text.text = item.text
        text.textColor = theme.list.itemSecondaryTextColor
        let textHeight = ayuGramTextHeight(item.text, font: text.font, width: width)
        text.frame = CGRect(x: x, y: 110, width: width, height: textHeight)
        var bottom = text.frame.maxY + 20
        if let buttonTitle = item.buttonTitle {
            button.isHidden = false
            button.setTitle(buttonTitle, for: .normal)
            button.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .normal)
            button.backgroundColor = theme.list.itemCheckColors.fillColor
            let buttonWidth = min(width, 260)
            button.frame = CGRect(x: x + floor((width - buttonWidth) / 2), y: bottom, width: buttonWidth, height: 46)
            bottom = button.frame.maxY + 20
        } else {
            button.isHidden = true
        }
        return ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: bottom), insets: .zero)
    }
}

// MARK: - Record card

final class AyuGramHistoryCardItem: AyuGramHistoryBaseItem {
    let context: AccountContext
    let data: ItemListPresentationData
    let record: AyuGramHistoryEntry
    let peer: EnginePeer?
    let openAuthor: () -> Void
    let openChat: () -> Void
    let openMedia: () -> Void
    let openMenu: () -> Void
    init(context: AccountContext, data: ItemListPresentationData, record: AyuGramHistoryEntry, peer: EnginePeer?, sectionId: ItemListSectionId, openAuthor: @escaping () -> Void, openChat: @escaping () -> Void, openMedia: @escaping () -> Void, openMenu: @escaping () -> Void) {
        self.peer = peer
        self.context = context
        self.data = data
        self.record = record
        self.openAuthor = openAuthor
        self.openChat = openChat
        self.openMedia = openMedia
        self.openMenu = openMenu
        super.init(sectionId: sectionId)
    }
    override func makeNode() -> AyuGramHistoryBaseNode { AyuGramHistoryCardNode() }
}

/// A tinted quote block with a coloured leading bar, an optional caption and the message text.
private final class AyuGramQuoteView: UIView {
    private let bar = UIView()
    private let caption = UILabel()
    private let text = UILabel()
    static let textFont = UIFont.systemFont(ofSize: 15)
    static let captionFont = UIFont.systemFont(ofSize: 12, weight: .semibold)

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true
        caption.font = AyuGramQuoteView.captionFont
        text.font = AyuGramQuoteView.textFont
        text.numberOfLines = 0
        for child in [bar, caption, text] { addSubview(child) }
    }
    required init?(coder: NSCoder) { fatalError() }

    static func height(caption: String?, text: String, width: CGFloat) -> CGFloat {
        let captionHeight: CGFloat = caption == nil ? 0 : 18
        return 8 + captionHeight + ayuGramTextHeight(text, font: textFont, width: width - 24) + 8
    }

    func update(caption captionText: String?, text value: String, color: UIColor, textColor: UIColor, dark: Bool, width: CGFloat) -> CGFloat {
        backgroundColor = color.withMultipliedAlpha(dark ? 0.16 : 0.09)
        bar.backgroundColor = color
        caption.text = captionText
        caption.textColor = color
        caption.isHidden = captionText == nil
        text.text = value
        text.textColor = textColor
        let height = AyuGramQuoteView.height(caption: captionText, text: value, width: width)
        bar.frame = CGRect(x: 0, y: 0, width: 3, height: height)
        caption.frame = CGRect(x: 14, y: 8, width: width - 24, height: 16)
        let textY: CGFloat = captionText == nil ? 8 : 26
        text.frame = CGRect(x: 14, y: textY, width: width - 24, height: height - textY - 8)
        return height
    }
}

private final class AyuGramHistoryCardNode: AyuGramHistoryBaseNode {
    private let card = UIView()
    private let avatar = CAGradientLayer()
    private let initials = UILabel()
    private let avatarNode = AvatarNode(font: avatarPlaceholderFont(size: 16))
    private let authorButton = UIButton(type: .custom)
    private let author = UILabel()
    private let chatTitle = UILabel()
    private let pill = UIView()
    private let pillIcon = UIImageView()
    private let pillText = UILabel()
    private let time = UILabel()
    private let before = AyuGramQuoteView()
    private let after = AyuGramQuoteView()
    private let preview = UIImageView()
    private let playBadge = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private let playIcon = UIImageView()
    private let gifBadge = UILabel()
    private let fileIcon = UIImageView()
    private let fileTitle = UILabel()
    private let mediaButton = UIButton(type: .custom)
    private let separator = UIView()
    private let openButton = UIButton(type: .custom)
    private let openIcon = UIImageView()
    private let openTitle = UILabel()
    private var item: AyuGramHistoryCardItem?

    override init() {
        super.init()
        view.addSubview(card)
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.addSublayer(avatar)
        card.addSubview(avatarNode.view)
        avatarNode.view.isUserInteractionEnabled = false
        avatar.startPoint = CGPoint(x: 0.5, y: 0)
        avatar.endPoint = CGPoint(x: 0.5, y: 1)
        avatar.cornerRadius = 20
        initials.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        initials.textColor = .white
        initials.textAlignment = .center
        author.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        author.lineBreakMode = .byTruncatingTail
        chatTitle.font = UIFont.systemFont(ofSize: 13)
        chatTitle.lineBreakMode = .byTruncatingTail
        pill.layer.cornerRadius = 11
        pillIcon.contentMode = .center
        pillText.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        pill.addSubview(pillIcon)
        pill.addSubview(pillText)
        time.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        time.textAlignment = .right
        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.layer.cornerRadius = 12
        preview.layer.cornerCurve = .continuous
        playBadge.clipsToBounds = true
        playBadge.layer.cornerRadius = 24
        playIcon.contentMode = .center
        playIcon.tintColor = .white
        playIcon.image = ayuGramSymbol("play.fill", size: 20)
        playBadge.contentView.addSubview(playIcon)
        preview.addSubview(playBadge)
        gifBadge.text = "GIF"
        gifBadge.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        gifBadge.textColor = .white
        gifBadge.textAlignment = .center
        gifBadge.backgroundColor = UIColor(white: 0, alpha: 0.5)
        gifBadge.layer.cornerRadius = 6
        gifBadge.clipsToBounds = true
        preview.addSubview(gifBadge)
        fileIcon.contentMode = .center
        fileIcon.layer.cornerRadius = 10
        fileIcon.layer.cornerCurve = .continuous
        fileIcon.image = ayuGramSymbol("doc.fill", size: 18)
        fileTitle.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        fileTitle.lineBreakMode = .byTruncatingMiddle
        openIcon.contentMode = .center
        openIcon.image = ayuGramSymbol("arrow.turn.up.right", size: 14)
        openTitle.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        openButton.addSubview(openIcon)
        openButton.addSubview(openTitle)
        for child in [initials, author, chatTitle, authorButton, pill, time, before, after, preview, fileIcon, fileTitle, mediaButton, separator, openButton] {
            card.addSubview(child)
        }
        for child in [initials, author, chatTitle, pill, fileIcon, fileTitle, openIcon, openTitle] {
            child.isUserInteractionEnabled = false
        }
        authorButton.addTarget(self, action: #selector(openAuthor), for: .touchUpInside)
        mediaButton.addTarget(self, action: #selector(openMedia), for: .touchUpInside)
        openButton.addTarget(self, action: #selector(openChat), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        card.addGestureRecognizer(longPress)
    }

    @objc private func openChat() { item?.openChat() }
    @objc private func openAuthor() { item?.openAuthor() }
    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            item?.openMenu()
        }
    }
    @objc private func openMedia() {
        // Voice messages (and ones archived as .bin before their kind was known) play in the chat.
        if item?.record.mediaKind == "voice" || item?.record.photoFileName?.hasSuffix(".bin") == true {
            item?.openChat()
        } else {
            item?.openMedia()
        }
    }

    override func layoutHistory(_ baseItem: AyuGramHistoryBaseItem, params: ListViewItemLayoutParams) -> ListViewItemNodeLayout {
        guard let item = baseItem as? AyuGramHistoryCardItem else { preconditionFailure() }
        self.item = item
        let record = item.record
        let theme = item.data.theme
        let dark = theme.overallDarkAppearance
        let locale = item.data.strings.baseLanguageCode
        let primary = theme.list.itemPrimaryTextColor
        let secondary = theme.list.itemSecondaryTextColor
        let accent = theme.list.itemAccentColor
        let edited = record.event == "edited"
        let eventColor = edited ? ayuGramEditedColor(theme) : theme.list.itemDestructiveColor
        let width = max(120, params.width - params.leftInset - params.rightInset - 32)
        let inner = width - 28
        card.backgroundColor = theme.list.itemBlocksBackgroundColor

        // Header: avatar, author, chat, event pill and time.
        let name = record.author.isEmpty ? record.peerTitle : record.author
        let colors = ayuGramAvatarColors[Int(UInt64(bitPattern: record.authorId ?? record.peerId) % UInt64(ayuGramAvatarColors.count))]
        avatar.colors = [UIColor(rgb: colors.1).cgColor, UIColor(rgb: colors.0).cgColor]
        avatar.frame = CGRect(x: 14, y: 14, width: 40, height: 40)
        initials.text = ayuGramInitials(name)
        initials.frame = avatar.frame
        // The real profile photo (including a personal photo you set for a contact); initials until it loads or without a peer.
        // The node's own frame sizes its content; setting only the view's frame left it zero-sized.
        avatarNode.frame = avatar.frame
        avatarNode.isHidden = item.peer == nil
        if let peer = item.peer {
            avatarNode.setPeer(context: item.context, theme: theme, peer: peer, synchronousLoad: false, displayDimensions: CGSize(width: 40, height: 40))
        }

        pillText.text = i18n(edited ? "Ayu.HistoryEdited" : "Ayu.Deleted", locale)
        pillText.textColor = eventColor
        pillIcon.image = ayuGramSymbol(edited ? "pencil" : "trash.fill", size: 10)
        pillIcon.tintColor = eventColor
        pill.backgroundColor = eventColor.withMultipliedAlpha(dark ? 0.2 : 0.12)
        let pillTextWidth = min(120, ceil(pillText.sizeThatFits(CGSize(width: 200, height: 22)).width))
        let pillWidth = 8 + 12 + 4 + pillTextWidth + 10
        pill.frame = CGRect(x: 14 + inner - pillWidth, y: 14, width: pillWidth, height: 22)
        pillIcon.frame = CGRect(x: 8, y: 0, width: 12, height: 22)
        pillText.frame = CGRect(x: 24, y: 0, width: pillTextWidth, height: 22)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: locale)
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        time.text = timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(record.timestamp)))
        time.textColor = secondary
        time.frame = CGRect(x: 14 + inner - 90, y: 39, width: 90, height: 16)

        let textX: CGFloat = 66
        let nameWidth = max(40, 14 + inner - pillWidth - 8 - textX)
        let showChat = !record.author.isEmpty && record.author != record.peerTitle
        author.text = name
        author.textColor = UIColor(rgb: colors.0).mixedWith(primary, alpha: dark ? 0.15 : 0.35)
        chatTitle.text = record.peerTitle
        chatTitle.textColor = secondary
        chatTitle.isHidden = !showChat
        if showChat {
            author.frame = CGRect(x: textX, y: 14, width: nameWidth, height: 21)
            chatTitle.frame = CGRect(x: textX, y: 36, width: max(40, 14 + inner - 98 - textX), height: 17)
        } else {
            author.frame = CGRect(x: textX, y: 23, width: nameWidth, height: 21)
        }
        authorButton.frame = CGRect(x: 8, y: 8, width: textX + nameWidth - 8, height: 52)
        authorButton.isEnabled = record.authorId != nil
        authorButton.accessibilityLabel = name

        // Body: the archived text, and for edits the current text below it.
        var bottom: CGFloat = 68
        before.isHidden = record.text.isEmpty
        if !record.text.isEmpty {
            let height = before.update(caption: edited ? i18n("Ayu.BeforeEdit", locale) : nil, text: record.text, color: eventColor, textColor: primary, dark: dark, width: inner)
            before.frame = CGRect(x: 14, y: bottom, width: inner, height: height)
            bottom = before.frame.maxY + 8
        }
        let current = edited ? record.updatedText : nil
        after.isHidden = current == nil
        if let current {
            let height = after.update(caption: i18n("Ayu.HistoryNow", locale), text: current.isEmpty ? "—" : current, color: accent, textColor: primary, dark: dark, width: inner)
            after.frame = CGRect(x: 14, y: bottom, width: inner, height: height)
            bottom = after.frame.maxY + 8
        }

        // Media: inline photo or video preview, or a file row.
        preview.isHidden = true
        fileIcon.isHidden = true
        fileTitle.isHidden = true
        mediaButton.isHidden = true
        if let name = record.photoFileName, let url = item.context.engine.ayuGramArchivedPhotoURL(name), FileManager.default.fileExists(atPath: url.path) {
            let kind = record.mediaKind ?? "photo"
            let scale = UIScreen.main.scale
            let round = kind == "round"
            let moving = kind == "video" || kind == "gif" || round
            if kind == "photo" || moving {
                let key = name as NSString
                var image = ayuGramPreviewCache.object(forKey: key)
                if image == nil && kind == "photo" {
                    image = ayuGramArchivedImage(url, maximumPixels: min(1280, Int(inner * scale)))
                    if let image { ayuGramPreviewCache.setObject(image, forKey: key) }
                }
                let height: CGFloat
                if kind == "photo", let image, image.size.width > 0 {
                    height = min(260, max(120, inner * image.size.height / image.size.width))
                } else if round {
                    height = min(200, inner)
                } else {
                    height = min(220, floor(inner * 9 / 16))
                }
                preview.image = image
                preview.backgroundColor = eventColor.withMultipliedAlpha(0.12)
                preview.isHidden = false
                // A round video is a circle; everything else fills the card width.
                preview.frame = round ? CGRect(x: 14 + floor((inner - height) / 2), y: bottom, width: height, height: height) : CGRect(x: 14, y: bottom, width: inner, height: height)
                preview.layer.cornerRadius = round ? height / 2 : 12
                let previewWidth = preview.frame.width
                playBadge.isHidden = kind != "video" && !round
                gifBadge.isHidden = kind != "gif"
                gifBadge.frame = CGRect(x: 8, y: 8, width: 34, height: 20)
                playBadge.frame = CGRect(x: floor((previewWidth - 48) / 2), y: floor((height - 48) / 2), width: 48, height: 48)
                playIcon.frame = CGRect(x: 2, y: 0, width: 48, height: 48)
                if moving && image == nil {
                    let maximum = CGSize(width: previewWidth * scale, height: height * scale)
                    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                        generator.appliesPreferredTrackTransform = true
                        generator.maximumSize = maximum
                        guard let frame = try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) else { return }
                        let thumbnail = UIImage(cgImage: frame)
                        ayuGramPreviewCache.setObject(thumbnail, forKey: key)
                        DispatchQueue.main.async {
                            guard let self, self.item?.record.photoFileName == name else { return }
                            self.preview.image = thumbnail
                        }
                    }
                }
                mediaButton.frame = preview.frame
                mediaButton.accessibilityLabel = kind == "gif" ? "GIF" : round ? item.data.strings.Message_VideoMessage : kind == "video" ? item.data.strings.Message_Video : item.data.strings.Settings_ViewPhoto
                bottom = preview.frame.maxY + 8
            } else {
                fileIcon.isHidden = false
                fileTitle.isHidden = false
                fileIcon.backgroundColor = accent.withMultipliedAlpha(dark ? 0.2 : 0.12)
                fileIcon.tintColor = accent
                fileIcon.frame = CGRect(x: 14, y: bottom, width: 44, height: 44)
                if kind == "voice" {
                    // Voice messages are Opus, which AVFoundation cannot play; they open in the chat's own player.
                    fileIcon.image = ayuGramSymbol("waveform", size: 18)
                    fileTitle.text = item.data.strings.Message_Audio + (record.mediaTitle.map { " · " + $0 } ?? "")
                } else {
                    fileIcon.image = ayuGramSymbol("doc.fill", size: 18)
                    fileTitle.text = record.mediaTitle ?? item.data.strings.Message_File
                }
                fileTitle.textColor = primary
                fileTitle.frame = CGRect(x: 68, y: bottom, width: inner - 54, height: 44)
                mediaButton.frame = CGRect(x: 14, y: bottom, width: inner, height: 44)
                mediaButton.accessibilityLabel = fileTitle.text
                bottom += 52
            }
            mediaButton.isHidden = false
        }

        // Footer: jump to the message in its chat.
        bottom += 2
        separator.backgroundColor = theme.list.itemBlocksSeparatorColor
        separator.frame = CGRect(x: 14, y: bottom, width: inner, height: UIScreenPixel)
        openTitle.text = i18n("Ayu.HistoryShowMessage", locale)
        openTitle.textColor = accent
        openIcon.tintColor = accent
        openButton.frame = CGRect(x: 14, y: bottom, width: inner, height: 44)
        openIcon.frame = CGRect(x: 0, y: 0, width: 18, height: 44)
        openTitle.frame = CGRect(x: 26, y: 0, width: inner - 26, height: 44)
        openButton.accessibilityLabel = openTitle.text
        openButton.accessibilityHint = item.data.strings.VoiceOver_Chat_GoToOriginalMessage
        bottom += 44

        card.frame = CGRect(x: params.leftInset + 16, y: 5, width: width, height: bottom)
        return ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: bottom + 10), insets: .zero)
    }
}
