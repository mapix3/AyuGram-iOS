import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import SGSimpleSettings
import SGStrings

class AyuGramHostController: ViewController {
    let context: AccountContext
    var presentationData: PresentationData
    let content: UIView

    init(context: AccountContext, title: String, content: UIView) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.content = content
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = title
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: self.presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = self.presentationData.theme.list.blocksBackgroundColor
        self.displayNodeDidLoad()
        self.displayNode.view.addSubview(self.content)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        self.content.frame = CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top))
    }
}


let ayuGramBadgeSymbols = ["sparkles", "star.fill", "heart.fill", "flame.fill", "bolt.fill", "crown.fill", "moon.stars.fill", "sun.max.fill", "leaf.fill", "pawprint.fill", "gamecontroller.fill", "music.note", "airplane", "eye.fill", "theatermasks.fill", "wand.and.stars", "diamond.fill", "shield.fill", "checkmark.seal.fill", "hare.fill", "tortoise.fill", "ant.fill", "ladybug.fill", "fish.fill", "snowflake", "drop.fill", "cloud.fill", "atom", "infinity", "hand.peace.fill"]

let ayuGramBadgePalettes: [(String, String)] = [("8E61F2", "C9B3FF"), ("FF4D6D", "FF9EAE"), ("FF7A00", "FFC266"), ("FFD60A", "FFF3A3"), ("2ECC71", "A8F0C6"), ("00B4D8", "90E0EF"), ("3A86FF", "9DBEFF"), ("FF006E", "8338EC"), ("111111", "555555"), ("F1F1F1", "BDBDBD"), ("00F5D4", "9B5DE5"), ("E63946", "1D3557")]

final class AyuGramBadgeView: UIView, UITextFieldDelegate {
    private let theme: PresentationTheme
    private let locale: String
    private let scroll = UIScrollView()
    private let previewBack = UIView()
    private let preview = UIImageView()
    private let sampleName = UILabel()
    private let sampleBadge = UIImageView()
    private let shapeControl = UISegmentedControl()
    private let iconsTitle = UILabel()
    private var iconButtons: [UIButton] = []
    private let emojiField = UITextField()
    private let colorsTitle = UILabel()
    private var colorButtons: [UIButton] = []
    private let darkLabel = UILabel()
    private let darkSwitch = UISwitch()
    private let hint = UILabel()

    private var current: AyuGramCustomBadge
    private let changed: (AyuGramCustomBadge) -> Void

