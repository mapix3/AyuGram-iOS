import Foundation
import UIKit
import AVFoundation
import PhotosUI
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
        AyuGramAssistantProvider(id: "ayugram", title: "AyuGram", endpoint: AyuGramPushRelay.baseURL + "/ai", model: "llama-3.3-70b", keyHint: "", needsKey: false),
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
    let image: UIImage?
    let imagePayload: String?

    init(outgoing: Bool, text: String, failed: Bool, image: UIImage? = nil, imagePayload: String? = nil) {
        self.outgoing = outgoing
        self.text = text
        self.failed = failed
        self.image = image
        self.imagePayload = imagePayload
    }
}

private final class AyuGramAssistantChat {
    let id: String
    var title: String
    var updated: Double
    var messages: [AyuGramAssistantMessage]

    init(id: String, title: String, updated: Double, messages: [AyuGramAssistantMessage]) {
        self.id = id
        self.title = title
        self.updated = updated
        self.messages = messages
    }
}

private final class AyuGramAssistantStore {
    static let shared = AyuGramAssistantStore()

    private(set) var chats: [AyuGramAssistantChat] = []
    private(set) var current: AyuGramAssistantChat
    private let queue = DispatchQueue(label: "ayugram.assistant.store", qos: .utility)

    private static var file: URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory.appendingPathComponent("ayugram-assistant-chats.json")
    }

    private init() {
        self.current = AyuGramAssistantChat(id: UUID().uuidString, title: "", updated: Date().timeIntervalSince1970, messages: [])
        guard let file = AyuGramAssistantStore.file, let data = try? Data(contentsOf: file), let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return
        }
        for item in list {
            guard let id = item["id"] as? String, let rawMessages = item["messages"] as? [[String: Any]] else {
                continue
            }
            var messages: [AyuGramAssistantMessage] = []
            for raw in rawMessages {
                guard let text = raw["t"] as? String else {
                    continue
                }
                messages.append(AyuGramAssistantMessage(outgoing: (raw["o"] as? Bool) ?? false, text: text, failed: (raw["f"] as? Bool) ?? false))
            }
            if messages.isEmpty {
                continue
            }
            self.chats.append(AyuGramAssistantChat(id: id, title: (item["title"] as? String) ?? "", updated: (item["updated"] as? Double) ?? 0.0, messages: messages))
        }
        self.chats.sort(by: { $0.updated > $1.updated })
    }

    private func save() {
        var list: [[String: Any]] = []
        for chat in self.chats.prefix(100) {
            var messages: [[String: Any]] = []
            for message in chat.messages.suffix(200) {
                let text = message.text.isEmpty && message.image != nil ? "🖼" : message.text
                messages.append(["o": message.outgoing, "t": text, "f": message.failed])
            }
            list.append(["id": chat.id, "title": chat.title, "updated": chat.updated, "messages": messages])
        }
        guard let file = AyuGramAssistantStore.file, let data = try? JSONSerialization.data(withJSONObject: list) else {
            return
        }
        self.queue.async {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    func append(_ message: AyuGramAssistantMessage, to chat: AyuGramAssistantChat) {
        chat.messages.append(message)
        chat.updated = Date().timeIntervalSince1970
        if chat.title.isEmpty && message.outgoing {
            let words = message.text.components(separatedBy: .whitespacesAndNewlines).filter({ !$0.isEmpty }).joined(separator: " ")
            chat.title = String(words.prefix(48))
        }
        self.chats.removeAll(where: { $0 === chat })
        self.chats.insert(chat, at: 0)
        self.save()
    }

    func select(_ chat: AyuGramAssistantChat) {
        self.current = chat
    }

    func startNew() {
        if !self.current.messages.isEmpty {
            self.current = AyuGramAssistantChat(id: UUID().uuidString, title: "", updated: Date().timeIntervalSince1970, messages: [])
        }
    }

    func rename(_ chat: AyuGramAssistantChat, title: String) {
        chat.title = String(title.prefix(80))
        self.save()
    }

    func delete(_ chat: AyuGramAssistantChat) {
        self.chats.removeAll(where: { $0 === chat })
        if self.current === chat {
            self.current = AyuGramAssistantChat(id: UUID().uuidString, title: "", updated: Date().timeIntervalSince1970, messages: [])
        }
        self.save()
    }
}

private var ayuGramAssistantMessages: [AyuGramAssistantMessage] {
    return AyuGramAssistantStore.shared.current.messages
}

private func ayuGramAssistantIcon(_ name: String, color: UIColor) -> UIImage? {
    guard let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.0, weight: .regular))?.withTintColor(color, renderingMode: .alwaysOriginal) else {
        return nil
    }
    return UIGraphicsImageRenderer(size: symbol.size).image { _ in
        symbol.draw(at: CGPoint())
    }
}

