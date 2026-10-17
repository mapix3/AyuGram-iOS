import Foundation
import UIKit
import CryptoKit
import Display
import SwiftSignalKit
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

    /// The key from a Bark key or from a link the Bark app shows (`https://api.day.app/KEY/...`).
    /// Returns "" for empty input and nil for anything that is not a key.
    static func parseBarkKey(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return ""
        }
        var key = text
        if text.contains("://") {
            guard let url = URL(string: text), let first = url.pathComponents.first(where: { $0 != "/" }) else {
                return nil
            }
            key = first
        }
        let allowed = CharacterSet.alphanumerics
        guard key.count >= 8, key.count <= 64, key.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII }) else {
            return nil
        }
        return key
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
        })
    }

    /// Renews the subscription at launch, also for accounts added since it was set up.
    static func renew(context: AccountContext) {
        guard let barkKey, !barkKey.isEmpty else {
            return
        }
        apply(context: context, barkKey: barkKey, completion: { _ in })
    }
}

/// Asks for the Bark key; without Bark installed, opens its App Store page instead.
/// LiveContainer answers app queries with its own list, which may not include Bark, so
/// there an undetected Bark offers both.
func ayuGramSetUpBark(context: AccountContext, present: @escaping (ViewController) -> Void) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let askForKey: () -> Void = {
        present(ayuGramBarkKeyPrompt(context: context, present: present))
    }
    if AyuGramPushRelay.isBarkInstalled {
        askForKey()
    } else if ayuGramRunsInLiveContainer {
        present(textAlertController(context: context, title: i18n("Ayu.BarkFixTitle", locale), text: i18n("Ayu.BarkFixInstall", locale), actions: [
            TextAlertAction(type: .genericAction, title: "App Store", action: {
                UIApplication.shared.open(AyuGramPushRelay.barkAppStoreURL, options: [:], completionHandler: nil)
            }),
            TextAlertAction(type: .defaultAction, title: i18n("Ayu.BarkEnterKey", locale), action: askForKey)
        ], actionLayout: .vertical))
    } else {
        UIApplication.shared.open(AyuGramPushRelay.barkAppStoreURL, options: [:], completionHandler: nil)
    }
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
