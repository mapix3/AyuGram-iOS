import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

public enum AyuPeekOnlineResult: Equatable {
    /// The exact last seen time is now shown; `bridge` names the other account that saw it,
    /// nil when it came from briefly opening this account's own last seen setting.
    case peeked(bridge: String?)
    case alreadyVisible
    case hidden
}

private func ayuPeekPresence(_ users: [Api.User], peerId: PeerId) -> TelegramUserPresence? {
    for user in users where user.peerId == peerId {
        return TelegramUserPresence(apiUser: user)
    }
    return nil
}

private func ayuPeekIsExact(_ presence: TelegramUserPresence?) -> Bool {
    if let presence, case .present = presence.status {
        return true
    }
    return false
}

private func ayuPeekIsHiddenByMe(_ presence: TelegramUserPresence?) -> Bool {
    guard let presence else {
        return false
    }
    switch presence.status {
    case let .recently(isHidden), let .lastWeek(isHidden), let .lastMonth(isHidden):
        return isHidden
    default:
        return false
    }
}

/// Completes with one value after `signal` completes, whatever it emitted.
private func ayuPeekAfter(_ signal: Signal<Void, NoError>) -> Signal<Void, NoError> {
    return signal |> reduceLeft(value: Void(), f: { _, _ in
        return Void()
    })
}

private func ayuPeekStore(account: Account, peerId: PeerId, presence: TelegramUserPresence) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        transaction.updatePeerPresencesInternal(presences: [peerId: presence], merge: { _, updated in
            return updated
        })
    }
}

/// The user's status as `account` sees it, looked up by its own access hash or by username.
private func ayuPeekFetch(account: Account, peerId: PeerId, username: String?) -> Signal<TelegramUserPresence?, NoError> {
    return account.postbox.transaction { transaction -> Api.InputUser? in
        return transaction.getPeer(peerId).flatMap(apiInputUser)
    }
    |> mapToSignal { inputUser -> Signal<TelegramUserPresence?, NoError> in
        if let inputUser {
            return account.network.request(Api.functions.users.getUsers(id: [inputUser]))
            |> map { users -> TelegramUserPresence? in
                return ayuPeekPresence(users, peerId: peerId)
            }
            |> `catch` { _ -> Signal<TelegramUserPresence?, NoError> in
                return .single(nil)
            }
        }
        guard let username, !username.isEmpty else {
            return .single(nil)
        }
        return account.network.request(Api.functions.contacts.resolveUsername(flags: 0, username: username, referer: nil))
        |> map { result -> TelegramUserPresence? in
            switch result {
            case let .resolvedPeer(resolvedPeerData):
                return ayuPeekPresence(resolvedPeerData.users, peerId: peerId)
            }
        }
        |> `catch` { _ -> Signal<TelegramUserPresence?, NoError> in
            return .single(nil)
        }
    }
}

private func ayuPeekAccountName(_ account: Account) -> Signal<String, NoError> {
    return account.postbox.transaction { transaction -> String in
        guard let user = transaction.getPeer(account.peerId) as? TelegramUser else {
            return ""
        }
        let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (user.username ?? "") : name
    }
}

