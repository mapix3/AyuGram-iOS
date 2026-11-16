import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import SGStrings

private final class AyuGramFloatingWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self || result === self.rootViewController?.view {
            return nil
        }
        return result
    }
}

private final class AyuGramFloatingRoot: UIViewController {
    override func loadView() {
        let view = UIView()
        view.backgroundColor = .clear
        self.view = view
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .default
    }
}

private struct AyuGramFloatingMessage {
    let id: EngineMessage.Id
    let outgoing: Bool
    let author: String
    let text: String
}

private final class AyuGramFloatingCell: UITableViewCell {
    private let bubble = UIView()
    private let name = UILabel()
    private let label = UILabel()
    private var outgoing = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.backgroundColor = .clear
        self.selectionStyle = .none
        self.bubble.layer.cornerRadius = 14.0
        self.bubble.layer.cornerCurve = .continuous
        self.name.font = UIFont.systemFont(ofSize: 11.0, weight: .semibold)
        self.label.font = UIFont.systemFont(ofSize: 14.0)
        self.label.numberOfLines = 0
        self.contentView.addSubview(self.bubble)
        self.bubble.addSubview(self.name)
        self.bubble.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func height(message: AyuGramFloatingMessage, width: CGFloat, showName: Bool) -> CGFloat {
        let maxWidth = floor(width * 0.8) - 20.0
        let text = (message.text as NSString).boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: UIFont.systemFont(ofSize: 14.0)], context: nil)
        return ceil(text.height) + 14.0 + (showName ? 15.0 : 0.0) + 4.0
    }

    func update(message: AyuGramFloatingMessage, showName: Bool, theme: PresentationTheme) {
        self.outgoing = message.outgoing
        self.label.text = message.text
        self.name.text = showName ? message.author : nil
        self.name.isHidden = !showName
        if message.outgoing {
            self.bubble.backgroundColor = theme.list.itemCheckColors.fillColor
            self.label.textColor = theme.list.itemCheckColors.foregroundColor
        } else {
            self.bubble.backgroundColor = theme.list.itemPrimaryTextColor.withAlphaComponent(theme.overallDarkAppearance ? 0.12 : 0.07)
            self.label.textColor = theme.list.itemPrimaryTextColor
        }
        self.name.textColor = theme.list.itemAccentColor
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let width = self.contentView.bounds.width
        let maxWidth = floor(width * 0.8) - 20.0
        let textSize = self.label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        var nameHeight: CGFloat = 0.0
        var bubbleWidth = ceil(textSize.width) + 20.0
        if !self.name.isHidden {
            nameHeight = 15.0
            bubbleWidth = max(bubbleWidth, min(maxWidth + 20.0, ceil(self.name.sizeThatFits(CGSize(width: maxWidth, height: 15.0)).width) + 20.0))
        }
        let bubbleHeight = ceil(textSize.height) + 14.0 + nameHeight
        let x = self.outgoing ? width - 8.0 - bubbleWidth : 8.0
        self.bubble.frame = CGRect(x: x, y: 2.0, width: bubbleWidth, height: bubbleHeight)
        self.name.frame = CGRect(x: 10.0, y: 6.0, width: bubbleWidth - 20.0, height: 14.0)
        self.label.frame = CGRect(x: 10.0, y: 7.0 + nameHeight, width: bubbleWidth - 20.0, height: ceil(textSize.height))
    }
}