private func ayuGramAssistantFailure(data: Data?, response: URLResponse?, error: Error?, locale: String) -> String {
    if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let details = object["error"] as? [String: Any], let message = details["message"] as? String {
            return message
        }
        if let message = object["error"] as? String {
            return message
        }
    }
    if let error {
        return error.localizedDescription
    }
    if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
        return "HTTP \(status)"
    }
    return i18n("Ayu.AIError", locale)
}

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
    let history = Array(messages.filter({ !$0.failed }).suffix(20))
    var payload: [[String: Any]] = [["role": "system", "content": "You are a helpful assistant built into AyuGram, a Telegram client. Answer in the language of the user. Use plain text without markdown."]]
    for (index, message) in history.enumerated() {
        let role = message.outgoing ? "user" : "assistant"
        if let imagePayload = message.imagePayload, index == history.count - 1 {
            let picture: [String: Any] = ["type": "image_url", "image_url": ["url": imagePayload]]
            let caption: [String: Any] = ["type": "text", "text": message.text.isEmpty ? "Describe this image." : message.text]
            let parts: [[String: Any]] = [caption, picture]
            payload.append(["role": role, "content": parts])
        } else {
            payload.append(["role": role, "content": message.text.isEmpty ? "[image]" : message.text])
        }
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
        if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let choices = object["choices"] as? [[String: Any]], let message = choices.first?["message"] as? [String: Any], let content = message["content"] as? String {
                text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let data, let raw = String(data: data, encoding: .utf8), (response as? HTTPURLResponse)?.statusCode == 200 {
            text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text?.isEmpty == true {
            text = nil
        }
        let failure = text == nil ? ayuGramAssistantFailure(data: data, response: response, error: error, locale: locale) : nil
        DispatchQueue.main.async {
            completion(text, failure)
        }
    }).resume()
}

private func ayuGramAssistantTranscribe(file: URL, locale: String, completion: @escaping (String?, String?) -> Void) {
    guard let audio = try? Data(contentsOf: file), !audio.isEmpty else {
        completion(nil, i18n("Ayu.AIError", locale))
        return
    }
    let config = AyuGramAssistantConfig.current
    var request: URLRequest
    if config.provider.id == "groq", !config.key.isEmpty, let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions") {
        let boundary = "ayugram-" + UUID().uuidString
        var form = Data()
        form.append(Data(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n").utf8))
        form.append(Data(("--" + boundary + "\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.m4a\"\r\nContent-Type: audio/m4a\r\n\r\n").utf8))
        form.append(audio)
        form.append(Data(("\r\n--" + boundary + "--\r\n").utf8))
        request = URLRequest(url: url)
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + config.key, forHTTPHeaderField: "Authorization")
        request.httpBody = form
    } else if let url = URL(string: AyuGramPushRelay.baseURL + "/ai/transcribe") {
        request = URLRequest(url: url)
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        request.httpBody = audio
    } else {
        completion(nil, i18n("Ayu.AIError", locale))
        return
    }
    request.httpMethod = "POST"
    request.timeoutInterval = 90.0
    URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
        var text: String?
        if let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let value = object["text"] as? String {
            text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text?.isEmpty == true {
            text = nil
        }
        let failure = text == nil ? ayuGramAssistantFailure(data: data, response: response, error: error, locale: locale) : nil
        DispatchQueue.main.async {
            completion(text, failure)
        }
    }).resume()
}

private func ayuGramAssistantPrepare(image: UIImage) -> (UIImage, String)? {
    let side = max(image.size.width, image.size.height)
    guard side > 0.0 else {
        return nil
    }
    let scale = min(1.0, 1024.0 / side)
    let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: CGPoint(), size: size))
    }
    guard let data = scaled.jpegData(compressionQuality: 0.7) else {
        return nil
    }
    return (scaled, "data:image/jpeg;base64," + data.base64EncodedString())
}

private func ayuGramAssistantInline(_ line: String, font: UIFont, color: UIColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let chars = Array(line)
    let bold = UIFont.systemFont(ofSize: font.pointSize, weight: .semibold)
    let italic = UIFont.italicSystemFont(ofSize: font.pointSize)
    let mono = UIFont.monospacedSystemFont(ofSize: font.pointSize - 1.0, weight: .regular)
    var plain = ""
    func flush() {
        if !plain.isEmpty {
            result.append(NSAttributedString(string: plain, attributes: [.font: font, .foregroundColor: color]))
            plain = ""
        }
    }
    func find(_ marker: [Character], from start: Int) -> Int? {
        if marker.isEmpty || start >= chars.count {
            return nil
        }
        var index = start
        while index + marker.count <= chars.count {
            if Array(chars[index ..< index + marker.count]) == marker {
                return index
            }
            index += 1
        }
        return nil
    }
    var index = 0
    while index < chars.count {
        let char = chars[index]
        if char == "`", let end = find(["`"], from: index + 1), end > index + 1 {
            flush()
            result.append(NSAttributedString(string: String(chars[index + 1 ..< end]), attributes: [.font: mono, .foregroundColor: color]))
            index = end + 1
            continue
        }
        if char == "*", index + 1 < chars.count, chars[index + 1] == "*", let end = find(["*", "*"], from: index + 2), end > index + 2 {
            flush()
            result.append(NSAttributedString(string: String(chars[index + 2 ..< end]), attributes: [.font: bold, .foregroundColor: color]))
            index = end + 2
            continue
        }
        if char == "_", index + 1 < chars.count, chars[index + 1] == "_", let end = find(["_", "_"], from: index + 2), end > index + 2 {
            flush()
            result.append(NSAttributedString(string: String(chars[index + 2 ..< end]), attributes: [.font: bold, .foregroundColor: color]))
            index = end + 2
            continue
        }
        if char == "*", index + 1 < chars.count, chars[index + 1] != " ", chars[index + 1] != "*", let end = find(["*"], from: index + 1), end > index + 1, chars[end - 1] != " " {
            flush()
            result.append(NSAttributedString(string: String(chars[index + 1 ..< end]), attributes: [.font: italic, .foregroundColor: color]))
            index = end + 1
            continue
        }
        if char == "~", index + 1 < chars.count, chars[index + 1] == "~", let end = find(["~", "~"], from: index + 2), end > index + 2 {
            flush()
            result.append(NSAttributedString(string: String(chars[index + 2 ..< end]), attributes: [.font: font, .foregroundColor: color, .strikethroughStyle: NSUnderlineStyle.single.rawValue]))
            index = end + 2
            continue
        }
        if char == "[", let middle = find(["]", "("], from: index + 1), middle > index + 1, let end = find([")"], from: middle + 2) {
            flush()
            result.append(NSAttributedString(string: String(chars[index + 1 ..< middle]), attributes: [.font: font, .foregroundColor: color, .underlineStyle: NSUnderlineStyle.single.rawValue]))
            index = end + 1
            continue
        }
        plain.append(char)
        index += 1
    }
    flush()
    return result
}

