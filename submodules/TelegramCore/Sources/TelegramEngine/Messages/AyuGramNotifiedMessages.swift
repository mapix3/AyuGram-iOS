import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

/// What a message notification showed. A message deleted before the app or the
/// notification service synced it never reaches the database, so this is the only
/// copy Save Deleted Messages can keep.
private struct AyuGramNotifiedMessage: Codable, Equatable {
    var peerId: Int64
    var messageId: Int32
    var threadId: Int64?
    var authorId: Int64?
    var timestamp: Int32
    var text: String
    /// The notification's raw `attachb64` photo or file.
    var attachment: Data?
}

private struct AyuGramNotifiedMessages: Codable {
    var entries: [AyuGramNotifiedMessage]
}

private func ayuGramNotifiedMessagesEntryId() -> ItemCacheEntryId {
    return ItemCacheEntryId(collectionId: 120, key: ValueBoxKey("notified"))
}
// Deletions arrive within minutes; the cap keeps rewriting the list cheap for the extension.
private let ayuGramNotifiedMessagesLimit = 200
private let ayuGramNotifiedMessagesLifetime: Int32 = 2 * 24 * 60 * 60

private func ayuGramNotifiedMessages(transaction: Transaction) -> AyuGramNotifiedMessages {
    return transaction.retrieveItemCacheEntry(id: ayuGramNotifiedMessagesEntryId())?.get(AyuGramNotifiedMessages.self) ?? AyuGramNotifiedMessages(entries: [])
}

/// Called by the notification service for every message notification it receives.
public func _internal_ayuGramRememberNotifiedMessage(transaction: Transaction, id: MessageId, threadId: Int64?, authorId: PeerId?, text: String, attachment: Data?) {
    guard AyuGramSettings.shared.snapshot.messageHistory, id.namespace == Namespaces.Message.Cloud, id.peerId.namespace != Namespaces.Peer.SecretChat else { return }
    guard !text.isEmpty || attachment != nil else { return }
    let now = Int32(Date().timeIntervalSince1970)
    var list = ayuGramNotifiedMessages(transaction: transaction)
    list.entries.removeAll { $0.timestamp < now - ayuGramNotifiedMessagesLifetime || ($0.peerId == id.peerId.toInt64() && $0.messageId == id.id) }
    list.entries.append(AyuGramNotifiedMessage(peerId: id.peerId.toInt64(), messageId: id.id, threadId: threadId, authorId: authorId?.toInt64(), timestamp: now, text: String(text.prefix(4096)), attachment: attachment))
    if list.entries.count > ayuGramNotifiedMessagesLimit {
        list.entries.removeFirst(list.entries.count - ayuGramNotifiedMessagesLimit)
    }
    if let entry = CodableEntry(list) {
        transaction.putItemCacheEntry(id: ayuGramNotifiedMessagesEntryId(), entry: entry)
    }
}

/// Puts deleted messages that were only ever seen in a notification back into the
/// database, so the deletion that follows keeps them like any other message.
/// Returns the ids it restored.
@discardableResult
private func ayuGramRestoreNotifiedMessages(transaction: Transaction, matching: (AyuGramNotifiedMessage) -> Bool) -> [MessageId] {
    guard AyuGramSettings.shared.snapshot.messageHistory else { return [] }
    var list = ayuGramNotifiedMessages(transaction: transaction)
    let matches = list.entries.filter(matching)
    guard !matches.isEmpty else { return [] }
    var restored: [MessageId] = []
    var messages: [StoreMessage] = []
    for entry in matches {
        let id = MessageId(peerId: PeerId(entry.peerId), namespace: Namespaces.Message.Cloud, id: entry.messageId)
        guard transaction.getMessage(id) == nil else { continue }
        let media = entry.attachment.flatMap { _internal_parseMediaAttachment(data: $0) }.map { [$0] } ?? []
        messages.append(StoreMessage(id: .Id(id), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: entry.threadId, timestamp: entry.timestamp, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: entry.authorId.map { PeerId($0) }, text: entry.text, attributes: [], media: media))
        restored.append(id)
    }
    // A deleted message is never restored twice.
    list.entries.removeAll(where: matching)
    if let entry = CodableEntry(list) {
        transaction.putItemCacheEntry(id: ayuGramNotifiedMessagesEntryId(), entry: entry)
    }
    let _ = transaction.addMessages(messages, location: .Random)
    return restored
}

