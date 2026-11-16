import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import SGSimpleSettings
import SGStrings

private struct AyuGramCopilotResult {
    let lastId: EngineMessage.Id
    let summary: String
    let replies: [String]
}

private var ayuGramCopilotCache: [EnginePeer.Id: AyuGramCopilotResult] = [:]

private let ayuGramCopilotBudget = 2000
private let ayuGramCopilotLineLimit = 220

private func ayuGramCopilotLine(_ text: String) -> String {
    let flat = text.components(separatedBy: .whitespacesAndNewlines).filter({ !$0.isEmpty }).joined(separator: " ")
    if flat.count > ayuGramCopilotLineLimit {
        return String(flat.prefix(ayuGramCopilotLineLimit)) + "…"
    }
    return flat
}

private func ayuGramCopilotMediaTag(_ message: EngineMessage) -> String? {
    for media in message.media {
        if media is TelegramMediaAction {
            return nil
        }
        if media is TelegramMediaImage {
            return "[фото]"
        }
        if let file = media as? TelegramMediaFile {
            if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                for attribute in file.attributes {
                    if case let .Sticker(displayText, _, _) = attribute, !displayText.isEmpty {
                        return "[стикер \(displayText)]"
                    }
                }
                return "[стикер]"
            }
            if file.isVoice {
                return "[голосовое]"
            }
            if file.isInstantVideo {
                return "[кружок]"
            }
            if file.isAnimated {
                return "[gif]"
            }
            if file.isVideo {
                return "[видео]"
            }
            if file.isMusic {
                return "[музыка]"
            }
            return "[файл]"
        }
        if media is TelegramMediaPoll {
            return "[опрос]"
        }
        if media is TelegramMediaMap {
            return "[геопозиция]"
        }
        if media is TelegramMediaContact {
            return "[контакт]"
        }
        if media is TelegramMediaDice {
            return "[кубик]"
        }
    }
    return ""
}

private func ayuGramCopilotTranscript(messages: [EngineMessage], accountPeerId: EnginePeer.Id, isGroup: Bool) -> (text: String, mine: Int) {
    var lines: [(String, String)] = []
    for message in messages {
        guard let tag = ayuGramCopilotMediaTag(message) else {
            continue
        }
        let body = ayuGramCopilotLine([tag, message.text].filter({ !$0.isEmpty }).joined(separator: " "))
        if body.isEmpty {
            continue
        }
        let outgoing = !message.flags.contains(.Incoming) || message.author?.id == accountPeerId
        var speaker = "Я"
        if !outgoing {
            if let author = message.author {
                if case let .user(user) = author {
                    speaker = ayuGramCopilotLine(user.firstName ?? user.lastName ?? "")
                } else {
                    speaker = ayuGramCopilotLine(author.debugDisplayTitle)
                }
            } else {
                speaker = isGroup ? "?" : "Собеседник"
            }
            if speaker.isEmpty || speaker == "Я" {
                speaker = "Собеседник"
            }
        }
        if let last = lines.last, last.0 == speaker {
            lines[lines.count - 1].1 = last.1 + " / " + body
        } else {
            lines.append((speaker, body))
        }
    }
    var picked: [String] = []
    var total = 0
    var mine = 0
    for (speaker, body) in lines.reversed() {
        let line = speaker + ": " + body
        if total + line.count > ayuGramCopilotBudget && !picked.isEmpty {
            break
        }
        picked.append(String(line.prefix(ayuGramCopilotBudget)))
        total += line.count + 1
        if speaker == "Я" {
            mine += 1
        }
    }
    return (picked.reversed().joined(separator: "\n"), mine)
}

private func ayuGramCopilotParse(_ text: String) -> (String, [String]) {
    var summary = ""
    var replies: [String] = []
    for raw in text.components(separatedBy: .newlines) {
        var line = raw.trimmingCharacters(in: .whitespaces)
        line = line.replacingOccurrences(of: "**", with: "")
        if line.isEmpty {
            continue
        }
        let upper = line.uppercased()
        if upper.hasPrefix("S:") || upper.hasPrefix("SUMMARY:") || upper.hasPrefix("СИТУАЦИЯ:") {
            summary = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            continue
        }
        if let first = line.first, first.isNumber, line.count > 2 {
            var rest = line.drop(while: { $0.isNumber })
            if let separator = rest.first, [":", ")", ".", "-"].contains(separator) {
                rest = rest.dropFirst()
                var reply = rest.trimmingCharacters(in: .whitespaces)
                if reply.hasPrefix("\"") && reply.hasSuffix("\"") && reply.count > 1 {
                    reply = String(reply.dropFirst().dropLast())
                }
                if !reply.isEmpty {
                    replies.append(reply)
                }
                continue
            }
        }
        if summary.isEmpty && replies.isEmpty {
            summary = line
        }
    }
    return (summary, Array(replies.prefix(3)))
}

