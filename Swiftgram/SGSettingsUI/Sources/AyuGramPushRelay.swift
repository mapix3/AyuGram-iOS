import Foundation
import UIKit
import CryptoKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import PromptUI
import SGSimpleSettings
import SGStrings

/// Notifications for a sideloaded AyuGram. Telegram holds no APNs key for this app, so instead
/// every logged-in account registers a Telegram Web Push subscription whose endpoint is the
/// AyuGram push relay (`push-relay/worker.js`). The endpoint carries this device's subscription
/// keys and the Bark key; the relay decrypts each push and hands it to the Bark app.
enum AyuGramPushRelay {
    static let baseURL = "https://ayugram-push.ayugram-status.workers.dev"

    static let barkAppStoreURL = URL(string: "https://apps.apple.com/app/id1403753865")!

    private static let barkKeyDefaultsKey = "ayuGram.pushRelay.barkKey"
    /// Set once the "Fix notifications" dialog has been shown.
    private static let keysDefaultsKey = "ayuGram.pushRelay.keys"
    /// The subscription last registered, so changing the key unsubscribes the old one.
    private static let subscriptionDefaultsKey = "ayuGram.pushRelay.subscription"

    static var barkKey: String? {
        return UserDefaults.standard.string(forKey: barkKeyDefaultsKey)
    }

    /// Bark's `bark` scheme is listed in LSApplicationQueriesSchemes.
    static var isBarkInstalled: Bool {
        return URL(string: "bark://").map { UIApplication.shared.canOpenURL($0) } == true
    }

