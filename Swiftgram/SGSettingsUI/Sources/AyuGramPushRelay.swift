import Foundation
import CryptoKit
import SwiftSignalKit
import TelegramCore
import AccountContext

/// Notifications for a sideloaded AyuGram. Telegram holds no APNs key for this app, so instead
/// every logged-in account registers a Telegram Web Push subscription whose endpoint is the
/// AyuGram push relay (`push-relay/worker.js`). The endpoint carries this device's subscription
/// keys and the Bark key; the relay decrypts each push and hands it to the Bark app.
enum AyuGramPushRelay {
    static let baseURL = "https://ayugram-push.ayugram-status.workers.dev"

    private static let barkKeyDefaultsKey = "ayuGram.pushRelay.barkKey"
    private static let keysDefaultsKey = "ayuGram.pushRelay.keys"
    /// The subscription last registered, so changing the key unsubscribes the old one.
    private static let subscriptionDefaultsKey = "ayuGram.pushRelay.subscription"

    static var barkKey: String? {
        return UserDefaults.standard.string(forKey: barkKeyDefaultsKey)
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
                    |> mapToSignal { _ -> Signal<String?, NoError> in .complete() }
                    |> then(.single(nil))
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
