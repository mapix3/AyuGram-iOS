import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import SGSimpleSettings
import SGStrings

struct AyuGramAssistantProvider {
    let id: String
    let title: String
    let endpoint: String
    let model: String
    let keyHint: String
    let needsKey: Bool

    static let all: [AyuGramAssistantProvider] = [
        AyuGramAssistantProvider(id: "pollinations", title: "Pollinations", endpoint: "https://text.pollinations.ai/openai", model: "openai", keyHint: "", needsKey: false),
        AyuGramAssistantProvider(id: "groq", title: "Groq", endpoint: "https://api.groq.com/openai/v1/chat/completions", model: "llama-3.3-70b-versatile", keyHint: "gsk_...", needsKey: true),
        AyuGramAssistantProvider(id: "gemini", title: "Google Gemini", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", model: "gemini-flash-latest", keyHint: "AIza...", needsKey: true),
        AyuGramAssistantProvider(id: "openrouter", title: "OpenRouter", endpoint: "https://openrouter.ai/api/v1/chat/completions", model: "meta-llama/llama-3.3-70b-instruct:free", keyHint: "sk-or-...", needsKey: true)
    ]
}

struct AyuGramAssistantConfig {
    let provider: AyuGramAssistantProvider
    let key: String
    let model: String

    private static let providerKey = "ayugram.assistant.provider"

    static var providerIndex: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: providerKey)
            return value >= 0 && value < AyuGramAssistantProvider.all.count ? value : 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: providerKey)
            NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
        }
    }

    static var current: AyuGramAssistantConfig {
        let provider = AyuGramAssistantProvider.all[providerIndex]
        let key = UserDefaults.standard.string(forKey: "ayugram.assistant.key." + provider.id) ?? ""
        let model = UserDefaults.standard.string(forKey: "ayugram.assistant.model." + provider.id) ?? ""
        return AyuGramAssistantConfig(provider: provider, key: key, model: model.isEmpty ? provider.model : model)
    }

    static func setKey(_ value: String) {
        let provider = AyuGramAssistantProvider.all[providerIndex]
        UserDefaults.standard.set(value, forKey: "ayugram.assistant.key." + provider.id)
        NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
    }

    static func setModel(_ value: String) {
        let provider = AyuGramAssistantProvider.all[providerIndex]
        UserDefaults.standard.set(value, forKey: "ayugram.assistant.model." + provider.id)
        NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
    }
}

private struct AyuGramAssistantMessage {
    let outgoing: Bool
    let text: String
    let failed: Bool
}

private var ayuGramAssistantMessages: [AyuGramAssistantMessage] = []

private func ayuGramAssistantRequest(messages: [AyuGramAssistantMessage], locale: String, completion: @escaping (String?, String?) -> Void) {
    let config = AyuGramAssistantConfig.current
    if config.provider.needsKey && config.key.isEmpty {
        completion(nil, i18n("Ayu.AINeedKey", locale))
        return
    }
    guard let url = URL(string: config.provider.endpoint) else {
        completion(nil, i18n("Ayu.AIError", locale))
        return
    }
    var payload: [[String: String]] = [["role": "system", "content": "You are a helpful assistant built into AyuGram, a Telegram client. Answer in the language of the user. Use plain text without markdown."]]
    for message in messages.filter({ !$0.failed }).suffix(20) {
        payload.append(["role": message.outgoing ? "user" : "assistant", "content": message.text])
    }
    let body: [String: Any] = ["model": config.model, "messages": payload]
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 90.0
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if !config.key.isEmpty {
        request.setValue("Bearer " + config.key, forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
        var text: String?
        var failure: String?
        if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String {
                text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let details = object["error"] as? [String: Any], let message = details["message"] as? String {
                failure = message
            } else if let message = object["error"] as? String {
                failure = message
            }
        } else if let data, let raw = String(data: data, encoding: .utf8), !raw.isEmpty, (response as? HTTPURLResponse)?.statusCode == 200 {
            text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text == nil || text?.isEmpty == true {
            text = nil
            if failure == nil {
                if let error {
                    failure = error.localizedDescription
                } else if let status = (response as? HTTPURLResponse)?.statusCode {
                    failure = "HTTP \(status)"
                }
            }
        }
        DispatchQueue.main.async {
            completion(text, text == nil ? (failure ?? i18n("Ayu.AIError", locale)) : nil)
        }
    }).resume()
}

private final class AyuGramAssistantCell: UITableViewCell {
    private let bubble = UIView()
    private let label = UILabel()
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        self.bubble.layer.cornerRadius = 16.0
        self.bubble.translatesAutoresizingMaskIntoConstraints = false
        self.label.numberOfLines = 0
        self.label.font = UIFont.systemFont(ofSize: 16.0)
        self.label.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(self.bubble)
        self.bubble.addSubview(self.label)
        let leading = self.bubble.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 12.0)
        let trailing = self.bubble.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -12.0)
        self.leading = leading
        self.trailing = trailing
        NSLayoutConstraint.activate([
            self.bubble.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 4.0),
            self.bubble.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -4.0),
            self.bubble.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor, multiplier: 0.82),
            self.label.topAnchor.constraint(equalTo: self.bubble.topAnchor, constant: 9.0),
            self.label.bottomAnchor.constraint(equalTo: self.bubble.bottomAnchor, constant: -9.0),
            self.label.leadingAnchor.constraint(equalTo: self.bubble.leadingAnchor, constant: 13.0),
            self.label.trailingAnchor.constraint(equalTo: self.bubble.trailingAnchor, constant: -13.0)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: AyuGramAssistantMessage, theme: PresentationTheme) {
        self.label.text = message.text
        self.leading?.isActive = !message.outgoing
        self.trailing?.isActive = message.outgoing
        if message.outgoing {
            self.bubble.backgroundColor = theme.list.itemAccentColor
            self.label.textColor = theme.list.itemCheckColors.foregroundColor
        } else {
            self.bubble.backgroundColor = theme.list.itemBlocksBackgroundColor
            self.label.textColor = message.failed ? theme.list.itemDestructiveColor : theme.list.itemPrimaryTextColor
        }
    }
}