    /// The key from whatever the Bark app lets you copy: the key itself, a link
    /// (`https://api.day.app/KEY/...`), a `GET` line, a `curl` command or its JSON body
    /// (`"device_key": "KEY"`). Returns "" for empty input and nil when no key is found.
    static func parseBarkKey(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return ""
        }
        let patterns = [
            "\"device_key\"\\s*:\\s*\"([A-Za-z0-9]+)\"",
            "device_key=([A-Za-z0-9]+)",
            "https?://[^/\\s\"']+/([A-Za-z0-9]+)(?=[/?#\\s\"']|$)"
        ]
        var candidates: [String] = []
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            for match in expression.matches(in: text, range: range) {
                if let captured = Range(match.range(at: 1), in: text) {
                    candidates.append(String(text[captured]))
                }
            }
        }
        if candidates.isEmpty, !text.contains("://") {
            candidates.append(text.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
        return candidates.first(where: isBarkKey)
    }

    private static func isBarkKey(_ key: String) -> Bool {
        guard key.count >= 8, key.count <= 64, key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else {
            return false
        }
        // Bark's settings also show the 64-digit APNs device token, which is not the key.
        if key.count == 64, key.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) {
            return false
        }
        return true
    }

    /// Private key d (32) | public key (65, uncompressed) | auth secret (16), made once per install.
    private static func subscriptionKeys() -> Data {
        if let keys = UserDefaults.standard.data(forKey: keysDefaultsKey), keys.count == 113 {
            return keys
        }
        let privateKey = P256.KeyAgreement.PrivateKey()
        let auth = SymmetricKey(size: .init(bitCount: 128)).withUnsafeBytes { Data($0) }
        let keys = privateKey.rawRepresentation + privateKey.publicKey.x963Representation + auth
        UserDefaults.standard.set(keys, forKey: keysDefaultsKey)
        return keys
    }

    private static func base64url(_ data: Data) -> String {
        return data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static let taggedDefaultsKey = "ayuGram.pushRelay.tagged"

    private static func subscription(barkKey: String, account: EnginePeer.Id? = nil) -> String {
        let keys = subscriptionKeys()
        let endpoint = baseURL + "/p/" + base64url(keys + Data(barkKey.utf8)) + (account.map { "?a=" + ayuGramPushAccountTag($0) } ?? "")
        let json: [String: Any] = ["endpoint": endpoint, "keys": ["p256dh": base64url(keys.subdata(in: 32 ..< 97)), "auth": base64url(keys.subdata(in: 97 ..< 113))]]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func engines(context: AccountContext) -> Signal<[TelegramEngine], NoError> {
        return context.sharedContext.activeAccountContexts
        |> take(1)
        |> map { _, accounts, _ in
            return accounts.map { $0.1.engine }
        }
    }

    /// Saves the Bark key ("" turns notifications off) and subscribes every logged-in account.
    /// Completes with Telegram's error, if any.
    static func apply(context: AccountContext, barkKey: String, completion: @escaping (String?) -> Void) {
        let previous = UserDefaults.standard.string(forKey: subscriptionDefaultsKey)
        let previousKey = UserDefaults.standard.string(forKey: barkKeyDefaultsKey)
        let current = barkKey.isEmpty ? nil : subscription(barkKey: barkKey)
        if barkKey.isEmpty {
            UserDefaults.standard.removeObject(forKey: barkKeyDefaultsKey)
            UserDefaults.standard.removeObject(forKey: subscriptionDefaultsKey)
        } else {
            UserDefaults.standard.set(barkKey, forKey: barkKeyDefaultsKey)
            UserDefaults.standard.set(current, forKey: subscriptionDefaultsKey)
        }
        let _ = (engines(context: context)
        |> mapToSignal { engines -> Signal<String?, NoError> in
            if engines.isEmpty {
                return .single(nil)
            }
            var requests: [Signal<String?, NoError>] = []
            for engine in engines {
                let account = engine.account.peerId
                var stale: [String] = []
                if let previous {
                    stale.append(previous)
                }
                if let previousKey, !previousKey.isEmpty, previousKey != barkKey {
                    stale.append(subscription(barkKey: previousKey, account: account))
                }
                if current != nil {
                    stale.append(subscription(barkKey: barkKey))
                }
                var request: Signal<String?, NoError> = .single(nil)
                for old in Set(stale) {
                    request = request
                    |> take(1)
                    |> mapToSignal { _ -> Signal<String?, NoError> in
                        return engine.accountData.ayuUnregisterWebPush(subscription: old)
                        |> map { _ -> String? in
                            return nil
                        }
                        |> take(1)
                    }
                }
                if current != nil {
                    let tagged = subscription(barkKey: barkKey, account: account)
                    request = request
                    |> take(1)
                    |> mapToSignal { _ -> Signal<String?, NoError> in
                        return engine.accountData.ayuRegisterWebPush(subscription: tagged)
                    }
                }
                requests.append(request |> take(1))
            }
            return combineLatest(requests)
            |> map { errors -> String? in
                return errors.compactMap { $0 }.first
            }
        }
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { error in
            completion(error)
            updateActivity()
        })
    }

    private final class BackgroundTask {
        var id: UIBackgroundTaskIdentifier = .invalid
    }

    private static var activityObservers: [NSObjectProtocol] = []
    private static var openChat: EnginePeer.Id?
    private static var activityTimer: Foundation.Timer?
    private static let activitySeconds = 90
    private static let activityInterval: TimeInterval = 45.0

    static func renew(context: AccountContext) {
        collectContext = context
        if let barkKey, !barkKey.isEmpty {
            let legacy = subscription(barkKey: barkKey)
            let migrated = UserDefaults.standard.bool(forKey: taggedDefaultsKey)
            let _ = (engines(context: context)
            |> mapToSignal { engines -> Signal<Void, NoError> in
                if engines.isEmpty {
                    return .single(Void())
                }
                return combineLatest(engines.map { engine -> Signal<Void, NoError> in
                    let tagged = subscription(barkKey: barkKey, account: engine.account.peerId)
                    let cleanup: Signal<Void, NoError> = migrated ? .single(Void()) : (engine.accountData.ayuUnregisterWebPush(subscription: legacy)
                    |> map { _ -> Void in
                        return Void()
                    }
                    |> take(1))
                    return cleanup
                    |> mapToSignal { _ -> Signal<Void, NoError> in
                        return engine.accountData.ayuRegisterWebPush(subscription: tagged)
                        |> map { _ -> Void in
                            return Void()
                        }
                        |> take(1)
                    }
                })
                |> afterNext { _ in
                    UserDefaults.standard.set(true, forKey: taggedDefaultsKey)
                }
                |> map { _ -> Void in
                    return Void()
                }
            }
            |> take(1)).startStandalone()
        }
        for observer in activityObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        activityObservers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { _ in
                updateActivity()
                if let openChat {
                    chatOpened(peerId: openChat)
                }
                Queue.mainQueue().after(2.0, {
                    clearReadChats()
                })
                Queue.mainQueue().after(8.0, {
                    collectDeleted()
                })
            }),
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { _ in
                updateActivity()
            }),
            NotificationCenter.default.addObserver(forName: Notification.Name("AyuGramChatOpened"), object: nil, queue: .main, using: { notification in
                if let peerId = notification.userInfo?["peerId"] as? EnginePeer.Id {
                    openChat = peerId
                    chatOpened(peerId: peerId)
                }
            }),
            NotificationCenter.default.addObserver(forName: Notification.Name("AyuGramChatClosed"), object: nil, queue: .main, using: { notification in
                if let peerId = notification.userInfo?["peerId"] as? EnginePeer.Id, openChat == peerId {
                    openChat = nil
                    chatOpened(peerId: peerId)
                }
            })
        ]
        Queue.mainQueue().after(4.0, {
            clearReadChats()
        })
        updateActivity()
        Queue.mainQueue().after(10.0, {
            collectDeleted()
        })
    }

    private static weak var collectContext: AccountContext?
    private static var collecting = false
    private static let ackDefaultsKey = "ayuGram.pushRelay.ack"

    /// Fetches messages the relay saw deleted while AyuGram was closed and keeps them.
    static func collectDeleted() {
        guard let context = collectContext, let barkKey, !barkKey.isEmpty, AyuGramSettings.shared.snapshot.messageHistory, !collecting else {
            return
        }
        let ack = UserDefaults.standard.stringArray(forKey: ackDefaultsKey) ?? []
        let json: [String: Any] = ["barkKey": barkKey, "ack": ack]
        guard let url = URL(string: baseURL + "/deleted/" + activityId(barkKey: barkKey)), let body = try? JSONSerialization.data(withJSONObject: json) else {
            return
        }
        collecting = true
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 20.0
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            DispatchQueue.main.async {
                guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
                    collecting = false
                    return
                }
                UserDefaults.standard.removeObject(forKey: ackDefaultsKey)
                let ids = entries.compactMap { $0["id"] as? String }
                if ids.isEmpty {
                    collecting = false
                    return
                }
                keepDeleted(context: context, messages: decodeDeleted(entries), completion: {
                    UserDefaults.standard.set(ids, forKey: ackDefaultsKey)
                    collecting = false
                    if ids.count >= 300 {
                        collectDeleted()
                    }
                })
            }
        }).resume()
    }

    private static func base64urlDecode(_ text: String) -> Data? {
        var value = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 {
            value += "="
        }
        return Data(base64Encoded: value)
    }

    /// Removes the notifications of chats that are read by now, or where the last message is
    /// the user's own: read on another device, or answered from anywhere.
    static func clearReadChats() {
        guard let context = collectContext, let barkKey, !barkKey.isEmpty, let url = URL(string: baseURL + "/shown/" + activityId(barkKey: barkKey)), let body = try? JSONSerialization.data(withJSONObject: ["barkKey": barkKey]) else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15.0
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return
            }
            for entry in entries {
                guard let chat = entry["chat"] as? String, let peerId = relayPeerId(chat: chat) else {
                    continue
                }
                let maxId = (entry["maxId"] as? NSNumber)?.int32Value ?? 0
                let _ = (context.engine.data.get(
                    TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId),
                    TelegramEngine.EngineData.Item.Messages.TopMessage(id: peerId)
                )
                |> deliverOnMainQueue).startStandalone(next: { counters, topMessage in
                    var answered = false
                    if let topMessage, !topMessage.flags.contains(.Incoming), topMessage.id.id >= maxId {
                        answered = true
                    }
                    if !counters.isUnread || answered {
                        chatOpened(peerId: peerId)
                    }
                })
            }
        }).resume()
    }

    private static func relayPeerId(chat: String) -> EnginePeer.Id? {
        let kinds: [(String, EnginePeer.Id.Namespace)] = [("user", Namespaces.Peer.CloudUser), ("chat", Namespaces.Peer.CloudGroup), ("channel", Namespaces.Peer.CloudChannel)]
        for (prefix, namespace) in kinds where chat.hasPrefix(prefix) {
            if let value = Int64(chat.dropFirst(prefix.count)) {
                return EnginePeer.Id(namespace: namespace, id: EnginePeer.Id.Id._internalFromInt64Value(value))
            }
        }
        return nil
    }

    private static func decodeDeleted(_ entries: [[String: Any]]) -> [AyuGramRelayedDeletedMessage] {
        let auth = subscriptionKeys().subdata(in: 97 ..< 113)
        let key = SymmetricKey(data: Data(SHA256.hash(data: Data("ayugram-stash|".utf8) + auth)))
        let now = Int32(Date().timeIntervalSince1970)
        var result: [AyuGramRelayedDeletedMessage] = []
        for entry in entries {
            guard let ivText = entry["iv"] as? String, let sealedText = entry["data"] as? String, let iv = base64urlDecode(ivText), let sealed = base64urlDecode(sealedText), iv.count == 12, sealed.count > 16,
                  let box = try? AES.GCM.SealedBox(combined: iv + sealed), let plain = try? AES.GCM.open(box, using: key),
                  let record = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any],
                  let chat = record["chat"] as? String, let message = (record["msg"] as? NSNumber)?.int32Value, let peerId = relayPeerId(chat: chat) else {
                continue
            }
            let authorId = (record["from"] as? String).flatMap { Int64($0) }.map { EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value($0)) }
            let text = (record["text"] as? String) ?? ""
            let date = (record["date"] as? NSNumber)?.int32Value ?? now
            let deletedAt = (entry["deletedAt"] as? NSNumber)?.int32Value ?? now
            result.append(AyuGramRelayedDeletedMessage(peerId: peerId, messageId: message, authorId: authorId, text: text, timestamp: date, deletedAt: deletedAt))
        }
        return result
    }

    private static func keepDeleted(context: AccountContext, messages: [AyuGramRelayedDeletedMessage], completion: @escaping () -> Void) {
        let _ = (engines(context: context)
        |> mapToSignal { engines -> Signal<Void, NoError> in
            var signal: Signal<[AyuGramRelayedDeletedMessage], NoError> = .single(messages)
            for engine in engines {
                signal = signal
                |> mapToSignal { remaining -> Signal<[AyuGramRelayedDeletedMessage], NoError> in
                    if remaining.isEmpty {
                        return .single([])
                    }
                    return engine.ayuGramKeepRelayedDeletedMessages(remaining)
                }
            }
            return signal
            |> map { _ -> Void in
                return Void()
            }
        }
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { _ in
            completion()
        })
    }

    private static func updateActivity() {
        activityTimer?.invalidate()
        activityTimer = nil
        guard let barkKey, !barkKey.isEmpty else {
            return
        }
        if UIApplication.shared.applicationState == .background {
            sendActivity(barkKey: barkKey, seconds: 0)
            return
        }
        sendActivity(barkKey: barkKey, seconds: activitySeconds)
        let timer = Foundation.Timer(timeInterval: activityInterval, repeats: true, block: { _ in
            guard let barkKey = AyuGramPushRelay.barkKey, !barkKey.isEmpty, UIApplication.shared.applicationState != .background else {
                return
            }
            sendActivity(barkKey: barkKey, seconds: activitySeconds)
        })
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer
    }

    private static func activityId(barkKey: String) -> String {
        return base64url(Data(SHA256.hash(data: Data(("ayugram-active|" + barkKey).utf8))))
    }

    private static func sendActivity(barkKey: String, seconds: Int) {
        post(path: "/active/" + activityId(barkKey: barkKey), body: Data(String(seconds).utf8))
    }

    static func chatOpened(peerId: EnginePeer.Id) {
        guard let barkKey, !barkKey.isEmpty else {
            return
        }
        let kind: String
        switch peerId.namespace {
        case Namespaces.Peer.CloudUser:
            kind = "user"
        case Namespaces.Peer.CloudGroup:
            kind = "chat"
        case Namespaces.Peer.CloudChannel:
            kind = "channel"
        default:
            return
        }
        let json: [String: Any] = ["barkKey": barkKey, "chat": kind + String(peerId.id._internalGetInt64Value())]
        guard let body = try? JSONSerialization.data(withJSONObject: json) else {
            return
        }
        post(path: "/seen/" + activityId(barkKey: barkKey), body: body)
    }

    private static func post(path: String, body: Data) {
        guard let url = URL(string: baseURL + path) else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15.0
        let task = BackgroundTask()
        let finish: () -> Void = {
            if task.id != .invalid {
                UIApplication.shared.endBackgroundTask(task.id)
                task.id = .invalid
            }
        }
        task.id = UIApplication.shared.beginBackgroundTask(withName: "AyuGramPushRelay", expirationHandler: finish)
        URLSession.shared.dataTask(with: request, completionHandler: { _, _, _ in
            DispatchQueue.main.async(execute: finish)
        }).resume()
    }
}