private func ayuGramAssistantFormatted(_ text: String, color: UIColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let base = UIFont.systemFont(ofSize: 16.0)
    let mono = UIFont.monospacedSystemFont(ofSize: 14.0, weight: .regular)
    var inCode = false
    var first = true
    for rawLine in text.components(separatedBy: "\n") {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            inCode = !inCode
            continue
        }
        if !first {
            result.append(NSAttributedString(string: "\n", attributes: [.font: base, .foregroundColor: color]))
        }
        first = false
        if inCode {
            result.append(NSAttributedString(string: rawLine, attributes: [.font: mono, .foregroundColor: color]))
            continue
        }
        var level = 0
        for char in trimmed {
            if char == "#" {
                level += 1
            } else {
                break
            }
        }
        if level > 0 && level <= 6 && trimmed.count > level && Array(trimmed)[level] == " " {
            let size: CGFloat = level == 1 ? 20.0 : (level == 2 ? 18.0 : 17.0)
            let content = String(trimmed.dropFirst(level + 1)).replacingOccurrences(of: "**", with: "")
            result.append(ayuGramAssistantInline(content, font: UIFont.systemFont(ofSize: size, weight: .bold), color: color))
            continue
        }
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            result.append(NSAttributedString(string: "—————", attributes: [.font: base, .foregroundColor: color.withAlphaComponent(0.4)]))
            continue
        }
        let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            result.append(NSAttributedString(string: indent + "•  ", attributes: [.font: base, .foregroundColor: color]))
            result.append(ayuGramAssistantInline(String(trimmed.dropFirst(2)), font: base, color: color))
            continue
        }
        if trimmed.hasPrefix("> ") {
            result.append(NSAttributedString(string: "▎ ", attributes: [.font: base, .foregroundColor: color.withAlphaComponent(0.5)]))
            result.append(ayuGramAssistantInline(String(trimmed.dropFirst(2)), font: UIFont.italicSystemFont(ofSize: 16.0), color: color))
            continue
        }
        result.append(NSAttributedString(string: indent, attributes: [.font: base, .foregroundColor: color]))
        result.append(ayuGramAssistantInline(trimmed, font: base, color: color))
    }
    return result
}

private final class AyuGramAssistantCell: UITableViewCell {
    private let bubble = UIView()
    private let stack = UIStackView()
    private let picture = UIImageView()
    private let label = UILabel()
    private var leading: NSLayoutConstraint?
    private var trailing: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        self.backgroundColor = .clear
        self.selectionStyle = .none
        self.bubble.layer.cornerRadius = 18.0
        self.bubble.layer.cornerCurve = .continuous
        self.bubble.translatesAutoresizingMaskIntoConstraints = false
        self.stack.axis = .vertical
        self.stack.spacing = 8.0
        self.stack.alignment = .leading
        self.stack.translatesAutoresizingMaskIntoConstraints = false
        self.picture.contentMode = .scaleAspectFill
        self.picture.clipsToBounds = true
        self.picture.layer.cornerRadius = 12.0
        self.label.numberOfLines = 0
        self.label.font = UIFont.systemFont(ofSize: 16.0)
        self.contentView.addSubview(self.bubble)
        self.bubble.addSubview(self.stack)
        self.stack.addArrangedSubview(self.picture)
        self.stack.addArrangedSubview(self.label)
        let leading = self.bubble.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 12.0)
        let trailing = self.bubble.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor, constant: -12.0)
        self.leading = leading
        self.trailing = trailing
        let pictureWidth = self.picture.widthAnchor.constraint(equalToConstant: 180.0)
        pictureWidth.priority = UILayoutPriority(999.0)
        let pictureHeight = self.picture.heightAnchor.constraint(equalToConstant: 180.0)
        pictureHeight.priority = UILayoutPriority(999.0)
        NSLayoutConstraint.activate([
            self.bubble.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 4.0),
            self.bubble.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -4.0),
            self.bubble.widthAnchor.constraint(lessThanOrEqualTo: self.contentView.widthAnchor, multiplier: 0.82),
            self.stack.topAnchor.constraint(equalTo: self.bubble.topAnchor, constant: 9.0),
            self.stack.bottomAnchor.constraint(equalTo: self.bubble.bottomAnchor, constant: -9.0),
            self.stack.leadingAnchor.constraint(equalTo: self.bubble.leadingAnchor, constant: 13.0),
            self.stack.trailingAnchor.constraint(equalTo: self.bubble.trailingAnchor, constant: -13.0),
            pictureWidth,
            pictureHeight
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: AyuGramAssistantMessage, theme: PresentationTheme) {
        self.label.text = message.text
        self.label.isHidden = message.text.isEmpty
        self.picture.image = message.image
        self.picture.isHidden = message.image == nil
        self.leading?.isActive = !message.outgoing
        self.trailing?.isActive = message.outgoing
        if message.outgoing {
            self.bubble.backgroundColor = theme.list.itemCheckColors.fillColor
            self.label.textColor = theme.list.itemCheckColors.foregroundColor
        } else {
            self.bubble.backgroundColor = theme.list.itemBlocksBackgroundColor
            self.label.textColor = message.failed ? theme.list.itemDestructiveColor : theme.list.itemPrimaryTextColor
            if !message.failed && !message.text.isEmpty {
                self.label.attributedText = ayuGramAssistantFormatted(message.text, color: theme.list.itemPrimaryTextColor)
            }
        }
    }
}