private final class AyuGramFloatingPanel: UIView, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private let context: AccountContext
    let peerId: EnginePeer.Id
    private let isGroup: Bool
    private var theme: PresentationTheme
    private let locale: String
    private let close: () -> Void
    private let open: () -> Void

    private let card = UIView()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let header = UIView()
    private let titleLabel = UILabel()
    private let statusDot = UIView()
    private let minimizeButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let tableView = UITableView(frame: CGRect(), style: .plain)
    private let field = UITextField()
    private let fieldBackground = UIView()
    private let sendButton = UIButton(type: .system)
    private let bubble = UIControl()
    private let bubbleBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let bubbleLabel = UILabel()
    private let badge = UIView()

    private var messages: [AyuGramFloatingMessage] = []
    private let disposable = MetaDisposable()
    private var minimized = false
    private var lastSeenId: EngineMessage.Id?
    private var keyboardHeight: CGFloat = 0.0
    private(set) var cardSize = CGSize(width: 290.0, height: 380.0)
    let bubbleSize: CGFloat = 58.0

    init(context: AccountContext, peerId: EnginePeer.Id, title: String, isGroup: Bool, theme: PresentationTheme, locale: String, close: @escaping () -> Void, open: @escaping () -> Void) {
        self.context = context
        self.peerId = peerId
        self.isGroup = isGroup
        self.theme = theme
        self.locale = locale
        self.close = close
        self.open = open
        super.init(frame: CGRect())

        self.card.layer.shadowColor = UIColor.black.cgColor
        self.card.layer.shadowOpacity = 0.3
        self.card.layer.shadowRadius = 20.0
        self.card.layer.shadowOffset = CGSize(width: 0.0, height: 8.0)
        self.blur.clipsToBounds = true
        self.blur.layer.cornerRadius = 22.0
        self.blur.layer.cornerCurve = .continuous
        self.card.addSubview(self.blur)
        self.addSubview(self.card)

        self.titleLabel.text = title
        self.titleLabel.font = UIFont.systemFont(ofSize: 15.0, weight: .semibold)
        self.statusDot.layer.cornerRadius = 4.0
        self.minimizeButton.setImage(UIImage(systemName: "minus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.0, weight: .bold)), for: .normal)
        self.minimizeButton.addTarget(self, action: #selector(self.minimizePressed), for: .touchUpInside)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.0, weight: .bold)), for: .normal)
        self.closeButton.addTarget(self, action: #selector(self.closePressed), for: .touchUpInside)
        self.header.addSubview(self.statusDot)
        self.header.addSubview(self.titleLabel)
        self.header.addSubview(self.minimizeButton)
        self.header.addSubview(self.closeButton)
        let openTap = UITapGestureRecognizer(target: self, action: #selector(self.openPressed))
        openTap.numberOfTapsRequired = 2
        self.header.addGestureRecognizer(openTap)
        self.blur.contentView.addSubview(self.header)

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.separatorStyle = .none
        self.tableView.backgroundColor = .clear
        self.tableView.keyboardDismissMode = .interactive
        self.tableView.contentInset = UIEdgeInsets(top: 4.0, left: 0.0, bottom: 4.0, right: 0.0)
        self.tableView.register(AyuGramFloatingCell.self, forCellReuseIdentifier: "m")
        self.blur.contentView.addSubview(self.tableView)

        self.fieldBackground.layer.cornerRadius = 17.0
        self.fieldBackground.layer.cornerCurve = .continuous
        self.blur.contentView.addSubview(self.fieldBackground)
        self.field.font = UIFont.systemFont(ofSize: 15.0)
        self.field.returnKeyType = .send
        self.field.delegate = self
        self.blur.contentView.addSubview(self.field)
        self.sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26.0)), for: .normal)
        self.sendButton.addTarget(self, action: #selector(self.sendPressed), for: .touchUpInside)
        self.blur.contentView.addSubview(self.sendButton)

        self.bubble.isHidden = true
        self.bubbleBlur.isUserInteractionEnabled = false
        self.bubbleBlur.clipsToBounds = true
        self.bubbleBlur.layer.cornerRadius = self.bubbleSize / 2.0
        self.bubble.addSubview(self.bubbleBlur)
        self.bubbleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .bold)
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
        self.addSubview(self.bubble)

        for view in [self.header, self.bubble] {
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.dragged(_:))))
        }

        self.applyTheme()
        self.layoutCard()
        self.subscribe()

        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable.dispose()
        NotificationCenter.default.removeObserver(self)
    }

    private func applyTheme() {
        let theme = self.theme
        let dark = theme.overallDarkAppearance
        self.blur.effect = UIBlurEffect(style: dark ? .systemThickMaterialDark : .systemThickMaterialLight)
        self.bubbleBlur.effect = UIBlurEffect(style: dark ? .systemThickMaterialDark : .systemThickMaterialLight)
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.statusDot.backgroundColor = theme.list.itemAccentColor
        self.minimizeButton.tintColor = theme.list.itemSecondaryTextColor
        self.closeButton.tintColor = theme.list.itemSecondaryTextColor
        self.fieldBackground.backgroundColor = theme.list.itemPrimaryTextColor.withAlphaComponent(dark ? 0.1 : 0.06)
        self.field.textColor = theme.list.itemPrimaryTextColor
        self.field.tintColor = theme.list.itemAccentColor
        self.field.keyboardAppearance = dark ? .dark : .light
        self.field.attributedPlaceholder = NSAttributedString(string: i18n("Ayu.FloatPlaceholder", self.locale), attributes: [.foregroundColor: theme.list.itemPlaceholderTextColor])
        self.sendButton.tintColor = theme.list.itemAccentColor
        self.bubbleLabel.textColor = theme.list.itemAccentColor
        self.badge.backgroundColor = theme.list.itemDestructiveColor
    }

    private func layoutCard() {
        let size = self.cardSize
        self.card.bounds = CGRect(origin: CGPoint(), size: size)
        self.blur.frame = self.card.bounds
        self.card.layer.shadowPath = UIBezierPath(roundedRect: self.card.bounds, cornerRadius: 22.0).cgPath
        self.header.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: 44.0)
        self.statusDot.frame = CGRect(x: 16.0, y: 18.0, width: 8.0, height: 8.0)
        self.closeButton.frame = CGRect(x: size.width - 40.0, y: 7.0, width: 30.0, height: 30.0)
        self.minimizeButton.frame = CGRect(x: size.width - 72.0, y: 7.0, width: 30.0, height: 30.0)
        self.titleLabel.frame = CGRect(x: 32.0, y: 12.0, width: size.width - 32.0 - 78.0, height: 20.0)
        let inputY = size.height - 10.0 - 34.0
        self.tableView.frame = CGRect(x: 0.0, y: 44.0, width: size.width, height: inputY - 6.0 - 44.0)
        self.fieldBackground.frame = CGRect(x: 10.0, y: inputY, width: size.width - 20.0, height: 34.0)
        self.field.frame = CGRect(x: 22.0, y: inputY, width: size.width - 22.0 - 46.0, height: 34.0)
        self.sendButton.frame = CGRect(x: size.width - 44.0, y: inputY, width: 34.0, height: 34.0)
        self.bubble.bounds = CGRect(x: 0.0, y: 0.0, width: self.bubbleSize, height: self.bubbleSize)
        self.bubbleBlur.frame = self.bubble.bounds
        self.bubbleLabel.frame = self.bubble.bounds
        self.badge.frame = CGRect(x: self.bubbleSize - 14.0, y: 0.0, width: 14.0, height: 14.0)
        self.bubble.layer.shadowPath = UIBezierPath(ovalIn: self.bubble.bounds).cgPath
    }

    func place(center: CGPoint) {
        self.card.center = center
        self.bubble.center = CGPoint(x: center.x + self.cardSize.width / 2.0 - self.bubbleSize / 2.0, y: center.y - self.cardSize.height / 2.0 + self.bubbleSize / 2.0)
    }

    func appear() {
        self.card.alpha = 0.0
        self.card.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
            self.card.alpha = 1.0
            self.card.transform = .identity
        })
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let target = self.minimized ? self.bubble : self.card
        guard !target.isHidden, target.frame.contains(point) else {
            return nil
        }
        return super.hitTest(point, with: event)
    }

    private func subscribe() {
        let accountPeerId = self.context.account.peerId
        let isGroup = self.isGroup
        self.disposable.set((self.context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: self.peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 40, fixedCombinedReadStates: nil)
        |> map { view, _, _ -> [AyuGramFloatingMessage] in
            var result: [AyuGramFloatingMessage] = []
            for entry in view.entries {
                let message = EngineMessage(entry.message)
                guard let tag = ayuGramCopilotMediaTag(message) else {
                    continue
                }
                let text = [tag, message.text].filter({ !$0.isEmpty }).joined(separator: " ")
                if text.isEmpty {
                    continue
                }
                let outgoing = !message.flags.contains(.Incoming) || message.author?.id == accountPeerId
                var author = ""
                if isGroup, !outgoing, let peer = message.author {
                    if case let .user(user) = peer {
                        author = user.firstName ?? user.lastName ?? ""
                    } else {
                        author = peer.debugDisplayTitle
                    }
                }
                result.append(AyuGramFloatingMessage(id: message.id, outgoing: outgoing, author: author, text: text))
            }
            return result
        }
        |> deliverOnMainQueue).startStrict(next: { [weak self] messages in
            guard let self else {
                return
            }
            let previousLast = self.messages.last?.id
            let atBottom = self.tableView.contentOffset.y + self.tableView.bounds.height >= self.tableView.contentSize.height - 40.0
            self.messages = messages
            self.tableView.reloadData()
            if let last = messages.last, last.id != previousLast {
                if previousLast == nil || atBottom || last.outgoing {
                    self.scrollToBottom(animated: previousLast != nil)
                }
                if self.minimized && !last.outgoing && last.id != self.lastSeenId {
                    self.showBadge()
                }
            }
        }))
    }

    private func scrollToBottom(animated: Bool) {
        let count = self.messages.count
        guard count > 0 else {
            return
        }
        self.tableView.layoutIfNeeded()
        self.tableView.scrollToRow(at: IndexPath(row: count - 1, section: 0), at: .bottom, animated: animated)
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

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.messages.count
    }

    private func showsName(_ index: Int) -> Bool {
        let message = self.messages[index]
        guard self.isGroup, !message.outgoing, !message.author.isEmpty else {
            return false
        }
        return index == 0 || self.messages[index - 1].author != message.author || self.messages[index - 1].outgoing
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return AyuGramFloatingCell.height(message: self.messages[indexPath.row], width: tableView.bounds.width, showName: self.showsName(indexPath.row))
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "m", for: indexPath)
        if let cell = cell as? AyuGramFloatingCell {
            cell.update(message: self.messages[indexPath.row], showName: self.showsName(indexPath.row), theme: self.theme)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let text = self.messages[indexPath.row].text
        let title = i18n("Ayu.AICopy", self.locale)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            return UIMenu(title: "", children: [UIAction(title: title, image: UIImage(systemName: "doc.on.doc"), handler: { _ in
                UIPasteboard.general.string = text
            })])
        })
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.sendPressed()
        return false
    }

    @objc private func sendPressed() {
        let text = (self.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        self.field.text = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let _ = enqueueMessages(account: self.context.account, peerId: self.peerId, messages: [.message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])]).startStandalone()
    }

    @objc private func minimizePressed() {
        self.field.resignFirstResponder()
        self.minimized = true
        self.lastSeenId = self.messages.last?.id
        self.bubble.isHidden = false
        self.bubble.alpha = 0.0
        self.bubble.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [], animations: {
            self.card.alpha = 0.0
            self.card.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            self.bubble.alpha = 1.0
            self.bubble.transform = .identity
        }, completion: { _ in
            if self.minimized {
                self.card.isHidden = true
            }
        })
    }

    @objc private func restorePressed() {
        self.minimized = false
        self.badge.isHidden = true
        self.card.isHidden = false
        self.clampCard()
        UIView.animate(withDuration: 0.45, delay: 0.0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.0, options: [], animations: {
            self.card.alpha = 1.0
            self.card.transform = .identity
            self.bubble.alpha = 0.0
            self.bubble.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        }, completion: { _ in
            if !self.minimized {
                self.bubble.isHidden = true
            }
        })
        self.scrollToBottom(animated: false)
    }

    @objc private func closePressed() {
        self.field.resignFirstResponder()
        UIView.animate(withDuration: 0.25, animations: {
            self.alpha = 0.0
            self.card.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }, completion: { _ in
            self.close()
        })
    }

    @objc private func openPressed() {
        self.minimizePressed()
        self.open()
    }

    @objc private func dragged(_ recognizer: UIPanGestureRecognizer) {
        let moving: UIView = self.minimized ? self.bubble : self.card
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(CGPoint(), in: self)
        moving.center = CGPoint(x: moving.center.x + translation.x, y: moving.center.y + translation.y)
        if recognizer.state == .ended || recognizer.state == .cancelled {
            if self.minimized {
                let margin = self.bubbleSize / 2.0 + 8.0
                let left = moving.center.x < self.bounds.width / 2.0
                let insets = self.safeAreaInsets
                let x = left ? insets.left + margin : self.bounds.width - insets.right - margin
                let y = min(max(moving.center.y, insets.top + margin), self.bounds.height - insets.bottom - margin)
                UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.0, options: [], animations: {
                    moving.center = CGPoint(x: x, y: y)
                })
            } else {
                UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: [], animations: {
                    self.clampCard()
                })
            }
        }
    }

    private func clampCard() {
        let insets = self.safeAreaInsets
        let half = CGSize(width: self.cardSize.width / 2.0, height: self.cardSize.height / 2.0)
        let bottom = self.bounds.height - max(insets.bottom, self.keyboardHeight) - 8.0
        var center = self.card.center
        center.x = min(max(center.x, insets.left + half.width + 8.0), self.bounds.width - insets.right - half.width - 8.0)
        center.y = min(max(center.y, insets.top + half.height + 8.0), max(insets.top + half.height + 8.0, bottom - half.height))
        self.card.center = center
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let frame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            return
        }
        let height = max(0.0, self.bounds.height - frame.minY)
        self.keyboardHeight = height
        guard self.field.isFirstResponder || height == 0.0 else {
            return
        }
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration, animations: {
            self.clampCard()
        })
    }
}