    init(theme: PresentationTheme, locale: String, name: String, badge: AyuGramCustomBadge, changed: @escaping (AyuGramCustomBadge) -> Void) {
        self.theme = theme
        self.locale = locale
        self.current = badge
        self.changed = changed
        super.init(frame: CGRect())

        self.scroll.alwaysBounceVertical = true
        self.addSubview(self.scroll)

        self.previewBack.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.previewBack.layer.cornerRadius = 22.0
        self.previewBack.layer.cornerCurve = .continuous
        self.scroll.addSubview(self.previewBack)
        self.preview.contentMode = .scaleAspectFit
        self.previewBack.addSubview(self.preview)
        self.sampleName.text = name
        self.sampleName.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        self.sampleName.textColor = theme.list.itemPrimaryTextColor
        self.previewBack.addSubview(self.sampleName)
        self.previewBack.addSubview(self.sampleBadge)


        for (index, key) in ["Ayu.BadgeSquircle", "Ayu.BadgeCircle", "Ayu.BadgeSeal", "Ayu.BadgeNoBackground"].enumerated() {
            self.shapeControl.insertSegment(withTitle: i18n(key, locale), at: index, animated: false)
        }
        self.shapeControl.addTarget(self, action: #selector(self.shapeChanged), for: .valueChanged)
        self.scroll.addSubview(self.shapeControl)

        for label in [self.iconsTitle, self.colorsTitle] {
            label.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
            label.textColor = theme.list.sectionHeaderTextColor
            self.scroll.addSubview(label)
        }
        self.iconsTitle.text = i18n("Ayu.BadgeIcon", locale).uppercased()
        self.colorsTitle.text = i18n("Ayu.BadgeColor", locale).uppercased()

        for (index, symbol) in ayuGramBadgeSymbols.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18.0, weight: .semibold)), for: .normal)
            button.tintColor = theme.list.itemPrimaryTextColor
            button.backgroundColor = theme.list.itemBlocksBackgroundColor
            button.layer.cornerRadius = 12.0
            button.layer.cornerCurve = .continuous
            button.addTarget(self, action: #selector(self.iconPressed(_:)), for: .touchUpInside)
            self.iconButtons.append(button)
            self.scroll.addSubview(button)
        }
        self.emojiField.placeholder = i18n("Ayu.BadgeEmoji", locale)
        self.emojiField.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.emojiField.textColor = theme.list.itemPrimaryTextColor
        self.emojiField.layer.cornerRadius = 12.0
        self.emojiField.layer.cornerCurve = .continuous
        self.emojiField.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.emojiField.leftViewMode = .always
        self.emojiField.returnKeyType = .done
        self.emojiField.delegate = self
        self.emojiField.keyboardAppearance = theme.overallDarkAppearance ? .dark : .light
        self.emojiField.addTarget(self, action: #selector(self.emojiChanged), for: .editingChanged)
        self.scroll.addSubview(self.emojiField)

        for (index, palette) in ayuGramBadgePalettes.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            var badge = AyuGramCustomBadge()
            badge.shape = 1
            badge.symbol = ""
            badge.top = palette.0
            badge.bottom = palette.1
            button.setImage(ayuGramCustomBadgeImage(badge, size: 36.0), for: .normal)
            button.layer.cornerRadius = 20.0
            button.layer.borderWidth = 2.0
            button.addTarget(self, action: #selector(self.colorPressed(_:)), for: .touchUpInside)
            self.colorButtons.append(button)
            self.scroll.addSubview(button)
        }

        self.darkLabel.text = i18n("Ayu.BadgeDarkIcon", locale)
        self.darkLabel.textColor = theme.list.itemPrimaryTextColor
        self.darkSwitch.onTintColor = theme.list.itemAccentColor
        self.darkSwitch.addTarget(self, action: #selector(self.darkChanged), for: .valueChanged)
        self.scroll.addSubview(self.darkLabel)
        self.scroll.addSubview(self.darkSwitch)

        self.hint.text = i18n("Ayu.BadgeHint", locale)
        self.hint.font = UIFont.systemFont(ofSize: 13.0)
        self.hint.textColor = theme.list.freeTextColor
        self.hint.numberOfLines = 0
        self.scroll.addSubview(self.hint)

        self.refresh(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var badge: AyuGramCustomBadge {
        return self.current
    }

    private func change(_ f: (inout AyuGramCustomBadge) -> Void) {
        f(&self.current)
        self.current.enabled = true
        UISelectionFeedbackGenerator().selectionChanged()
        self.refresh(animated: true)
        self.changed(self.current)
    }

    private func refresh(animated: Bool) {
        let badge = self.badge
        var shown = badge
        shown.enabled = true
        self.preview.image = ayuGramCustomBadgeImage(shown, size: 96.0)
        self.sampleBadge.image = ayuGramCustomBadgeImage(shown, size: 22.0)
        if animated {
            self.preview.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                self.preview.transform = .identity
            })
        }
        self.shapeControl.selectedSegmentIndex = Int(max(0, min(3, badge.shape)))
        self.darkSwitch.isOn = badge.darkGlyph
        for (index, button) in self.iconButtons.enumerated() {
            let selected = badge.emoji.isEmpty && ayuGramBadgeSymbols[index] == badge.symbol
            button.backgroundColor = selected ? self.theme.list.itemAccentColor.withAlphaComponent(0.2) : self.theme.list.itemBlocksBackgroundColor
            button.tintColor = selected ? self.theme.list.itemAccentColor : self.theme.list.itemPrimaryTextColor
        }
        if !self.emojiField.isFirstResponder {
            self.emojiField.text = badge.emoji
        }
        for (index, button) in self.colorButtons.enumerated() {
            let palette = ayuGramBadgePalettes[index]
            let selected = palette.0 == badge.top && palette.1 == badge.bottom
            button.layer.borderColor = selected ? self.theme.list.itemAccentColor.cgColor : UIColor.clear.cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.bounds.width
        let side: CGFloat = 16.0
        let inner = width - side * 2.0
        self.scroll.frame = self.bounds
        var y: CGFloat = 16.0
        self.previewBack.frame = CGRect(x: side, y: y, width: inner, height: 170.0)
        self.preview.frame = CGRect(x: (inner - 96.0) / 2.0, y: 18.0, width: 96.0, height: 96.0)
        let nameSize = self.sampleName.sizeThatFits(CGSize(width: inner - 60.0, height: 24.0))
        let nameWidth = min(nameSize.width, inner - 60.0)
        let nameX = (inner - nameWidth - 26.0) / 2.0
        self.sampleName.frame = CGRect(x: nameX, y: 128.0, width: nameWidth, height: 24.0)
        self.sampleBadge.frame = CGRect(x: nameX + nameWidth + 4.0, y: 129.0, width: 22.0, height: 22.0)
        y += 170.0 + 16.0
        self.shapeControl.frame = CGRect(x: side, y: y, width: inner, height: 34.0)
        y += 34.0 + 22.0
        self.iconsTitle.frame = CGRect(x: side + 4.0, y: y, width: inner, height: 16.0)
        y += 24.0
        let columns = 6
        let spacing: CGFloat = 8.0
        let cell = floor((inner - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        for (index, button) in self.iconButtons.enumerated() {
            let column = index % columns
            let row = index / columns
            button.frame = CGRect(x: side + CGFloat(column) * (cell + spacing), y: y + CGFloat(row) * (cell + spacing), width: cell, height: cell)
        }
        let rows = (self.iconButtons.count + columns - 1) / columns
        y += CGFloat(rows) * (cell + spacing) + 2.0
        self.emojiField.frame = CGRect(x: side, y: y, width: inner, height: 44.0)
        y += 44.0 + 22.0
        self.colorsTitle.frame = CGRect(x: side + 4.0, y: y, width: inner, height: 16.0)
        y += 24.0
        let colorColumns = 6
        let colorCell: CGFloat = 40.0
        let colorSpacing = floor((inner - colorCell * CGFloat(colorColumns)) / CGFloat(colorColumns - 1))
        for (index, button) in self.colorButtons.enumerated() {
            let column = index % colorColumns
            let row = index / colorColumns
            button.frame = CGRect(x: side + CGFloat(column) * (colorCell + colorSpacing), y: y + CGFloat(row) * (colorCell + 10.0), width: colorCell, height: colorCell)
        }
        let colorRows = (self.colorButtons.count + colorColumns - 1) / colorColumns
        y += CGFloat(colorRows) * (colorCell + 10.0) + 8.0
        let darkSize = self.darkSwitch.sizeThatFits(.zero)
        self.darkSwitch.frame = CGRect(x: width - side - darkSize.width, y: y, width: darkSize.width, height: darkSize.height)
        self.darkLabel.frame = CGRect(x: side, y: y, width: inner - darkSize.width - 8.0, height: darkSize.height)
        y += darkSize.height + 14.0
        let hintHeight = ceil(self.hint.sizeThatFits(CGSize(width: inner - 8.0, height: .greatestFiniteMagnitude)).height)
        self.hint.frame = CGRect(x: side + 4.0, y: y, width: inner - 8.0, height: hintHeight)
        y += hintHeight + 30.0
        self.scroll.contentSize = CGSize(width: width, height: y)
    }

    @objc private func shapeChanged() {
        let value = Int32(self.shapeControl.selectedSegmentIndex)
        self.change { $0.shape = value }
    }

    @objc private func iconPressed(_ sender: UIButton) {
        let symbol = ayuGramBadgeSymbols[sender.tag]
        self.emojiField.text = ""
        self.emojiField.resignFirstResponder()
        self.change { badge in
            badge.symbol = symbol
            badge.emoji = ""
            badge.enabled = true
        }
    }

    @objc private func emojiChanged() {
        let text = String((self.emojiField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        self.change { badge in
            badge.emoji = text
            if !text.isEmpty {
                badge.enabled = true
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    @objc private func colorPressed(_ sender: UIButton) {
        let palette = ayuGramBadgePalettes[sender.tag]
        self.change { badge in
            badge.top = palette.0
            badge.bottom = palette.1
            badge.enabled = true
        }
    }

    @objc private func darkChanged() {
        let value = self.darkSwitch.isOn
        self.change { $0.darkGlyph = value }
    }
}

private final class AyuGramSupporterView: UIView {
    private let context: AccountContext
    private let theme: PresentationTheme
    private let locale: String
    private let accountId: Int64
    private var name = ""

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let codeLabel = UILabel()
    private let payButton = UIButton(type: .system)
    private let paidButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private var editor: AyuGramBadgeView?
    private var state: AyuGramSupporterState = .unknown
    private var saveTimer: Foundation.Timer?
    private var pendingBadge: AyuGramCustomBadge?

    init(context: AccountContext, theme: PresentationTheme, locale: String) {
        self.context = context
        self.theme = theme
        self.locale = locale
        self.accountId = context.account.peerId.id._internalGetInt64Value()
        super.init(frame: CGRect())

        self.spinner.color = theme.list.itemAccentColor
        self.spinner.startAnimating()
        self.addSubview(self.spinner)

        var sample = AyuGramCustomBadge()
        sample.symbol = "heart.fill"
        sample.shape = 2
        sample.top = "FF4D6D"
        sample.bottom = "FF9EAE"
        self.icon.image = ayuGramCustomBadgeImage(sample, size: 84.0)
        self.icon.contentMode = .scaleAspectFit
        self.titleLabel.font = UIFont.systemFont(ofSize: 22.0, weight: .bold)
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.titleLabel.textAlignment = .center
        self.titleLabel.text = i18n("Ayu.SupporterBadge", locale)
        self.textLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.textLabel.textColor = theme.list.itemSecondaryTextColor
        self.textLabel.textAlignment = .center
        self.textLabel.numberOfLines = 0
        self.codeLabel.font = UIFont.monospacedSystemFont(ofSize: 30.0, weight: .bold)
        self.codeLabel.textColor = theme.list.itemAccentColor
        self.codeLabel.textAlignment = .center
        self.codeLabel.isUserInteractionEnabled = true
        self.codeLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.codeTapped)))
        self.statusLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.statusLabel.textColor = theme.list.itemSecondaryTextColor
        self.statusLabel.textAlignment = .center
        self.statusLabel.numberOfLines = 0
        for button in [self.payButton, self.paidButton] {
            button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
            button.layer.cornerRadius = 14.0
            button.layer.cornerCurve = .continuous
        }
        self.payButton.backgroundColor = theme.list.itemCheckColors.fillColor
        self.payButton.setTitleColor(theme.list.itemCheckColors.foregroundColor, for: .normal)
        self.payButton.addTarget(self, action: #selector(self.payPressed), for: .touchUpInside)
        self.paidButton.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.paidButton.setTitleColor(theme.list.itemAccentColor, for: .normal)
        self.paidButton.addTarget(self, action: #selector(self.paidPressed), for: .touchUpInside)
        for view in [self.icon, self.titleLabel, self.textLabel, self.codeLabel, self.payButton, self.paidButton, self.statusLabel] as [UIView] {
            view.isHidden = true
            self.addSubview(view)
        }

        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
        |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
            guard let self else {
                return
            }
            if case let .user(user) = peer {
                self.name = [user.firstName ?? "", user.lastName ?? ""].filter({ !$0.isEmpty }).joined(separator: " ")
            }
            self.check()
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.saveTimer?.invalidate()
    }

    private func check() {
        AyuGramBadgeSync.shared.supporterStatus(accountId: self.accountId, completion: { [weak self] state in
            self?.apply(state)
        })
    }

    private func apply(_ state: AyuGramSupporterState) {
        self.state = state
        self.spinner.stopAnimating()
        self.spinner.isHidden = true
        let price = AyuGramBadgeSync.shared.price
        var showsIntro = true
        self.codeLabel.isHidden = true
        self.statusLabel.text = nil
        switch state {
        case .unknown:
            showsIntro = false
        case .none:
            self.textLabel.text = i18n("Ayu.SupporterInfo", self.locale, price)
            self.payButton.setTitle(i18n("Ayu.SupporterPay", self.locale, price), for: .normal)
            self.paidButton.setTitle(i18n("Ayu.SupporterPaid", self.locale), for: .normal)
        case let .pending(code):
            self.textLabel.text = i18n("Ayu.SupporterPending", self.locale, price)
            self.codeLabel.text = code
            self.codeLabel.isHidden = false
            self.payButton.setTitle(i18n("Ayu.SupporterPay", self.locale, price), for: .normal)
            self.paidButton.setTitle(i18n("Ayu.SupporterCheck", self.locale), for: .normal)
        case .failed:
            self.textLabel.text = i18n("Ayu.SupporterFailed", self.locale)
            self.payButton.setTitle(i18n("Ayu.SupporterPay", self.locale, price), for: .normal)
            self.paidButton.setTitle(i18n("Ayu.SupporterCheck", self.locale), for: .normal)
        case let .granted(badge):
            showsIntro = false
            if self.editor == nil {
                let editor = AyuGramBadgeView(theme: self.theme, locale: self.locale, name: self.name.isEmpty ? "AyuGram" : self.name, badge: badge, changed: { [weak self] updated in
                    self?.schedule(updated)
                })
                self.editor = editor
                self.addSubview(editor)
                AyuGramClientBadges.shared.setSupporter(self.accountId, badge: badge)
            }
        }
        for view in [self.icon, self.titleLabel, self.textLabel, self.payButton, self.paidButton, self.statusLabel] as [UIView] {
            view.isHidden = !showsIntro
        }
        self.setNeedsLayout()
    }

    private func schedule(_ badge: AyuGramCustomBadge) {
        self.pendingBadge = badge
        AyuGramClientBadges.shared.setSupporter(self.accountId, badge: badge)
        self.saveTimer?.invalidate()
        self.saveTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false, block: { [weak self] _ in
            guard let self, let badge = self.pendingBadge else {
                return
            }
            self.pendingBadge = nil
            AyuGramBadgeSync.shared.setSupporterBadge(accountId: self.accountId, badge: badge, completion: { _ in })
        })
    }

    @objc private func codeTapped() {
        UIPasteboard.general.string = self.codeLabel.text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        self.statusLabel.text = i18n("Ayu.SupporterCopied", self.locale)
        self.setNeedsLayout()
    }

    var push: ((ViewController) -> Void)?

    @objc private func payPressed() {
        var intro = i18n("Ayu.SupporterPayIntro", self.locale, AyuGramBadgeSync.shared.price)
        if case let .pending(code) = self.state {
            intro += "\n\n" + i18n("Ayu.SupporterPayCode", self.locale, code)
        }
        self.push?(ayuGramBadgePaymentController(context: self.context, intro: intro))
    }

    @objc private func paidPressed() {
        self.paidButton.isEnabled = false
        let finish: (AyuGramSupporterState) -> Void = { [weak self] state in
            guard let self else {
                return
            }
            self.paidButton.isEnabled = true
            self.apply(state)
            if case .pending = state {
                self.statusLabel.text = i18n("Ayu.SupporterWaiting", self.locale)
                self.setNeedsLayout()
            }
        }
        if case .pending = self.state {
            AyuGramBadgeSync.shared.supporterStatus(accountId: self.accountId, completion: finish)
        } else {
            AyuGramBadgeSync.shared.requestSupporter(accountId: self.accountId, name: self.name, completion: finish)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.bounds.width
        let side: CGFloat = 24.0
        let inner = width - side * 2.0
        self.spinner.center = CGPoint(x: width / 2.0, y: self.bounds.height / 2.0)
        self.editor?.frame = self.bounds
        var y: CGFloat = 28.0
        self.icon.frame = CGRect(x: (width - 84.0) / 2.0, y: y, width: 84.0, height: 84.0)
        y += 84.0 + 14.0
        self.titleLabel.frame = CGRect(x: side, y: y, width: inner, height: 28.0)
        y += 28.0 + 8.0
        let textHeight = ceil(self.textLabel.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height)
        self.textLabel.frame = CGRect(x: side, y: y, width: inner, height: textHeight)
        y += textHeight + 18.0
        if !self.codeLabel.isHidden {
            self.codeLabel.frame = CGRect(x: side, y: y, width: inner, height: 40.0)
            y += 40.0 + 18.0
        }
        self.payButton.frame = CGRect(x: side, y: y, width: inner, height: 50.0)
        y += 50.0 + 10.0
        self.paidButton.frame = CGRect(x: side, y: y, width: inner, height: 50.0)
        y += 50.0 + 12.0
        let statusHeight = ceil(self.statusLabel.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height)
        self.statusLabel.frame = CGRect(x: side, y: y, width: inner, height: statusHeight)
    }
}

public func ayuGramSupporterController(context: AccountContext) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    AyuGramBadgeSync.shared.start()
    let view = AyuGramSupporterView(context: context, theme: presentationData.theme, locale: locale)
    let controller = AyuGramHostController(context: context, title: i18n("Ayu.SupporterBadge", locale), content: view)
    view.push = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}
