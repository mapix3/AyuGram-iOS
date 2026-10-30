import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

/// A chat whose whole history was deleted while Save Deleted Messages kept copies of it.
/// Its kept messages are never pruned until the chat is removed from the list.
public struct AyuGramDeletedChat: Codable, Equatable {
    public let peerId: Int64
    public var title: String
    public var deletedAt: Int32

    public init(peerId: Int64, title: String, deletedAt: Int32) {
        self.peerId = peerId
        self.title = title
        self.deletedAt = deletedAt
    }
}

private struct AyuGramDeletedChats: Codable { var chats: [AyuGramDeletedChat] }
private let ayuGramDeletedChatsKey = applicationSpecificPreferencesKey(0x415957)
/// A deletion of fewer messages than this is never taken for a deleted chat.
private let ayuGramDeletedChatMinimum = 3
/// How many of the newest messages must all be deleted copies.
private let ayuGramDeletedChatScanLimit = 200

private func ayuGramLoadDeletedChats(transaction: Transaction) -> AyuGramDeletedChats {
    return transaction.getPreferencesEntry(key: ayuGramDeletedChatsKey)?.get(AyuGramDeletedChats.self) ?? AyuGramDeletedChats(chats: [])
}

private struct AyuGramKeptPeers: Codable { var peers: [Int64] }
private let ayuGramKeptPeersKey = applicationSpecificPreferencesKey(0x415958)

private func ayuGramLoadKeptPeers(transaction: Transaction) -> [Int64] {
    return transaction.getPreferencesEntry(key: ayuGramKeptPeersKey)?.get(AyuGramKeptPeers.self)?.peers ?? []
}

func ayuGramNoteKeptPeers(transaction: Transaction, peerIds: Set<PeerId>) {
    guard !peerIds.isEmpty else { return }
    var peers = ayuGramLoadKeptPeers(transaction: transaction)
    var changed = false
    for peerId in peerIds where !peers.contains(peerId.toInt64()) {
        peers.append(peerId.toInt64())
        changed = true
    }
    if changed {
        transaction.setPreferencesEntry(key: ayuGramKeptPeersKey, value: PreferencesEntry(AyuGramKeptPeers(peers: peers)))
    }
}

func ayuGramDeletedChatPeers(transaction: Transaction) -> Set<Int64> {
    return Set(ayuGramLoadDeletedChats(transaction: transaction).chats.map { $0.peerId })
}

/// Called after a remote deletion kept copies of `retained`: a chat whose newest messages
/// are now all deleted copies lost its whole history.
func ayuGramFlagDeletedChats(transaction: Transaction, retained: [MessageId]) {
    guard AyuGramSettings.shared.snapshot.messageHistory else { return }
    var list = ayuGramLoadDeletedChats(transaction: transaction)
    var changed = false
    let now = Int32(Date().timeIntervalSince1970)
    for (peerId, ids) in Dictionary(grouping: retained, by: { $0.peerId }) where ids.count >= ayuGramDeletedChatMinimum {
        var hasLiveMessage = false
        transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: ayuGramDeletedChatScanLimit) { message in
            if !message.flags.contains(.AyuLocallyDeleted) {
                hasLiveMessage = true
            }
            return !hasLiveMessage
        }
        guard !hasLiveMessage else { continue }
        let title = String((transaction.getPeer(peerId)?.debugDisplayTitle ?? "").prefix(256))
        if let index = list.chats.firstIndex(where: { $0.peerId == peerId.toInt64() }) {
            list.chats[index].deletedAt = now
            if !title.isEmpty {
                list.chats[index].title = title
            }
        } else {
            list.chats.append(AyuGramDeletedChat(peerId: peerId.toInt64(), title: title, deletedAt: now))
        }
        if case .notIncluded = transaction.getPeerChatListInclusion(peerId) {
            transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
        }
        changed = true
    }
    if changed {
        transaction.setPreferencesEntry(key: ayuGramDeletedChatsKey, value: PreferencesEntry(list))
    }
}

/// The kept copies of deleted messages in a chat, oldest first.
private func ayuGramDeletedCopies(transaction: Transaction, peerId: PeerId) -> [Message] {
    var messages: [Message] = []
    transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: Int.max) { message in
        if message.flags.contains(.AyuLocallyDeleted) {
            messages.append(message)
        }
        return true
    }
    return messages.reversed()
}

public extension TelegramEngine {
    /// Deleted chats, newest first, with the number of kept messages and the chat if it is still known.
    func ayuGramDeletedChats() -> Signal<[(chat: AyuGramDeletedChat, peer: EnginePeer?, count: Int)], NoError> {
        return self.account.postbox.preferencesView(keys: [ayuGramDeletedChatsKey])
        |> mapToSignal { _ -> Signal<[(chat: AyuGramDeletedChat, peer: EnginePeer?, count: Int)], NoError> in
            return self.account.postbox.transaction { transaction -> [(chat: AyuGramDeletedChat, peer: EnginePeer?, count: Int)] in
                return ayuGramLoadDeletedChats(transaction: transaction).chats.sorted(by: { $0.deletedAt > $1.deletedAt }).map { chat in
                    let peerId = PeerId(chat.peerId)
                    return (chat, transaction.getPeer(peerId).map(EnginePeer.init), ayuGramDeletedCopies(transaction: transaction, peerId: peerId).count)
                }
            }
        }
    }