private final class AyuGramCopilotSuggestion: UIControl {
    let label = UILabel()
    var text = ""

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.layer.cornerRadius = 14.0
        self.layer.cornerCurve = .continuous
        self.label.numberOfLines = 4
        self.label.font = UIFont.systemFont(ofSize: 15.0)
        self.label.isUserInteractionEnabled = false
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.18, animations: {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.alpha = self.isHighlighted ? 0.75 : 1.0
            })
        }
    }

    func height(width: CGFloat) -> CGFloat {
        let size = self.label.sizeThatFits(CGSize(width: width - 24.0, height: .greatestFiniteMagnitude))
        return ceil(size.height) + 20.0
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        self.label.frame = self.bounds.insetBy(dx: 12.0, dy: 10.0)
    }
}

public final class AyuGramCopilotView: UIView, UITextFieldDelegate {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let isGroup: Bool
    private let insert: (String) -> Void
    private var theme: PresentationTheme
    private var locale: String

    private let button = UIControl()
    private let buttonBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let buttonGhost = AyuGramGhostView()
    private let dim = UIControl()
    private let panel = UIView()
    private let panelBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let scroll = UIScrollView()
    private let headerGhost = AyuGramGhostView()
    private let titleLabel = UILabel()
    private let refreshButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let summaryLabel = UILabel()
    private var shimmerBars: [UIView] = []
    private var suggestions: [AyuGramCopilotSuggestion] = []
    private let answerLabel = UILabel()
    private let field = UITextField()
    private let sendButton = UIButton(type: .system)
    private let fieldBackground = UIView()

    private var expanded = false
    private var loading = false
    private var asking = false
    private var transcript: String?
    private var errorText: String?
    private var answer: String?
    private var anchor = CGPoint()
    private var buttonSize: CGFloat = 40.0
    private var maxWidth: CGFloat = 340.0
    private var maxHeight: CGFloat = 400.0
    private let disposable = MetaDisposable()