func ayuGramRestoreNotifiedMessages(transaction: Transaction, ids: [MessageId]) {
    let keys = Set(ids.map { "\($0.peerId.toInt64()):\($0.id)" })
    ayuGramRestoreNotifiedMessages(transaction: transaction, matching: { keys.contains("\($0.peerId):\($0.messageId)") })
}

/// Private chats and basic groups share one message id sequence per account, and
/// their deletions name only those ids.
func ayuGramRestoreNotifiedMessages(transaction: Transaction, globalIds: [Int32]) -> [MessageId] {
    let globalIds = Set(globalIds)
    return ayuGramRestoreNotifiedMessages(transaction: transaction, matching: { entry in
        let namespace = PeerId(entry.peerId).namespace
        return (namespace == Namespaces.Peer.CloudUser || namespace == Namespaces.Peer.CloudGroup) && globalIds.contains(entry.messageId)
    })
}

/// Deletions the notification service applies itself (MESSAGE_DELETED pushes) keep
/// messages exactly like deletions the app receives.
public func _internal_ayuGramDeleteNotifiedMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
    ayuGramRestoreNotifiedMessages(transaction: transaction, ids: ids)
    ayuGramDeleteRemoteMessages(transaction: transaction, mediaBox: mediaBox, ids: ids)
}

/// A message the push relay saw in a notification and then saw deleted.
public struct AyuGramRelayedDeletedMessage: Equatable {
    public let peerId: EnginePeer.Id
    public let messageId: Int32
    public let authorId: EnginePeer.Id?
    public let text: String
    public let timestamp: Int32
    public let deletedAt: Int32

    public init(peerId: EnginePeer.Id, messageId: Int32, authorId: EnginePeer.Id?, text: String, timestamp: Int32, deletedAt: Int32) {
        self.peerId = peerId
        self.messageId = messageId
        self.authorId = authorId
        self.text = text
        self.timestamp = timestamp
        self.deletedAt = deletedAt
    }
}

/// Keeps messages deleted while AyuGram was closed: with notifications relayed through
/// Bark the app never synced them, so the relay's copy is the only one. Returns the
/// messages of chats this account does not know.
func _internal_ayuGramKeepRelayedDeletedMessages(transaction: Transaction, mediaBox: MediaBox, messages: [AyuGramRelayedDeletedMessage]) -> [AyuGramRelayedDeletedMessage] {
    guard AyuGramSettings.shared.snapshot.messageHistory else { return [] }
    var unknown: [AyuGramRelayedDeletedMessage] = []
    var ids: [MessageId] = []
    var added: [StoreMessage] = []
    for item in messages {
        guard item.peerId.namespace != Namespaces.Peer.SecretChat, transaction.getPeer(item.peerId) != nil else {
            unknown.append(item)
            continue
        }
        let id = MessageId(peerId: item.peerId, namespace: Namespaces.Message.Cloud, id: item.messageId)
        if let existing = transaction.getMessage(id) {
            if existing.ayuHistory?.deletedAt == nil {
                ids.append(id)
            }
            continue
        }
        guard !item.text.isEmpty else { continue }
        let authorId = item.authorId ?? (item.peerId.namespace == Namespaces.Peer.CloudUser ? item.peerId : nil)
        added.append(StoreMessage(id: .Id(id), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: item.timestamp, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: authorId, text: String(item.text.prefix(4096)), attributes: [], media: []))
        ids.append(id)
    }
    if !added.isEmpty {
        let _ = transaction.addMessages(added, location: .Random)
    }
    if !ids.isEmpty {
        ayuGramDeleteRemoteMessages(transaction: transaction, mediaBox: mediaBox, ids: ids)
    }
    return unknown
}

public extension TelegramEngine {
    func ayuGramKeepRelayedDeletedMessages(_ messages: [AyuGramRelayedDeletedMessage]) -> Signal<[AyuGramRelayedDeletedMessage], NoError> {
        let mediaBox = self.account.postbox.mediaBox
        return self.account.postbox.transaction { transaction -> [AyuGramRelayedDeletedMessage] in
            return _internal_ayuGramKeepRelayedDeletedMessages(transaction: transaction, mediaBox: mediaBox, messages: messages)
        }
    }
}
