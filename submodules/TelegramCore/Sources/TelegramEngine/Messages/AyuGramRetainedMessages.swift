import Foundation
import Postbox
import SGSimpleSettings

func ayuGramDeleteRemoteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil) {
    let ids = ids.filter { transaction.getMessage($0)?.ayuHistory?.deletedAt == nil }
    guard !ids.isEmpty else { return }
    let recorded = ayuGramRecordHistory(transaction: transaction, mediaBox: mediaBox, ids: ids, event: "deleted")
    let policy = transaction.getPreferencesEntry(key: applicationSpecificPreferencesKey(0x415956))?.get(AyuGramHistoryPolicy.self) ?? AyuGramHistoryPolicy()
    var retained: [StoreMessage] = []
    // Every chat keeps its deleted messages; only the selected chats are also listed in Message history.
    let keepAll = AyuGramSettings.shared.snapshot.messageHistory
    for id in ids where recorded.contains(id) || (keepAll && ayuGramIsRetainable(transaction: transaction, id: id)) {
        guard let message = transaction.getMessage(id) else { continue }
        // A kept copy of a one-time or timer message must not expire again.
        var attributes = message.attributes.filter { !($0 is AyuHistoryMessageAttribute || $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute) }
        attributes.append(AyuHistoryMessageAttribute(originalText: message.ayuHistory?.originalText ?? message.text, editedAt: message.ayuHistory?.editedAt, deletedAt: message.ayuHistory?.deletedAt ?? Int32(Date().timeIntervalSince1970)))
        var flags = StoreMessageFlags(message.flags)
        flags.insert(.AyuLocallyDeleted)
        flags.remove(.TopIndexable)
        flags.remove(.ReactionsArePossible)
        retained.append(StoreMessage(id: .Id(id), customStableId: message.stableId, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: flags, tags: [], globalTags: [], localTags: [], forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: policy.savePhotos ? ayuGramRetainedMedia(transaction: transaction, mediaBox: mediaBox, message: message) : []))
    }
    _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: ids, manualAddMessageThreadStatsDifference: manualAddMessageThreadStatsDifference)
    let _ = transaction.addMessages(retained, location: .Random)
    ayuGramFlagDeletedChats(transaction: transaction, retained: retained.compactMap { message -> MessageId? in
        if case let .Id(id) = message.id {
            return id
        }
        return nil
    })
}

func ayuGramRecordEdit(transaction: Transaction, mediaBox: MediaBox, id: MessageId, updated: StoreMessage) -> AyuHistoryMessageAttribute? {
    guard let previous = transaction.getMessage(id), previous.ayuHistory?.deletedAt == nil else { return nil }
    // Reactions, view counters and refreshed file references also arrive as
    // edit updates; only a changed text or a replaced photo/file is an edit.
    let changed = previous.text != updated.text || ayuGramEditableMediaIds(previous.media) != ayuGramEditableMediaIds(updated.media)
    guard changed else { return previous.ayuHistory }
    let saved = ayuGramRecordHistory(transaction: transaction, mediaBox: mediaBox, ids: [id], event: "edited")
    if saved.contains(id) {
        ayuGramCompleteEditSnapshot(transaction: transaction, id: id, updatedText: updated.text)
    } else if !(AyuGramSettings.shared.snapshot.messageHistory && ayuGramIsHistoryCandidate(transaction: transaction, id: id)) {
        return previous.ayuHistory
    }
    // Chats outside Message history keep the version before the first edit on the message
    // itself, like deleted messages, so it can still be shown.
    return AyuHistoryMessageAttribute(originalText: previous.ayuHistory?.originalText ?? previous.text, editedAt: Int32(Date().timeIntervalSince1970), deletedAt: nil)
}

private func ayuGramEditableMediaIds(_ media: [Media]) -> [MediaId] {
    return media.filter { !($0 is TelegramMediaWebpage) }.compactMap { $0.id }
}

func ayuGramClearLocalEditMarker(transaction: Transaction, ids: Set<MessageId>) {
    for id in ids {
        guard let message = transaction.getMessage(id), let marker = message.ayuHistory, marker.deletedAt == nil else { continue }
        let attributes = message.attributes.filter { !($0 is AyuHistoryMessageAttribute) } + [AyuHistoryMessageAttribute(originalText: "", editedAt: nil, deletedAt: nil)]
        transaction.updateMessage(id) { _ in
            return .update(StoreMessage(id: .Id(id), customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media))
        }
    }
}