    public init(context: AccountContext, peerId: EnginePeer.Id, isGroup: Bool, theme: PresentationTheme, locale: String, insert: @escaping (String) -> Void) {
        self.context = context
        self.peerId = peerId
        self.isGroup = isGroup
        self.theme = theme
        self.locale = locale
        self.insert = insert
        super.init(frame: CGRect())

        self.dim.backgroundColor = UIColor(white: 0.0, alpha: 0.18)
        self.dim.alpha = 0.0
        self.dim.isHidden = true
        self.dim.addTarget(self, action: #selector(self.collapsePressed), for: .touchUpInside)
        self.addSubview(self.dim)

        self.button.clipsToBounds = false
        self.buttonBlur.isUserInteractionEnabled = false
        self.buttonBlur.clipsToBounds = true
        self.button.addSubview(self.buttonBlur)
        self.button.addSubview(self.buttonGhost)
        self.button.layer.shadowColor = UIColor.black.cgColor
        self.button.layer.shadowOpacity = 0.18
        self.button.layer.shadowRadius = 8.0
        self.button.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        self.button.addTarget(self, action: #selector(self.expandPressed), for: .touchUpInside)
        self.button.addTarget(self, action: #selector(self.buttonDown), for: .touchDown)
        self.button.addTarget(self, action: #selector(self.buttonUp), for: [.touchUpOutside, .touchCancel, .touchUpInside])
        self.addSubview(self.button)

        self.panel.isHidden = true
        self.panel.layer.shadowColor = UIColor.black.cgColor
        self.panel.layer.shadowOpacity = 0.25
        self.panel.layer.shadowRadius = 18.0
        self.panel.layer.shadowOffset = CGSize(width: 0.0, height: 6.0)
        self.panelBlur.clipsToBounds = true
        self.panelBlur.layer.cornerRadius = 22.0
        self.panelBlur.layer.cornerCurve = .continuous
        self.panel.addSubview(self.panelBlur)
        self.panelBlur.contentView.addSubview(self.scroll)
        self.scroll.alwaysBounceVertical = false
        self.scroll.showsVerticalScrollIndicator = false

        self.titleLabel.font = UIFont.systemFont(ofSize: 16.0, weight: .semibold)
        self.refreshButton.setImage(UIImage(systemName: "arrow.clockwise", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)), for: .normal)
        self.refreshButton.addTarget(self, action: #selector(self.refreshPressed), for: .touchUpInside)
        self.closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.0, weight: .semibold)), for: .normal)
        self.closeButton.addTarget(self, action: #selector(self.collapsePressed), for: .touchUpInside)
        self.summaryLabel.font = UIFont.systemFont(ofSize: 13.0)
        self.summaryLabel.numberOfLines = 3
        self.answerLabel.numberOfLines = 0
        for _ in 0 ..< 3 {
            let bar = UIView()
            bar.layer.cornerRadius = 12.0
            bar.layer.cornerCurve = .continuous
            self.shimmerBars.append(bar)
            self.scroll.addSubview(bar)
        }
        for _ in 0 ..< 3 {
            let suggestion = AyuGramCopilotSuggestion()
            suggestion.addTarget(self, action: #selector(self.suggestionPressed(_:)), for: .touchUpInside)
            let press = UILongPressGestureRecognizer(target: self, action: #selector(self.suggestionHeld(_:)))
            suggestion.addGestureRecognizer(press)
            self.suggestions.append(suggestion)
            self.scroll.addSubview(suggestion)
        }
        for view in [self.headerGhost, self.titleLabel, self.refreshButton, self.closeButton, self.summaryLabel, self.answerLabel] as [UIView] {
            self.scroll.addSubview(view)
        }
        self.fieldBackground.layer.cornerRadius = 18.0
        self.fieldBackground.layer.cornerCurve = .continuous
        self.scroll.addSubview(self.fieldBackground)
        self.field.font = UIFont.systemFont(ofSize: 15.0)
        self.field.returnKeyType = .send
        self.field.delegate = self
        self.scroll.addSubview(self.field)
        self.sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26.0)), for: .normal)
        self.sendButton.addTarget(self, action: #selector(self.askPressed), for: .touchUpInside)
        self.scroll.addSubview(self.sendButton)
        self.addSubview(self.panel)

        self.applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.disposable.dispose()
    }

    public var isExpanded: Bool {
        return self.expanded
    }

    public func update(theme: PresentationTheme, locale: String) {
        guard theme !== self.theme || locale != self.locale else {
            return
        }
        self.theme = theme
        self.locale = locale
        self.applyTheme()
        self.relayout()
    }

    private func applyTheme() {
        let theme = self.theme
        let dark = theme.overallDarkAppearance
        self.buttonBlur.effect = UIBlurEffect(style: dark ? .systemThinMaterialDark : .systemThinMaterialLight)
        self.panelBlur.effect = UIBlurEffect(style: dark ? .systemThickMaterialDark : .systemThickMaterialLight)
        let accent = theme.list.itemAccentColor
        for ghost in [self.buttonGhost, self.headerGhost] {
            ghost.colors = (dark ? .white : accent.ayuMix(.white, alpha: 0.55), accent)
            ghost.eyeColor = dark ? UIColor(white: 0.08, alpha: 1.0) : .white
        }
        self.titleLabel.textColor = theme.list.itemPrimaryTextColor
        self.titleLabel.text = i18n("Ayu.Copilot", self.locale)
        self.refreshButton.tintColor = theme.list.itemSecondaryTextColor
        self.closeButton.tintColor = theme.list.itemSecondaryTextColor
        self.summaryLabel.textColor = theme.list.itemSecondaryTextColor
        for bar in self.shimmerBars {
            bar.backgroundColor = theme.list.itemPrimaryTextColor.withAlphaComponent(0.07)
        }
        for suggestion in self.suggestions {
            suggestion.backgroundColor = theme.list.itemPrimaryTextColor.withAlphaComponent(dark ? 0.08 : 0.05)
            suggestion.label.textColor = theme.list.itemPrimaryTextColor
        }
        self.fieldBackground.backgroundColor = theme.list.itemPrimaryTextColor.withAlphaComponent(dark ? 0.08 : 0.05)
        self.field.textColor = theme.list.itemPrimaryTextColor
        self.field.tintColor = accent
        self.field.keyboardAppearance = dark ? .dark : .light
        self.field.attributedPlaceholder = NSAttributedString(string: i18n("Ayu.CopilotAsk", self.locale), attributes: [.foregroundColor: theme.list.itemPlaceholderTextColor])
        self.sendButton.tintColor = accent
        self.renderAnswer()
    }

    public func layout(anchor: CGPoint, buttonSize: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat) {
        self.anchor = anchor
        self.buttonSize = buttonSize
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.relayout()
    }

    private func relayout() {
        self.dim.frame = self.bounds
        let size = self.buttonSize
        let buttonFrame = CGRect(x: self.anchor.x - size, y: self.anchor.y, width: size, height: size)
        self.button.bounds = CGRect(origin: CGPoint(), size: buttonFrame.size)
        self.button.center = CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)
        self.buttonBlur.frame = self.button.bounds
        self.buttonBlur.layer.cornerRadius = size / 2.0
        self.button.layer.shadowPath = UIBezierPath(ovalIn: self.button.bounds).cgPath
        let ghostSize = floor(size * 0.62)
        self.buttonGhost.frame = CGRect(x: (size - ghostSize) / 2.0, y: (size - ghostSize) / 2.0 + 1.0, width: ghostSize, height: ghostSize)

        let width = min(self.maxWidth, 340.0)
        let inner = width - 28.0
        var y: CGFloat = 14.0
        self.headerGhost.frame = CGRect(x: 14.0, y: y, width: 24.0, height: 24.0)
        self.closeButton.frame = CGRect(x: width - 14.0 - 30.0, y: y - 3.0, width: 30.0, height: 30.0)
        self.refreshButton.frame = CGRect(x: self.closeButton.frame.minX - 32.0, y: y - 3.0, width: 30.0, height: 30.0)
        self.titleLabel.frame = CGRect(x: 46.0, y: y, width: self.refreshButton.frame.minX - 50.0, height: 24.0)
        y += 34.0

        self.summaryLabel.isHidden = (self.summaryLabel.text ?? "").isEmpty
        if !self.summaryLabel.isHidden {
            let height = ceil(self.summaryLabel.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height)
            self.summaryLabel.frame = CGRect(x: 14.0, y: y, width: inner, height: height)
            y += height + 10.0
        }

        for (index, bar) in self.shimmerBars.enumerated() {
            bar.isHidden = !self.loading
            if self.loading {
                let barWidth = inner * [1.0, 0.82, 0.64][index]
                bar.frame = CGRect(x: 14.0, y: y, width: barWidth, height: 40.0)
                y += 48.0
            }
        }
        for suggestion in self.suggestions {
            let visible = !self.loading && !suggestion.text.isEmpty
            suggestion.isHidden = !visible
            if visible {
                let height = suggestion.height(width: inner)
                suggestion.frame = CGRect(x: 14.0, y: y, width: inner, height: height)
                y += height + 8.0
            }
        }

        self.answerLabel.isHidden = self.answerLabel.attributedText == nil || self.answerLabel.attributedText?.length == 0
        if !self.answerLabel.isHidden {
            y += 2.0
            let height = ceil(self.answerLabel.sizeThatFits(CGSize(width: inner, height: .greatestFiniteMagnitude)).height)
            self.answerLabel.frame = CGRect(x: 14.0, y: y, width: inner, height: height)
            y += height + 10.0
        }

        y += 2.0
        self.fieldBackground.frame = CGRect(x: 14.0, y: y, width: inner, height: 36.0)
        self.field.frame = CGRect(x: 28.0, y: y, width: inner - 14.0 - 36.0, height: 36.0)
        self.sendButton.frame = CGRect(x: 14.0 + inner - 36.0, y: y, width: 36.0, height: 36.0)
        self.sendButton.isEnabled = !self.asking
        self.sendButton.alpha = self.asking ? 0.4 : 1.0
        y += 36.0 + 14.0

        let height = min(y, self.maxHeight)
        self.scroll.contentSize = CGSize(width: width, height: y)
        let panelFrame = CGRect(x: self.anchor.x - width, y: self.anchor.y, width: width, height: height)
        let wasIdentity = self.panel.transform.isIdentity
        let transform = self.panel.transform
        self.panel.transform = .identity
        self.panel.frame = panelFrame
        self.panel.transform = wasIdentity ? .identity : transform
        self.panelBlur.frame = self.panel.bounds
        self.panel.layer.shadowPath = UIBezierPath(roundedRect: self.panel.bounds, cornerRadius: 22.0).cgPath
        self.scroll.frame = self.panelBlur.bounds
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.expanded {
            return super.hitTest(point, with: event)
        }
        if !self.button.isHidden && self.button.frame.insetBy(dx: -6.0, dy: -6.0).contains(point) {
            return self.button
        }
        return nil
    }

    @objc private func buttonDown() {
        UIView.animate(withDuration: 0.15, animations: {
            self.button.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        })
    }

    @objc private func buttonUp() {
        UIView.animate(withDuration: 0.35, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
            self.button.transform = .identity
        })
    }

