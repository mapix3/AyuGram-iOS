import Foundation
import SwiftSignalKit
import TelegramApi
import MtProtoKit

/// Subscribes this session to Telegram's Web Push (token type 10) with a subscription JSON
/// (`endpoint`, `keys.p256dh`, `keys.auth`). A sideloaded AyuGram has no APNs key on
/// Telegram's side, so notifications reach the AyuGram push relay instead. Returns nil on
/// success, else the server's error.
func _internal_ayuRegisterWebPush(account: Account, subscription: String) -> Signal<String?, NoError> {
    return account.network.request(Api.functions.account.registerDevice(flags: 0, tokenType: 10, token: subscription, appSandbox: .boolFalse, secret: Buffer(data: Data()), otherUids: []))
    |> map { _ -> String? in
        return nil
    }
    |> `catch` { error -> Signal<String?, NoError> in
        return .single(error.errorDescription)
    }
}

func _internal_ayuUnregisterWebPush(account: Account, subscription: String) -> Signal<Never, NoError> {
    return account.network.request(Api.functions.account.unregisterDevice(tokenType: 10, token: subscription, otherUids: []))
    |> `catch` { _ -> Signal<Api.Bool, NoError> in
        return .single(.boolFalse)
    }
    |> ignoreValues
}