private final class AyuGramAssistantNode: ASDisplayNode, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    private var presentationData: PresentationData
    private let tableView = UITableView(frame: CGRect(), style: .plain)
    private let inputBar = UIView()
    private let separator = UIView()
    private let field = UITextField()
    private let sendButton = UIButton(type: .system)
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()
    private var loading = false

    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        super.init()

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.separatorStyle = .none
        self.tableView.keyboardDismissMode = .interactive
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 60.0
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.register(AyuGramAssistantCell.self, forCellReuseIdentifier: "message")
        self.view.addSubview(self.tableView)

        self.emptyLabel.textAlignment = .center
        self.emptyLabel.numberOfLines = 0
        self.emptyLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.view.addSubview(self.emptyLabel)

        self.field.font = UIFont.systemFont(ofSize: 16.0)
        self.field.returnKeyType = .send
        self.field.delegate = self
        self.field.layer.cornerRadius = 18.0
        self.field.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.field.leftViewMode = .always
        self.field.rightView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.field.rightViewMode = .always

        self.sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30.0)), for: .normal)
        self.sendButton.addTarget(self, action: #selector(self.sendPressed), for: .touchUpInside)
        self.indicator.hidesWhenStopped = true

        self.inputBar.addSubview(self.separator)
        self.inputBar.addSubview(self.field)
        self.inputBar.addSubview(self.sendButton)
        self.inputBar.addSubview(self.indicator)
        self.view.addSubview(self.inputBar)

        self.applyTheme()
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.applyTheme()
        self.tableView.reloadData()
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        let locale = self.presentationData.strings.baseLanguageCode
        self.backgroundColor = theme.list.blocksBackgroundColor
        self.tableView.backgroundColor = theme.list.blocksBackgroundColor
        self.inputBar.backgroundColor = theme.list.blocksBackgroundColor
        self.separator.backgroundColor = theme.list.itemBlocksSeparatorColor
        self.field.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.field.textColor = theme.list.itemPrimaryTextColor
        self.field.tintColor = theme.list.itemAccentColor
        self.field.keyboardAppearance = theme.overallDarkAppearance ? .dark : .light
        self.field.attributedPlaceholder = NSAttributedString(string: i18n("Ayu.AIPlaceholder", locale), attributes: [.foregroundColor: theme.list.itemPlaceholderTextColor])
        self.sendButton.tintColor = theme.list.itemAccentColor
        self.indicator.color = theme.list.itemAccentColor
        self.emptyLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyLabel.text = i18n("Ayu.AIEmpty", locale)
        self.emptyLabel.isHidden = !ayuGramAssistantMessages.isEmpty
    }

    func clear() {
        ayuGramAssistantMessages = []
        self.emptyLabel.isHidden = false
        self.tableView.reloadData()
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let size = layout.size
        let bottom = layout.insets(options: [.input]).bottom
        let side = layout.safeInsets.left
        let barHeight: CGFloat = 52.0
        let barFrame = CGRect(x: 0.0, y: size.height - bottom - barHeight, width: size.width, height: barHeight + bottom)
        transition.updateFrame(view: self.inputBar, frame: barFrame)
        self.separator.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: 1.0 / UIScreen.main.scale)
        self.field.frame = CGRect(x: side + 12.0, y: 8.0, width: max(0.0, size.width - side * 2.0 - 12.0 - 52.0), height: 36.0)
        self.sendButton.frame = CGRect(x: size.width - side - 46.0, y: 6.0, width: 40.0, height: 40.0)
        self.indicator.center = self.sendButton.center
        let tableFrame = CGRect(x: 0.0, y: navigationHeight, width: size.width, height: max(0.0, barFrame.minY - navigationHeight))
        transition.updateFrame(view: self.tableView, frame: tableFrame)
        self.emptyLabel.frame = tableFrame.insetBy(dx: 32.0, dy: 0.0)
        self.scrollToBottom(animated: false)
    }

    private func scrollToBottom(animated: Bool) {
        let count = ayuGramAssistantMessages.count
        if count > 0 && self.tableView.numberOfRows(inSection: 0) == count {
            self.tableView.scrollToRow(at: IndexPath(row: count - 1, section: 0), at: .bottom, animated: animated)
        }
    }

    private func setLoading(_ value: Bool) {
        self.loading = value
        self.sendButton.isHidden = value
        if value {
            self.indicator.startAnimating()
        } else {
            self.indicator.stopAnimating()
        }
    }

    private func append(_ message: AyuGramAssistantMessage) {
        ayuGramAssistantMessages.append(message)
        self.emptyLabel.isHidden = true
        self.tableView.reloadData()
        self.tableView.layoutIfNeeded()
        self.scrollToBottom(animated: true)
    }

    @objc private func sendPressed() {
        let text = (self.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !self.loading else {
            return
        }
        self.field.text = ""
        self.append(AyuGramAssistantMessage(outgoing: true, text: text, failed: false))
        self.setLoading(true)
        ayuGramAssistantRequest(messages: ayuGramAssistantMessages, locale: self.presentationData.strings.baseLanguageCode, completion: { [weak self] reply, failure in
            guard let self else {
                return
            }
            self.setLoading(false)
            if let reply {
                self.append(AyuGramAssistantMessage(outgoing: false, text: reply, failed: false))
            } else {
                self.append(AyuGramAssistantMessage(outgoing: false, text: failure ?? "", failed: true))
            }
        })
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.sendPressed()
        return false
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ayuGramAssistantMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath)
        if let cell = cell as? AyuGramAssistantCell, indexPath.row < ayuGramAssistantMessages.count {
            cell.update(message: ayuGramAssistantMessages[indexPath.row], theme: self.presentationData.theme)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.row < ayuGramAssistantMessages.count else {
            return nil
        }
        let text = ayuGramAssistantMessages[indexPath.row].text
        let title = i18n("Ayu.AICopy", self.presentationData.strings.baseLanguageCode)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            return UIMenu(title: "", children: [UIAction(title: title, image: UIImage(systemName: "doc.on.doc"), handler: { _ in
                UIPasteboard.general.string = text
            })])
        })
    }
}

private final class AyuGramAssistantController: ViewController {
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private var node: AyuGramAssistantNode {
        return self.displayNode as! AyuGramAssistantNode
    }

    init(context: AccountContext) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))

        let locale = presentationData.strings.baseLanguageCode
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.title = i18n("Ayu.Assistant", locale)
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: i18n("Ayu.AIClear", locale), style: .plain, target: self, action: #selector(self.clearPressed))

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            let previousTheme = self.presentationData.theme
            self.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
                self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
                if self.isNodeLoaded {
                    self.node.updatePresentationData(presentationData)
                }
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    @objc private func clearPressed() {
        if self.isNodeLoaded {
            self.node.clear()
        }
    }

    override func loadDisplayNode() {
        self.displayNode = AyuGramAssistantNode(presentationData: self.presentationData)
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.node.containerLayoutUpdated(layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}

func ayuGramAssistantController(context: AccountContext) -> ViewController {
    return AyuGramAssistantController(context: context)
}