private final class AyuGramAssistantChatCell: UITableViewCell {
    private let title = UILabel()
    private let plate = UIView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.backgroundColor = .clear
        self.selectionStyle = .none
        self.plate.layer.cornerRadius = 10.0
        self.plate.layer.cornerCurve = .continuous
        self.title.font = UIFont.systemFont(ofSize: 16.0)
        self.title.lineBreakMode = .byTruncatingTail
        self.contentView.addSubview(self.plate)
        self.contentView.addSubview(self.title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = self.contentView.bounds
        self.plate.frame = bounds.insetBy(dx: 8.0, dy: 2.0)
        self.title.frame = bounds.insetBy(dx: 20.0, dy: 2.0)
    }

    func update(title: String, active: Bool, theme: PresentationTheme) {
        self.title.text = title
        self.title.textColor = theme.list.itemPrimaryTextColor
        self.plate.backgroundColor = active ? theme.list.itemAccentColor.withAlphaComponent(0.16) : .clear
    }
}

private final class AyuGramAssistantDrawer: UIView, UITableViewDataSource, UITableViewDelegate {
    private let dim = UIButton(type: .custom)
    private let panel = UIView()
    private let heading = UILabel()
    private let newButton = UIButton(type: .system)
    private let line = UIView()
    private let tableView = UITableView(frame: CGRect(), style: .plain)
    private var theme: PresentationTheme
    private var locale: String
    private var panelWidth: CGFloat = 0.0
    private(set) var isOpen = false

    var selected: ((AyuGramAssistantChat) -> Void)?
    var created: (() -> Void)?
    var renameRequested: ((AyuGramAssistantChat) -> Void)?
    var deleted: ((AyuGramAssistantChat) -> Void)?

    init(theme: PresentationTheme, locale: String) {
        self.theme = theme
        self.locale = locale
        super.init(frame: CGRect())

        self.isHidden = true
        self.dim.backgroundColor = UIColor(white: 0.0, alpha: 0.4)
        self.dim.alpha = 0.0
        self.dim.addTarget(self, action: #selector(self.dimPressed), for: .touchUpInside)
        self.addSubview(self.dim)

        self.heading.font = UIFont.systemFont(ofSize: 20.0, weight: .semibold)
        self.newButton.titleLabel?.font = UIFont.systemFont(ofSize: 16.0, weight: .medium)
        self.newButton.contentHorizontalAlignment = .leading
        self.newButton.addTarget(self, action: #selector(self.newPressed), for: .touchUpInside)

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.separatorStyle = .none
        self.tableView.rowHeight = 44.0
        self.tableView.backgroundColor = .clear
        self.tableView.register(AyuGramAssistantChatCell.self, forCellReuseIdentifier: "chat")

        self.panel.clipsToBounds = true
        self.panel.addSubview(self.heading)
        self.panel.addSubview(self.newButton)
        self.panel.addSubview(self.line)
        self.panel.addSubview(self.tableView)
        self.addSubview(self.panel)

        self.update(theme: theme, locale: locale)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(theme: PresentationTheme, locale: String) {
        self.theme = theme
        self.locale = locale
        self.panel.backgroundColor = theme.list.plainBackgroundColor
        self.heading.textColor = theme.list.itemPrimaryTextColor
        self.heading.text = i18n("Ayu.AIChats", locale)
        self.line.backgroundColor = theme.list.itemPlainSeparatorColor
        self.newButton.tintColor = theme.list.itemAccentColor
        self.newButton.setTitle("  " + i18n("Ayu.AINewChat", locale), for: .normal)
        self.newButton.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17.0, weight: .medium)), for: .normal)
        self.tableView.reloadData()
    }

    func reload() {
        self.tableView.reloadData()
    }