/// Opens this account's last seen setting to everybody for one request and restores it exactly,
/// whatever the request returns.
private func ayuPeekByInversion(account: Account, peerId: PeerId) -> Signal<TelegramUserPresence?, NoError> {
    return account.network.request(Api.functions.account.getPrivacy(key: .inputPrivacyKeyStatusTimestamp))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.account.PrivacyRules?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<TelegramUserPresence?, NoError> in
        guard let result else {
            return .single(nil)
        }
        var peers: [SelectivePrivacyPeer] = []
        let original: SelectivePrivacySettings
        switch result {
        case let .privacyRules(privacyRulesData):
            for user in privacyRulesData.users {
                peers.append(SelectivePrivacyPeer(peer: TelegramUser(user: user), participantCount: nil))
            }
            for chat in privacyRulesData.chats {
                if let peer = parseTelegramGroupOrChannel(chat: chat) {
                    peers.append(SelectivePrivacyPeer(peer: peer, participantCount: nil))
                }
            }
            var peerMap: [PeerId: SelectivePrivacyPeer] = [:]
            for peer in peers {
                peerMap[peer.peer.id] = peer
            }
            original = SelectivePrivacySettings(apiRules: privacyRulesData.rules, peers: peerMap)
        }
        let storePeers = account.postbox.transaction { transaction -> Void in
            updatePeersCustom(transaction: transaction, peers: peers.map { $0.peer }, update: { _, updated in
                return updated
            })
        }
        let open = _internal_updateSelectiveAccountPrivacySettings(account: account, type: .presence, settings: .enableEveryone(disableFor: [:]))
        let restore = _internal_updateSelectiveAccountPrivacySettings(account: account, type: .presence, settings: original)
        return ayuPeekAfter(storePeers)
        |> mapToSignal { _ -> Signal<Void, NoError> in
            return ayuPeekAfter(open)
        }
        |> mapToSignal { _ -> Signal<TelegramUserPresence?, NoError> in
            return ayuPeekFetch(account: account, peerId: peerId, username: nil)
            |> take(1)
        }
        |> mapToSignal { presence -> Signal<TelegramUserPresence?, NoError> in
            return ayuPeekAfter(restore)
            |> map { _ -> TelegramUserPresence? in
                return presence
            }
        }
    }
}

func _internal_ayuPeekOnline(account: Account, peerId: PeerId, bridges: [Account]) -> Signal<AyuPeekOnlineResult, NoError> {
    guard peerId.namespace == Namespaces.Peer.CloudUser, peerId != account.peerId else {
        return .single(.hidden)
    }
    let username = account.postbox.transaction { transaction -> String? in
        return (transaction.getPeer(peerId) as? TelegramUser)?.addressName
    }
    return username
    |> mapToSignal { username -> Signal<AyuPeekOnlineResult, NoError> in
        let bridges = bridges.filter { $0.peerId != account.peerId && $0.peerId != peerId }
        func tryBridges(_ remaining: ArraySlice<Account>) -> Signal<AyuPeekOnlineResult?, NoError> {
            guard let bridge = remaining.first else {
                return .single(nil)
            }
            return ayuPeekFetch(account: bridge, peerId: peerId, username: username)
            |> take(1)
            |> mapToSignal { presence -> Signal<AyuPeekOnlineResult?, NoError> in
                guard let presence, ayuPeekIsExact(presence) else {
                    return tryBridges(remaining.dropFirst())
                }
                return ayuPeekAccountName(bridge)
                |> mapToSignal { name -> Signal<AyuPeekOnlineResult?, NoError> in
                    return ayuPeekStore(account: account, peerId: peerId, presence: presence)
                    |> map { _ -> AyuPeekOnlineResult? in
                        return .peeked(bridge: name)
                    }
                }
            }
        }
        return ayuPeekFetch(account: account, peerId: peerId, username: nil)
        |> take(1)
        |> mapToSignal { own -> Signal<AyuPeekOnlineResult, NoError> in
            if let own, ayuPeekIsExact(own) {
                return ayuPeekStore(account: account, peerId: peerId, presence: own)
                |> map { _ -> AyuPeekOnlineResult in
                    return .alreadyVisible
                }
            }
            return tryBridges(bridges[...])
            |> mapToSignal { bridged -> Signal<AyuPeekOnlineResult, NoError> in
                if let bridged {
                    return .single(bridged)
                }
                guard ayuPeekIsHiddenByMe(own) else {
                    return .single(.hidden)
                }
                return ayuPeekByInversion(account: account, peerId: peerId)
                |> mapToSignal { presence -> Signal<AyuPeekOnlineResult, NoError> in
                    guard let presence, ayuPeekIsExact(presence) else {
                        return .single(.hidden)
                    }
                    return ayuPeekStore(account: account, peerId: peerId, presence: presence)
                    |> map { _ -> AyuPeekOnlineResult in
                        return .peeked(bridge: nil)
                    }
                }
            }
        }
    }
}