    @objc private func expandPressed() {
        self.setExpanded(true)
    }

    @objc private func collapsePressed() {
        self.setExpanded(false)
    }

    public func setExpanded(_ value: Bool) {
        guard value != self.expanded else {
            return
        }
        self.expanded = value
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let scale = max(0.12, self.buttonSize / max(1.0, min(self.maxWidth, 340.0)))
        if value {
            self.relayout()
            self.panel.isHidden = false
            self.dim.isHidden = false
            self.setAnchorTopRight(self.panel)
            self.panel.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.panel.alpha = 0.0
            UIView.animate(withDuration: 0.5, delay: 0.0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                self.panel.transform = .identity
                self.panel.alpha = 1.0
                self.dim.alpha = 1.0
                self.button.alpha = 0.0
                self.button.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            })
            self.start(force: false)
        } else {
            self.field.resignFirstResponder()
            UIView.animate(withDuration: 0.3, delay: 0.0, options: [.curveEaseInOut], animations: {
                self.panel.transform = CGAffineTransform(scaleX: scale, y: scale)
                self.panel.alpha = 0.0
                self.dim.alpha = 0.0
            }, completion: { _ in
                if !self.expanded {
                    self.panel.isHidden = true
                    self.dim.isHidden = true
                    self.panel.transform = .identity
                }
            })
            UIView.animate(withDuration: 0.45, delay: 0.1, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.0, options: [], animations: {
                self.button.alpha = 1.0
                self.button.transform = .identity
            })
        }
    }

    private func setAnchorTopRight(_ view: UIView) {
        let frame = view.frame
        view.layer.anchorPoint = CGPoint(x: 1.0, y: 0.0)
        view.frame = frame
    }

    @objc private func refreshPressed() {
        UIView.animate(withDuration: 0.4, animations: {
            self.refreshButton.transform = self.refreshButton.transform.rotated(by: .pi)
        })
        self.start(force: true)
    }

    private func start(force: Bool) {
        self.errorText = nil
        let accountPeerId = self.context.account.peerId
        let isGroup = self.isGroup
        let peerId = self.peerId
        self.disposable.set((self.context.engine.ayuGramRecentMessages(peerId: peerId, limit: 60)
        |> deliverOnMainQueue).startStrict(next: { [weak self] messages in
            guard let self else {
                return
            }
            guard let last = messages.last else {
                self.transcript = nil
                self.show(summary: i18n("Ayu.CopilotEmpty", self.locale), replies: [])
                return
            }
            let built = ayuGramCopilotTranscript(messages: messages, accountPeerId: accountPeerId, isGroup: isGroup)
            self.transcript = built.text
            if !force, let cached = ayuGramCopilotCache[peerId], cached.lastId == last.id {
                self.show(summary: cached.summary, replies: cached.replies)
                return
            }
            self.request(transcript: built.text, mine: built.mine, lastId: last.id)
        }))
    }

    private func request(transcript: String, mine: Int, lastId: EngineMessage.Id) {
        self.loading = true
        self.headerGhost.squint = false
        self.headerGhost.lookTarget = CGPoint(x: 0.9, y: -0.4)
        self.summaryLabel.text = i18n("Ayu.CopilotThinking", self.locale)
        self.relayout()
        self.startShimmer()
        let style = mine < 3 ? " If there are few Я lines, write naturally and casually." : ""
        let system = "You help the user (Я) reply in a Telegram chat. Read the dialog, understand the situation, and copy Я's writing style exactly: language, length, letter case, slang, emoji, punctuation." + style + " Reply strictly in this format and nothing else:\nS: <one short line: what is going on and what the other side wants, in the dialog language>\n1: <next message from Я>\n2: <different variant>\n3: <different variant>\nEach variant is one message Я would actually send now, as short as Я's usual messages, no quotes."
        let prompt = "Dialog, oldest first:\n" + transcript
        let peerId = self.peerId
        ayuGramAssistantComplete(system: system, prompt: prompt, maxTokens: 320, locale: self.locale, completion: { [weak self] reply, failure in
            guard let self else {
                return
            }
            self.loading = false
            self.headerGhost.lookTarget = nil
            if let reply {
                let parsed = ayuGramCopilotParse(reply)
                if parsed.1.isEmpty {
                    self.show(summary: parsed.0.isEmpty ? reply : parsed.0, replies: [])
                } else {
                    ayuGramCopilotCache[peerId] = AyuGramCopilotResult(lastId: lastId, summary: parsed.0, replies: parsed.1)
                    self.show(summary: parsed.0, replies: parsed.1)
                    self.headerGhost.hop()
                }
            } else {
                self.show(summary: failure ?? i18n("Ayu.AIError", self.locale), replies: [])
            }
        })
    }

    private func startShimmer() {
        for (index, bar) in self.shimmerBars.enumerated() {
            bar.layer.removeAllAnimations()
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.35
            pulse.duration = 0.7
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            bar.layer.add(pulse, forKey: "pulse")
        }
    }

    private func show(summary: String, replies: [String]) {
        self.loading = false
        self.summaryLabel.text = summary
        for (index, suggestion) in self.suggestions.enumerated() {
            suggestion.text = index < replies.count ? replies[index] : ""
            suggestion.label.text = suggestion.text
        }
        self.relayout()
        for (index, suggestion) in self.suggestions.enumerated() where !suggestion.isHidden {
            suggestion.alpha = 0.0
            suggestion.transform = CGAffineTransform(translationX: 0.0, y: 10.0)
            UIView.animate(withDuration: 0.4, delay: Double(index) * 0.06, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: [.allowUserInteraction], animations: {
                suggestion.alpha = 1.0
                suggestion.transform = .identity
            })
        }
    }

    @objc private func suggestionPressed(_ sender: AyuGramCopilotSuggestion) {
        guard !sender.text.isEmpty else {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self.insert(sender.text)
        self.setExpanded(false)
    }

    @objc private func suggestionHeld(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let suggestion = recognizer.view as? AyuGramCopilotSuggestion, !suggestion.text.isEmpty else {
            return
        }
        UIPasteboard.general.string = suggestion.text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let original = suggestion.backgroundColor
        UIView.animate(withDuration: 0.15, animations: {
            suggestion.backgroundColor = self.theme.list.itemAccentColor.withAlphaComponent(0.25)
        }, completion: { _ in
            UIView.animate(withDuration: 0.4, animations: {
                suggestion.backgroundColor = original
            })
        })
        self.summaryLabel.text = i18n("Ayu.CopilotCopied", self.locale)
        self.relayout()
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.askPressed()
        return false
    }

    @objc private func askPressed() {
        let question = (self.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !self.asking else {
            return
        }
        guard let transcript = self.transcript else {
            return
        }
        self.asking = true
        self.field.text = ""
        self.answer = i18n("Ayu.CopilotThinking", self.locale)
        self.renderAnswer()
        self.relayout()
        self.headerGhost.lookTarget = CGPoint(x: -0.9, y: 0.6)
        let system = "You analyze a Telegram dialog for the user (Я) and answer their question about it. Be brief: at most 4 sentences, in the language of the question. If asked what to write, give one ready message in Я's style."
        let prompt = "Dialog, oldest first:\n" + transcript + "\n\nQuestion: " + String(question.prefix(500))
        ayuGramAssistantComplete(system: system, prompt: prompt, maxTokens: 380, locale: self.locale, completion: { [weak self] reply, failure in
            guard let self else {
                return
            }
            self.asking = false
            self.headerGhost.lookTarget = nil
            self.answer = reply ?? failure ?? i18n("Ayu.AIError", self.locale)
            self.renderAnswer()
            self.relayout()
            self.answerLabel.alpha = 0.0
            UIView.animate(withDuration: 0.3, animations: {
                self.answerLabel.alpha = 1.0
            })
            let bottom = max(0.0, self.scroll.contentSize.height - self.scroll.bounds.height)
            self.scroll.setContentOffset(CGPoint(x: 0.0, y: bottom), animated: true)
        })
    }

    private func renderAnswer() {
        guard let answer = self.answer, !answer.isEmpty else {
            self.answerLabel.attributedText = nil
            return
        }
        self.answerLabel.attributedText = ayuGramAssistantFormatted(answer, color: self.theme.list.itemPrimaryTextColor)
    }
}
