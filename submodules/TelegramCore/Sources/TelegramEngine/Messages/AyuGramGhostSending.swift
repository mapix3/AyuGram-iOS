import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

private let ayuGhostScheduleDelay: Int32 = 12

func ayuPrepareGhostSending(account: Account, peerId: PeerId, messages: [(Bool, EnqueueMessage)]) -> Signal<[(Bool, EnqueueMessage)], NoError> {
    let extra = AyuGramSettings.shared.extra
    let silent = extra.sendsSilently
    let schedule = extra.scheduleInGhost && AyuGramSettings.shared.snapshot.ghostMode
    guard silent || schedule, peerId.namespace != Namespaces.Peer.SecretChat else {
        return .single(messages)
    }
    return account.postbox.transaction { transaction -> Bool in
        if !schedule || peerId == account.peerId {
            return false
        }
        if let user = transaction.getPeer(peerId) as? TelegramUser, user.botInfo != nil {
            return false
        }
        return true
    }
    |> map { canSchedule -> [(Bool, EnqueueMessage)] in
        let scheduleTime = Int32(Date().timeIntervalSince1970) + ayuGhostScheduleDelay
        return messages.map { transformed, message in
            return (transformed, message.withUpdatedAttributes { attributes in
                var attributes = attributes
                if silent, !attributes.contains(where: { $0 is NotificationInfoMessageAttribute }) {
                    attributes.append(NotificationInfoMessageAttribute(flags: .muted))
                }
                if canSchedule, !attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute || $0 is OutgoingQuickReplyMessageAttribute }) {
                    attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil))
                    attributes.append(AyuGhostScheduleMessageAttribute())
                }
                return attributes
            })
        }
    }
}

public final class AyuGhostScheduleMessageAttribute: MessageAttribute {
    public init() {
    }

    public init(decoder: PostboxDecoder) {
    }

    public func encode(_ encoder: PostboxEncoder) {
    }
}

private struct AyuGhostMirror: Codable, Equatable {
    var peerId: Int64
    var mirrorId: Int32
    var scheduleTime: Int32
    var createdAt: Int32
    var text: String
}

private struct AyuGhostMirrors: Codable {
    var entries: [AyuGhostMirror]
}

private let ayuGhostMirrorLifetime: Int32 = 5 * 60

private func ayuGhostMirrorsEntryId() -> ItemCacheEntryId {
    return ItemCacheEntryId(collectionId: 122, key: ValueBoxKey("ghostMirrors"))
}

private func ayuGhostMirrors(transaction: Transaction) -> AyuGhostMirrors {
    return transaction.retrieveItemCacheEntry(id: ayuGhostMirrorsEntryId())?.get(AyuGhostMirrors.self) ?? AyuGhostMirrors(entries: [])
}

private func ayuStoreGhostMirrors(transaction: Transaction, _ list: AyuGhostMirrors) {
    if let entry = CodableEntry(list) {
        transaction.putItemCacheEntry(id: ayuGhostMirrorsEntryId(), entry: entry)
    }
}

private func ayuGhostMirrorMessageId(_ mirror: AyuGhostMirror) -> MessageId {
    return MessageId(peerId: PeerId(mirror.peerId), namespace: Namespaces.Message.Local, id: mirror.mirrorId)
}

private func ayuDropExpiredGhostMirrors(transaction: Transaction, list: inout AyuGhostMirrors, now: Int32) -> Bool {
    let expired = list.entries.filter { $0.createdAt < now - ayuGhostMirrorLifetime }
    if expired.isEmpty {
        return false
    }
    transaction.deleteMessages(expired.map(ayuGhostMirrorMessageId), forEachMedia: nil)
    list.entries.removeAll { $0.createdAt < now - ayuGhostMirrorLifetime }
    return true
}