private var ayuGramFloatingWindow: AyuGramFloatingWindow?
private var ayuGramFloatingPanels: [AyuGramFloatingPanel] = []

public func ayuGramOpenFloatingChat(context: AccountContext, peerId: EnginePeer.Id, title: String, isGroup: Bool, openChat: @escaping () -> Void) {
    if let existing = ayuGramFloatingPanels.first(where: { $0.peerId == peerId }) {
        existing.superview?.bringSubviewToFront(existing)
        return
    }
    let window: AyuGramFloatingWindow
    if let current = ayuGramFloatingWindow {
        window = current
    } else {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        window = AyuGramFloatingWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 5.0)
        window.backgroundColor = .clear
        window.rootViewController = AyuGramFloatingRoot()
        window.isHidden = false
        ayuGramFloatingWindow = window
    }
    guard let root = window.rootViewController?.view else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    var panelRef: AyuGramFloatingPanel?
    let panel = AyuGramFloatingPanel(context: context, peerId: peerId, title: title, isGroup: isGroup, theme: presentationData.theme, locale: presentationData.strings.baseLanguageCode, close: {
        guard let panel = panelRef else {
            return
        }
        panel.removeFromSuperview()
        ayuGramFloatingPanels.removeAll(where: { $0 === panel })
        panelRef = nil
        if ayuGramFloatingPanels.isEmpty {
            ayuGramFloatingWindow?.isHidden = true
            ayuGramFloatingWindow = nil
        }
    }, open: openChat)
    panelRef = panel
    panel.frame = root.bounds
    panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    root.addSubview(panel)
    ayuGramFloatingPanels.append(panel)
    let offset = CGFloat(ayuGramFloatingPanels.count - 1) * 24.0
    let insets = window.safeAreaInsets
    panel.place(center: CGPoint(x: root.bounds.width - insets.right - panel.cardSize.width / 2.0 - 12.0 - offset, y: insets.top + 70.0 + panel.cardSize.height / 2.0 + offset))
    panel.appear()
}