    func layout(size: CGSize, left: CGFloat, bottom: CGFloat) {
        self.dim.frame = CGRect(origin: CGPoint(), size: size)
        let width = min(320.0, floor(size.width * 0.82)) + left
        self.panelWidth = width
        self.panel.frame = CGRect(x: self.isOpen ? 0.0 : -width, y: 0.0, width: width, height: size.height)
        self.heading.frame = CGRect(x: left + 20.0, y: 14.0, width: width - left - 40.0, height: 26.0)
        self.newButton.frame = CGRect(x: left + 20.0, y: 52.0, width: width - left - 40.0, height: 44.0)
        self.line.frame = CGRect(x: 0.0, y: 108.0, width: width, height: 1.0 / UIScreen.main.scale)
        self.tableView.frame = CGRect(x: left, y: 109.0, width: width - left, height: max(0.0, size.height - 109.0))
        self.tableView.contentInset = UIEdgeInsets(top: 6.0, left: 0.0, bottom: bottom + 6.0, right: 0.0)
    }

    func setOpen(_ open: Bool) {
        guard self.isOpen != open else {
            return
        }
        self.isOpen = open
        if open {
            self.isHidden = false
            self.tableView.reloadData()
        }
        UIView.animate(withDuration: 0.25, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
            self.dim.alpha = open ? 1.0 : 0.0
            self.panel.frame.origin.x = open ? 0.0 : -self.panelWidth
        }, completion: { _ in
            if !self.isOpen {
                self.isHidden = true
            }
        })
    }

    @objc private func dimPressed() {
        self.setOpen(false)
    }

    @objc private func newPressed() {
        self.created?()
    }

    private func chat(at indexPath: IndexPath) -> AyuGramAssistantChat? {
        let chats = AyuGramAssistantStore.shared.chats
        return indexPath.row < chats.count ? chats[indexPath.row] : nil
    }

    private func name(_ chat: AyuGramAssistantChat) -> String {
        return chat.title.isEmpty ? i18n("Ayu.AINewChat", self.locale) : chat.title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return AyuGramAssistantStore.shared.chats.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat", for: indexPath)
        if let cell = cell as? AyuGramAssistantChatCell, let chat = self.chat(at: indexPath) {
            cell.update(title: self.name(chat), active: chat === AyuGramAssistantStore.shared.current, theme: self.theme)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let chat = self.chat(at: indexPath) {
            self.selected?(chat)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chat = self.chat(at: indexPath) else {
            return nil
        }
        let action = UIContextualAction(style: .destructive, title: i18n("Ayu.AIDelete", self.locale), handler: { [weak self] _, _, completion in
            self?.deleted?(chat)
            completion(true)
        })
        return UISwipeActionsConfiguration(actions: [action])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let chat = self.chat(at: indexPath) else {
            return nil
        }
        let renameTitle = i18n("Ayu.AIRename", self.locale)
        let deleteTitle = i18n("Ayu.AIDelete", self.locale)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
            return UIMenu(title: "", children: [
                UIAction(title: renameTitle, image: UIImage(systemName: "pencil"), handler: { _ in
                    self?.renameRequested?(chat)
                }),
                UIAction(title: deleteTitle, image: UIImage(systemName: "trash"), attributes: .destructive, handler: { _ in
                    self?.deleted?(chat)
                })
            ])
        })
    }
}

private final class AyuGramAssistantNode: ASDisplayNode, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, PHPickerViewControllerDelegate {
    private var presentationData: PresentationData
    private let presentNative: (UIViewController) -> Void
    private let titleUpdated: (String?) -> Void
    private let drawer: AyuGramAssistantDrawer
    private let tableView = UITableView(frame: CGRect(), style: .plain)
    private let inputBar = UIView()
    private let separator = UIView()
    private let field = UITextField()
    private let attachButton = UIButton(type: .system)
    private let micButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let preview = UIImageView()
    private let removeButton = UIButton(type: .system)
    private let emptyView = UIView()
    private let emptyIcon = UIImageView()
    private let emptyLabel = UILabel()
    private var suggestionButtons: [UIButton] = []
    private var loading = false
    private var attachment: (UIImage, String)?
    private var recorder: AVAudioRecorder?
    private var recordingFile: URL?
    private var validLayout: (ContainerViewLayout, CGFloat)?