func ayuCreateGhostMirrors(transaction: Transaction, accountPeerId: PeerId, ids: [MessageId]) {
    var pending: [Int64: (MessageId, Int32, String)] = [:]
    var stored: [StoreMessage] = []
    let now = Int32(Date().timeIntervalSince1970)
    for id in ids where id.namespace == Namespaces.Message.ScheduledLocal {
        guard let message = transaction.getMessage(id), message.attributes.contains(where: { $0 is AyuGhostScheduleMessageAttribute }) else {
            continue
        }
        let scheduleTime = (message.attributes.first(where: { $0 is OutgoingScheduleInfoMessageAttribute }) as? OutgoingScheduleInfoMessageAttribute)?.scheduleTime ?? message.timestamp
        let attributes = message.attributes.filter { !($0 is OutgoingScheduleInfoMessageAttribute) && !($0 is AyuGhostScheduleMessageAttribute) && !($0 is OutgoingMessageInfoAttribute) }
        let uniqueId = Int64.random(in: Int64.min ... Int64.max)
        let tags = tagsForStoreMessage(incoming: false, attributes: attributes, media: message.media, textEntities: nil, isPinned: false).0
        stored.append(StoreMessage(peerId: id.peerId, namespace: Namespaces.Message.Local, customStableId: nil, globallyUniqueId: uniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: now, flags: [], tags: tags, globalTags: [], localTags: [], forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init), authorId: accountPeerId, text: message.text, attributes: attributes, media: message.media))
        pending[uniqueId] = (id, scheduleTime, message.text)
    }
    if stored.isEmpty {
        return
    }
    var list = ayuGhostMirrors(transaction: transaction)
    let _ = ayuDropExpiredGhostMirrors(transaction: transaction, list: &list, now: now)
    let added = transaction.addMessages(stored, location: .Random)
    for (uniqueId, mirrorId) in added {
        guard let (scheduledId, scheduleTime, text) = pending[uniqueId] else {
            continue
        }
        list.entries.append(AyuGhostMirror(peerId: scheduledId.peerId.toInt64(), mirrorId: mirrorId.id, scheduleTime: scheduleTime, createdAt: now, text: text))
    }
    ayuStoreGhostMirrors(transaction: transaction, list)
}

func ayuConsumeGhostMirrors(transaction: Transaction, publishedIds: [MessageId]) -> [MessageId] {
    if publishedIds.isEmpty {
        return publishedIds
    }
    var list = ayuGhostMirrors(transaction: transaction)
    if list.entries.isEmpty {
        return publishedIds
    }
    var changed = ayuDropExpiredGhostMirrors(transaction: transaction, list: &list, now: Int32(Date().timeIntervalSince1970))
    var remaining: [MessageId] = []
    var consumed: [MessageId] = []
    for id in publishedIds.sorted() {
        guard let message = transaction.getMessage(id), !message.flags.contains(.Incoming) else {
            remaining.append(id)
            continue
        }
        let peerId = id.peerId.toInt64()
        let candidates = list.entries.indices.filter { list.entries[$0].peerId == peerId }
        guard let index = candidates.first(where: { list.entries[$0].text == message.text }) ?? candidates.min(by: { list.entries[$0].createdAt < list.entries[$1].createdAt }) else {
            remaining.append(id)
            continue
        }
        consumed.append(ayuGhostMirrorMessageId(list.entries[index]))
        list.entries.remove(at: index)
        changed = true
    }
    if !consumed.isEmpty {
        transaction.deleteMessages(consumed, forEachMedia: nil)
    }
    if changed {
        ayuStoreGhostMirrors(transaction: transaction, list)
    }
    return remaining
}

func ayuGhostMirrorDeletion(transaction: Transaction, ids: [MessageId]) -> [MessageId] {
    let mirrorIds = ids.filter { $0.namespace == Namespaces.Message.Local }
    if mirrorIds.isEmpty {
        return ids
    }
    var list = ayuGhostMirrors(transaction: transaction)
    if list.entries.isEmpty {
        return ids
    }
    var result = ids
    var changed = false
    for id in mirrorIds {
        guard let index = list.entries.firstIndex(where: { ayuGhostMirrorMessageId($0) == id }) else {
            continue
        }
        let mirror = list.entries[index]
        list.entries.remove(at: index)
        changed = true
        var scheduledId: MessageId?
        for namespace in [Namespaces.Message.ScheduledLocal, Namespaces.Message.ScheduledCloud] where scheduledId == nil {
            transaction.withAllMessages(peerId: id.peerId, namespace: namespace, { message in
                if message.timestamp == mirror.scheduleTime && message.text == mirror.text && !result.contains(message.id) {
                    scheduledId = message.id
                    return false
                }
                return true
            })
        }
        if let scheduledId {
            result.append(scheduledId)
        }
    }
    if changed {
        ayuStoreGhostMirrors(transaction: transaction, list)
    }
    return result
}