/// Asks for the Bark key. When Bark is not found, explains where the key comes from and
/// offers both the App Store and entering the key: LiveContainer and some installers answer
/// app queries with their own list, so an installed Bark can look missing.
func ayuGramSetUpBark(context: AccountContext, present: @escaping (ViewController) -> Void) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let askForKey: () -> Void = {
        present(ayuGramBarkKeyPrompt(context: context, present: present))
    }
    if AyuGramPushRelay.isBarkInstalled {
        askForKey()
        return
    }
    present(textAlertController(context: context, title: i18n("Ayu.BarkFixTitle", locale), text: i18n("Ayu.BarkHowTo", locale), actions: [
        TextAlertAction(type: .genericAction, title: "App Store", action: {
            UIApplication.shared.open(AyuGramPushRelay.barkAppStoreURL, options: [:], completionHandler: nil)
        }),
        TextAlertAction(type: .defaultAction, title: i18n("Ayu.BarkEnterKey", locale), action: askForKey),
        TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {})
    ], actionLayout: .vertical))
}

private func ayuGramBarkKeyPrompt(context: AccountContext, present: @escaping (ViewController) -> Void) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let result: (String) -> Void = { text in
        present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
    }
    return promptController(context: context, text: i18n("Ayu.BarkPrompt", locale), value: AyuGramPushRelay.barkKey ?? "", placeholder: "Bark key", characterLimit: 200, apply: { value in
        guard let value else {
            return
        }
        guard let key = AyuGramPushRelay.parseBarkKey(value) else {
            result(i18n("Ayu.BarkInvalid", locale))
            return
        }
        AyuGramPushRelay.apply(context: context, barkKey: key, completion: { error in
            // Redraws the settings row's title.
            NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
            if key.isEmpty {
                result(i18n("Ayu.BarkDisabled", locale))
            } else if let error {
                result(i18n("Ayu.BarkFailed", locale, error))
            } else {
                result(i18n("Ayu.BarkEnabled", locale))
            }
        })
    })
}

/// A short one-way tag for an account, so the push relay can tell accounts apart without their ids.
public func ayuGramPushAccountTag(_ peerId: EnginePeer.Id) -> String {
    let digest = SHA256.hash(data: Data("ayugram-push-account|\(peerId.toInt64())".utf8))
    return String(digest.map { String(format: "%02x", $0) }.joined().prefix(12))
}