    init(presentationData: PresentationData, presentNative: @escaping (UIViewController) -> Void, titleUpdated: @escaping (String?) -> Void) {
        self.presentationData = presentationData
        self.presentNative = presentNative
        self.titleUpdated = titleUpdated
        self.drawer = AyuGramAssistantDrawer(theme: presentationData.theme, locale: presentationData.strings.baseLanguageCode)
        super.init()

        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.separatorStyle = .none
        self.tableView.keyboardDismissMode = .interactive
        self.tableView.rowHeight = UITableView.automaticDimension
        self.tableView.estimatedRowHeight = 60.0
        self.tableView.contentInsetAdjustmentBehavior = .never
        self.tableView.contentInset = UIEdgeInsets(top: 8.0, left: 0.0, bottom: 8.0, right: 0.0)
        self.tableView.register(AyuGramAssistantCell.self, forCellReuseIdentifier: "message")
        self.view.addSubview(self.tableView)

        self.emptyIcon.image = UIImage(systemName: "sparkles", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44.0, weight: .medium))
        self.emptyIcon.contentMode = .center
        self.emptyLabel.textAlignment = .center
        self.emptyLabel.numberOfLines = 0
        self.emptyLabel.font = UIFont.systemFont(ofSize: 15.0)
        self.emptyView.addSubview(self.emptyIcon)
        self.emptyView.addSubview(self.emptyLabel)
        for index in 0 ..< 3 {
            let button = UIButton(type: .system)
            button.tag = index
            button.titleLabel?.font = UIFont.systemFont(ofSize: 15.0)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.layer.cornerRadius = 18.0
            button.layer.cornerCurve = .continuous
            button.addTarget(self, action: #selector(self.suggestionPressed(_:)), for: .touchUpInside)
            self.suggestionButtons.append(button)
            self.emptyView.addSubview(button)
        }
        self.view.addSubview(self.emptyView)

        self.field.font = UIFont.systemFont(ofSize: 16.0)
        self.field.returnKeyType = .send
        self.field.delegate = self
        self.field.layer.cornerRadius = 18.0
        self.field.layer.cornerCurve = .continuous
        self.field.leftView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.field.leftViewMode = .always
        self.field.rightView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 14.0, height: 1.0))
        self.field.rightViewMode = .always

        let symbols = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)
        self.attachButton.setImage(UIImage(systemName: "photo", withConfiguration: symbols), for: .normal)
        self.attachButton.addTarget(self, action: #selector(self.attachPressed), for: .touchUpInside)
        self.micButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: symbols), for: .normal)
        self.micButton.addTarget(self, action: #selector(self.micPressed), for: .touchUpInside)
        self.sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30.0)), for: .normal)
        self.sendButton.addTarget(self, action: #selector(self.sendPressed), for: .touchUpInside)
        self.indicator.hidesWhenStopped = true

        self.preview.contentMode = .scaleAspectFill
        self.preview.clipsToBounds = true
        self.preview.layer.cornerRadius = 10.0
        self.preview.isHidden = true
        self.removeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20.0)), for: .normal)
        self.removeButton.addTarget(self, action: #selector(self.removePressed), for: .touchUpInside)
        self.removeButton.isHidden = true

        self.inputBar.addSubview(self.separator)
        self.inputBar.addSubview(self.preview)
        self.inputBar.addSubview(self.removeButton)
        self.inputBar.addSubview(self.attachButton)
        self.inputBar.addSubview(self.field)
        self.inputBar.addSubview(self.micButton)
        self.inputBar.addSubview(self.sendButton)
        self.inputBar.addSubview(self.indicator)
        self.view.addSubview(self.inputBar)
        self.view.addSubview(self.drawer)

        self.drawer.selected = { [weak self] chat in
            AyuGramAssistantStore.shared.select(chat)
            self?.showCurrent()
        }
        self.drawer.created = { [weak self] in
            AyuGramAssistantStore.shared.startNew()
            self?.showCurrent()
        }
        self.drawer.deleted = { [weak self] chat in
            guard let self else {
                return
            }
            let wasCurrent = chat === AyuGramAssistantStore.shared.current
            AyuGramAssistantStore.shared.delete(chat)
            self.drawer.reload()
            if wasCurrent {
                self.reloadMessages()
            }
        }
        self.drawer.renameRequested = { [weak self] chat in
            self?.rename(chat)
        }

        self.applyTheme()
        self.titleUpdated(self.currentTitle)
    }

    private var currentTitle: String? {
        let title = AyuGramAssistantStore.shared.current.title
        return title.isEmpty ? nil : title
    }

    private func reloadMessages() {
        self.emptyView.isHidden = !ayuGramAssistantMessages.isEmpty
        self.tableView.reloadData()
        self.tableView.layoutIfNeeded()
        self.scrollToBottom(animated: false)
        self.titleUpdated(self.currentTitle)
    }

    private func showCurrent() {
        self.reloadMessages()
        self.drawer.setOpen(false)
    }

    private func rename(_ chat: AyuGramAssistantChat) {
        let strings = self.presentationData.strings
        let alert = UIAlertController(title: i18n("Ayu.AIRename", self.locale), message: nil, preferredStyle: .alert)
        alert.addTextField(configurationHandler: { field in
            field.text = chat.title
            field.autocapitalizationType = .sentences
        })
        alert.addAction(UIAlertAction(title: strings.Common_Cancel, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: strings.Common_OK, style: .default, handler: { [weak self, weak alert] _ in
            guard let self else {
                return
            }
            let title = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                AyuGramAssistantStore.shared.rename(chat, title: title)
                self.drawer.reload()
                self.titleUpdated(self.currentTitle)
            }
        }))
        self.presentNative(alert)
    }

    func toggleChats() {
        self.field.resignFirstResponder()
        self.drawer.setOpen(!self.drawer.isOpen)
    }

    deinit {
        self.recorder?.stop()
        if let recordingFile = self.recordingFile {
            try? FileManager.default.removeItem(at: recordingFile)
        }
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        self.applyTheme()
        self.drawer.update(theme: presentationData.theme, locale: presentationData.strings.baseLanguageCode)
        self.tableView.reloadData()
    }

    private var locale: String {
        return self.presentationData.strings.baseLanguageCode
    }

    private func applyTheme() {
        let theme = self.presentationData.theme
        self.backgroundColor = theme.list.blocksBackgroundColor
        self.tableView.backgroundColor = theme.list.blocksBackgroundColor
        self.inputBar.backgroundColor = theme.list.blocksBackgroundColor
        self.separator.backgroundColor = theme.list.itemBlocksSeparatorColor
        self.field.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.field.textColor = theme.list.itemPrimaryTextColor
        self.field.tintColor = theme.list.itemAccentColor
        self.field.keyboardAppearance = theme.overallDarkAppearance ? .dark : .light
        self.attachButton.tintColor = theme.list.itemSecondaryTextColor
        self.sendButton.tintColor = theme.list.itemAccentColor
        self.removeButton.tintColor = theme.list.itemSecondaryTextColor
        self.indicator.color = theme.list.itemAccentColor
        self.emptyIcon.tintColor = theme.list.itemAccentColor
        self.emptyLabel.textColor = theme.list.itemSecondaryTextColor
        self.emptyLabel.text = i18n("Ayu.AIEmpty", self.locale)
        for (index, button) in self.suggestionButtons.enumerated() {
            button.setTitle(i18n("Ayu.AISuggest\(index + 1)", self.locale), for: .normal)
            button.setTitleColor(theme.list.itemPrimaryTextColor, for: .normal)
            button.backgroundColor = theme.list.itemBlocksBackgroundColor
        }
        self.emptyView.isHidden = !ayuGramAssistantMessages.isEmpty
        self.updateRecordingAppearance()
    }

    private func updateRecordingAppearance() {
        let theme = self.presentationData.theme
        let recording = self.recorder != nil
        self.micButton.tintColor = recording ? theme.list.itemDestructiveColor : theme.list.itemSecondaryTextColor
        self.micButton.setImage(UIImage(systemName: recording ? "stop.circle.fill" : "mic.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)), for: .normal)
        self.field.attributedPlaceholder = NSAttributedString(string: i18n(recording ? "Ayu.AIRecording" : "Ayu.AIPlaceholder", self.locale), attributes: [.foregroundColor: recording ? theme.list.itemDestructiveColor : theme.list.itemPlaceholderTextColor])
        self.field.isEnabled = !recording
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (layout, navigationHeight)
        let size = layout.size
        let bottom = layout.insets(options: [.input]).bottom
        let side = layout.safeInsets.left
        let previewHeight: CGFloat = self.attachment == nil ? 0.0 : 64.0
        let barHeight: CGFloat = 52.0 + previewHeight
        let barFrame = CGRect(x: 0.0, y: size.height - bottom - barHeight, width: size.width, height: barHeight + bottom)
        transition.updateFrame(view: self.inputBar, frame: barFrame)
        self.separator.frame = CGRect(x: 0.0, y: 0.0, width: size.width, height: 1.0 / UIScreen.main.scale)
        self.preview.frame = CGRect(x: side + 14.0, y: 8.0, width: 56.0, height: 56.0)
        self.removeButton.frame = CGRect(x: side + 14.0 + 56.0 - 14.0, y: 0.0, width: 28.0, height: 28.0)
        let row = previewHeight + 6.0
        self.attachButton.frame = CGRect(x: side + 6.0, y: row, width: 40.0, height: 40.0)
        self.sendButton.frame = CGRect(x: size.width - side - 46.0, y: row, width: 40.0, height: 40.0)
        self.micButton.frame = CGRect(x: self.sendButton.frame.minX - 40.0, y: row, width: 40.0, height: 40.0)
        self.indicator.center = self.sendButton.center
        self.field.frame = CGRect(x: self.attachButton.frame.maxX + 4.0, y: row + 2.0, width: max(0.0, self.micButton.frame.minX - self.attachButton.frame.maxX - 8.0), height: 36.0)
        let tableFrame = CGRect(x: 0.0, y: navigationHeight, width: size.width, height: max(0.0, barFrame.minY - navigationHeight))
        transition.updateFrame(view: self.tableView, frame: tableFrame)
        self.emptyView.frame = tableFrame
        self.drawer.frame = CGRect(x: 0.0, y: navigationHeight, width: size.width, height: max(0.0, size.height - navigationHeight))
        self.drawer.layout(size: self.drawer.bounds.size, left: side, bottom: layout.intrinsicInsets.bottom)
        let width = min(tableFrame.width - 48.0, 340.0)
        let contentHeight: CGFloat = 60.0 + 12.0 + 44.0 + 16.0 + 3.0 * 44.0
        var y = max(8.0, floor((tableFrame.height - contentHeight) / 2.0))
        let x = floor((tableFrame.width - width) / 2.0)
        self.emptyIcon.frame = CGRect(x: x, y: y, width: width, height: 60.0)
        y += 72.0
        self.emptyLabel.frame = CGRect(x: x, y: y, width: width, height: 44.0)
        y += 60.0
        for button in self.suggestionButtons {
            button.frame = CGRect(x: x, y: y, width: width, height: 36.0)
            y += 44.0
        }
        self.scrollToBottom(animated: false)
    }

    private func relayout() {
        if let (layout, navigationHeight) = self.validLayout {
            self.containerLayoutUpdated(layout, navigationHeight: navigationHeight, transition: .immediate)
        }
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

    private func setAttachment(_ value: (UIImage, String)?) {
        self.attachment = value
        self.preview.image = value?.0
        self.preview.isHidden = value == nil
        self.removeButton.isHidden = value == nil
        self.relayout()
    }

    private func append(_ message: AyuGramAssistantMessage) {
        self.append(message, to: AyuGramAssistantStore.shared.current)
    }

    private func append(_ message: AyuGramAssistantMessage, to chat: AyuGramAssistantChat) {
        AyuGramAssistantStore.shared.append(message, to: chat)
        self.drawer.reload()
        guard chat === AyuGramAssistantStore.shared.current else {
            return
        }
        self.emptyView.isHidden = true
        self.tableView.reloadData()
        self.tableView.layoutIfNeeded()
        self.scrollToBottom(animated: true)
        self.titleUpdated(self.currentTitle)
    }

    private func submit(text: String) {
        let attachment = self.attachment
        guard !self.loading, !text.isEmpty || attachment != nil else {
            return
        }
        self.field.text = ""
        self.setAttachment(nil)
        let chat = AyuGramAssistantStore.shared.current
        self.append(AyuGramAssistantMessage(outgoing: true, text: text, failed: false, image: attachment?.0, imagePayload: attachment?.1), to: chat)
        self.setLoading(true)
        ayuGramAssistantRequest(messages: chat.messages, locale: self.locale, completion: { [weak self] reply, failure in
            guard let self else {
                return
            }
            self.setLoading(false)
            if let reply {
                self.append(AyuGramAssistantMessage(outgoing: false, text: reply, failed: false), to: chat)
            } else {
                self.append(AyuGramAssistantMessage(outgoing: false, text: failure ?? "", failed: true), to: chat)
            }
        })
    }

    @objc private func sendPressed() {
        self.submit(text: (self.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func suggestionPressed(_ button: UIButton) {
        self.submit(text: i18n("Ayu.AISuggest\(button.tag + 1)", self.locale))
    }

    @objc private func removePressed() {
        self.setAttachment(nil)
    }

    @objc private func attachPressed() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        self.view.endEditing(true)
        self.presentNative(picker)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true, completion: nil)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
            return
        }
        let _ = provider.loadObject(ofClass: UIImage.self, completionHandler: { [weak self] object, _ in
            guard let image = object as? UIImage, let prepared = ayuGramAssistantPrepare(image: image) else {
                return
            }
            DispatchQueue.main.async {
                self?.setAttachment(prepared)
            }
        })
    }

    @objc private func micPressed() {
        if self.recorder != nil {
            self.finishRecording()
            return
        }
        guard !self.loading else {
            return
        }
        AVAudioSession.sharedInstance().requestRecordPermission({ [weak self] granted in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if granted {
                    self.startRecording()
                } else {
                    self.append(AyuGramAssistantMessage(outgoing: false, text: i18n("Ayu.AIMicDenied", self.locale), failed: true))
                }
            }
        })
    }

    private func startRecording() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ayugram-assistant-" + UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32000
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: file, settings: settings)
            guard recorder.record(forDuration: 120.0) else {
                throw NSError(domain: "AyuGramAssistant", code: 1)
            }
            self.recorder = recorder
            self.recordingFile = file
            self.view.endEditing(true)
            self.updateRecordingAppearance()
        } catch {
            self.append(AyuGramAssistantMessage(outgoing: false, text: i18n("Ayu.AIError", self.locale), failed: true))
        }
    }

    private func finishRecording() {
        guard let recorder = self.recorder, let file = self.recordingFile else {
            return
        }
        recorder.stop()
        self.recorder = nil
        self.recordingFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        self.updateRecordingAppearance()
        self.setLoading(true)
        ayuGramAssistantTranscribe(file: file, locale: self.locale, completion: { [weak self] text, failure in
            try? FileManager.default.removeItem(at: file)
            guard let self else {
                return
            }
            self.setLoading(false)
            if let text {
                self.submit(text: text)
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
        guard indexPath.row < ayuGramAssistantMessages.count, !ayuGramAssistantMessages[indexPath.row].text.isEmpty else {
            return nil
        }
        let text = ayuGramAssistantMessages[indexPath.row].text
        let title = i18n("Ayu.AICopy", self.locale)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { _ in
            return UIMenu(title: "", children: [UIAction(title: title, image: UIImage(systemName: "doc.on.doc"), handler: { _ in
                UIPasteboard.general.string = text
            })])
        })
    }
}

private final class AyuGramAssistantController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private var node: AyuGramAssistantNode {
        return self.displayNode as! AyuGramAssistantNode
    }

    init(context: AccountContext) {
        self.context = context
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))

        let locale = presentationData.strings.baseLanguageCode
        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.title = i18n("Ayu.Assistant", locale)
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: ayuGramAssistantIcon("sidebar.left", color: presentationData.theme.rootController.navigationBar.accentTextColor), style: .plain, target: self, action: #selector(self.chatsPressed))

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
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: ayuGramAssistantIcon("sidebar.left", color: presentationData.theme.rootController.navigationBar.accentTextColor), style: .plain, target: self, action: #selector(self.chatsPressed))
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

    @objc private func chatsPressed() {
        if self.isNodeLoaded {
            self.node.toggleChats()
        }
    }

    override func loadDisplayNode() {
        let context = self.context
        self.displayNode = AyuGramAssistantNode(presentationData: self.presentationData, presentNative: { controller in
            context.sharedContext.mainWindow?.presentNative(controller)
        }, titleUpdated: { [weak self] title in
            guard let self else {
                return
            }
            self.title = title ?? i18n("Ayu.Assistant", self.presentationData.strings.baseLanguageCode)
        })
        self.displayNodeDidLoad()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.node.containerLayoutUpdated(layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}

public func ayuGramAssistantController(context: AccountContext) -> ViewController {
    return AyuGramAssistantController(context: context)
}