    /// Chats that hold kept deleted messages, most recently deleted first.
    func ayuGramKeptDeletedChats() -> Signal<[(peerId: EnginePeer.Id, peer: EnginePeer?, count: Int, deletedAt: Int32)], NoError> {
        return self.account.postbox.transaction { transaction -> [(peerId: EnginePeer.Id, peer: EnginePeer?, count: Int, deletedAt: Int32)] in
            var ids = ayuGramLoadKeptPeers(transaction: transaction)
            for chat in ayuGramLoadDeletedChats(transaction: transaction).chats where !ids.contains(chat.peerId) {
                ids.append(chat.peerId)
            }
            var result: [(peerId: EnginePeer.Id, peer: EnginePeer?, count: Int, deletedAt: Int32)] = []
            var remaining: [Int64] = []
            for id in ids {
                let peerId = PeerId(id)
                let copies = ayuGramDeletedCopies(transaction: transaction, peerId: peerId)
                guard !copies.isEmpty else { continue }
                remaining.append(id)
                let deletedAt = copies.compactMap { $0.ayuHistory?.deletedAt }.max() ?? copies.last?.timestamp ?? 0
                result.append((peerId, transaction.getPeer(peerId).map(EnginePeer.init), copies.count, deletedAt))
            }
            if remaining.count != ayuGramLoadKeptPeers(transaction: transaction).count {
                transaction.setPreferencesEntry(key: ayuGramKeptPeersKey, value: remaining.isEmpty ? nil : PreferencesEntry(AyuGramKeptPeers(peers: remaining)))
            }
            return result.sorted(by: { $0.deletedAt > $1.deletedAt })
        }
    }

    /// The kept deleted messages of a chat as history records, newest first.
    func ayuGramKeptDeletedEntries(peerId: EnginePeer.Id) -> Signal<[AyuGramHistoryEntry], NoError> {
        return self.account.postbox.transaction { transaction -> [AyuGramHistoryEntry] in
            let peerTitle = String((transaction.getPeer(peerId)?.debugDisplayTitle ?? "").prefix(256))
            return ayuGramDeletedCopies(transaction: transaction, peerId: peerId).reversed().map { message -> AyuGramHistoryEntry in
                var text = message.text
                if text.isEmpty {
                    for media in message.media {
                        if media is TelegramMediaImage {
                            text = "🖼"
                        } else if let file = media as? TelegramMediaFile {
                            text = file.isVoice ? "🎤" : file.isInstantVideo || file.isVideo ? "📹" : file.isSticker ? "🏷" : "📎 " + (file.fileName ?? "")
                        }
                        if !text.isEmpty {
                            break
                        }
                    }
                }
                return AyuGramHistoryEntry(peerId: peerId.toInt64(), messageId: message.id.id, peerTitle: peerTitle, author: String((message.author?.debugDisplayTitle ?? "").prefix(256)), text: text, event: "deleted", timestamp: message.ayuHistory?.deletedAt ?? message.timestamp, photoFileName: nil, photoResourceId: nil, authorId: message.author?.id.toInt64(), messageTimestamp: message.timestamp, mediaKind: nil, mediaTitle: nil, updatedText: nil)
            }
        }
    }

    func ayuGramDeleteKeptMessage(peerId: EnginePeer.Id, messageId: Int32) -> Signal<Void, NoError> {
        return self.account.postbox.transaction { transaction -> Void in
            let id = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: messageId)
            if let message = transaction.getMessage(id), message.flags.contains(.AyuLocallyDeleted) {
                transaction.deleteMessages([id], forEachMedia: { _ in })
            }
        }
    }

    /// The kept messages of a deleted chat, oldest first.
    func ayuGramDeletedChatMessages(peerId: EnginePeer.Id) -> Signal<[EngineMessage], NoError> {
        return self.account.postbox.transaction { transaction -> [EngineMessage] in
            return ayuGramDeletedCopies(transaction: transaction, peerId: peerId).map(EngineMessage.init)
        }
    }

    /// Removes a chat from the list. With `deleteMessages` its kept messages are deleted too;
    /// otherwise they stay in the chat like other deleted messages.
    func ayuGramForgetDeletedChat(peerId: EnginePeer.Id, deleteMessages: Bool) -> Signal<Void, NoError> {
        return self.account.postbox.transaction { transaction -> Void in
            var list = ayuGramLoadDeletedChats(transaction: transaction)
            list.chats.removeAll(where: { $0.peerId == peerId.toInt64() })
            transaction.setPreferencesEntry(key: ayuGramDeletedChatsKey, value: list.chats.isEmpty ? nil : PreferencesEntry(list))
            if deleteMessages {
                transaction.deleteMessages(ayuGramDeletedCopies(transaction: transaction, peerId: peerId).map { $0.id }, forEachMedia: { _ in })
            }
        }
    }
}
