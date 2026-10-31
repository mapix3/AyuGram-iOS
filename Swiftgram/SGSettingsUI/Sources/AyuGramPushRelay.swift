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
    private static let offeredDefaultsKey = "ayuGram.pushRelay.offered"
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

    /// True the first time it is asked on an install without a Bark key.
    static func shouldOffer() -> Bool {
        guard (barkKey ?? "").isEmpty, !UserDefaults.standard.bool(forKey: offeredDefaultsKey) else {
            return false
        }
        UserDefaults.standard.set(true, forKey: offeredDefaultsKey)
        return true
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

    private static func subscription(barkKey: String) -> String {
        let keys = subscriptionKeys()
        let endpoint = baseURL + "/p/" + base64url(keys + Data(barkKey.utf8))
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
                var request: Signal<String?, NoError> = .single(nil)
                if let previous, previous != current {
                    request = engine.accountData.ayuUnregisterWebPush(subscription: previous)
                    |> map { _ -> String? in
                        return nil
                    }
                }
                if let current {
                    request = request
                    |> take(1)
                    |> mapToSignal { _ -> Signal<String?, NoError> in
                        return engine.accountData.ayuRegisterWebPush(subscription: current)
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
    private static var activityTimer: Foundation.Timer?
    private static let activitySeconds = 90
    private static let activityInterval: TimeInterval = 45.0

    static func renew(context: AccountContext) {
        if let barkKey, !barkKey.isEmpty {
            let current = subscription(barkKey: barkKey)
            let _ = (engines(context: context)
            |> mapToSignal { engines -> Signal<Void, NoError> in
                if engines.isEmpty {
                    return .single(Void())
                }
                return combineLatest(engines.map { engine -> Signal<Void, NoError> in
                    return engine.accountData.ayuRegisterWebPush(subscription: current)
                    |> map { _ -> Void in
                        return Void()
                    }
                    |> take(1)
                })
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
            }),
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { _ in
                updateActivity()
            }),
            NotificationCenter.default.addObserver(forName: Notification.Name("AyuGramChatOpened"), object: nil, queue: .main, using: { notification in
                if let peerId = notification.userInfo?["peerId"] as? EnginePeer.Id {
                    chatOpened(peerId: peerId)
                }
            })
        ]
        updateActivity()
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

/// Once per install without a Bark key: a sideloaded AyuGram gets notifications only through Bark.
func ayuGramOfferBarkIfNeeded(context: AccountContext) {
    guard AyuGramPushRelay.shouldOffer() else {
        return
    }
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let present: (ViewController) -> Void = { [weak context] controller in
        context?.sharedContext.mainWindow?.present(controller, on: .root)
    }
    let text = i18n(AyuGramPushRelay.isBarkInstalled ? "Ayu.BarkFixConnect" : "Ayu.BarkFixInstall", locale)
    // After the root controller is in the window.
    Queue.mainQueue().after(1.0) {
        present(textAlertController(context: context, title: i18n("Ayu.BarkFixTitle", locale), text: text, actions: [
            TextAlertAction(type: .genericAction, title: data.strings.Common_No, action: {}),
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Yes, action: {
                ayuGramSetUpBark(context: context, present: present)
            })
        ]))
    }
}
