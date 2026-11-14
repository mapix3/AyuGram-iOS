import Foundation
import Postbox
import SGSimpleSettings

private func ayuGramPeerLabel(_ peerId: PeerId) -> String {
    switch peerId.namespace {
    case Namespaces.Peer.CloudUser:
        return "user\(peerId.id._internalGetInt64Value())"
    case Namespaces.Peer.CloudGroup:
        return "group\(peerId.id._internalGetInt64Value())"
    case Namespaces.Peer.CloudChannel:
        return "channel\(peerId.id._internalGetInt64Value())"
    default:
        return "peer\(peerId.toInt64())"
    }
}

private func ayuGramDeletionOutcome(transaction: Transaction, id: MessageId) -> String {
    guard AyuGramSettings.shared.snapshot.messageHistory else { return "saving is off" }
    guard let message = transaction.getMessage(id) else { return "not in database" }
    if message.ayuHistory?.deletedAt != nil { return "already kept" }
    if id.namespace != Namespaces.Message.Cloud && id.peerId.namespace != Namespaces.Peer.SecretChat { return "not a cloud message" }
    if message.text.isEmpty && message.media.isEmpty && !ayuGramHasRichText(message.attributes) { return "empty" }
    return "kept"
}

/// Writes what happens to each remote deletion to the AyuGram log.
func ayuGramLogDeletion(transaction: Transaction, source: String, ids: [MessageId], unresolved: Int = 0) {
    var parts: [String] = []
    for id in ids.prefix(20) {
        parts.append("\(ayuGramPeerLabel(id.peerId)):\(id.id) \(ayuGramDeletionOutcome(transaction: transaction, id: id))")
    }
    if ids.count > 20 {
        parts.append("+\(ids.count - 20) more")
    }
    if unresolved > 0 {
        parts.append("\(unresolved) ids not found in any private chat or group")
    }
    if !parts.isEmpty {
        AyuGramSessionLog.log("delete \(source): " + parts.joined(separator: ", "))
    }
}

func ayuGramDeleteRemoteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], manualAddMessageThreadStatsDifference: ((MessageThreadKey, Int, Int) -> Void)? = nil) {
    let ids = ids.filter { transaction.getMessage($0)?.ayuHistory?.deletedAt == nil }
    guard !ids.isEmpty else { return }
    let recorded = ayuGramRecordHistory(transaction: transaction, mediaBox: mediaBox, ids: ids, event: "deleted")
    var retained: [StoreMessage] = []
    // Every chat keeps its deleted messages; only the selected chats are also listed in Message history.
    let keepAll = AyuGramSettings.shared.snapshot.messageHistory
    for id in ids where recorded.contains(id) || (keepAll && ayuGramIsRetainable(transaction: transaction, id: id)) {
        guard let message = transaction.getMessage(id) else { continue }
        // A kept copy of a one-time or timer message must not expire again.
        var attributes = message.attributes.filter { !($0 is AyuHistoryMessageAttribute || $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute) }
        attributes.append(AyuHistoryMessageAttribute(originalText: message.ayuHistory?.originalText ?? ayuGramContentText(text: message.text, attributes: message.attributes), editedAt: message.ayuHistory?.editedAt, deletedAt: message.ayuHistory?.deletedAt ?? Int32(Date().timeIntervalSince1970)))
        var flags = StoreMessageFlags(message.flags)
        flags.insert(.AyuLocallyDeleted)
        flags.remove(.TopIndexable)
        flags.remove(.ReactionsArePossible)
        retained.append(StoreMessage(id: .Id(id), customStableId: message.stableId, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: flags, tags: [], globalTags: [], localTags: [], forwardInfo: message.forwardInfo.map(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: ayuGramKeptMedia(mediaBox: mediaBox, media: ayuGramRetainedMedia(transaction: transaction, mediaBox: mediaBox, message: message))))
    }
    _internal_deleteMessages(transaction: transaction, mediaBox: mediaBox, ids: ids, manualAddMessageThreadStatsDifference: manualAddMessageThreadStatsDifference)
    let _ = transaction.addMessages(retained, location: .Random)
    ayuGramNoteKeptPeers(transaction: transaction, peerIds: Set(retained.compactMap { message -> PeerId? in
        if case let .Id(id) = message.id {
            return id.peerId
        }
        return nil
    }))
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
    let changed = previous.text != updated.text || ayuGramRichText(previous.attributes, full: false) != ayuGramRichText(updated.attributes, full: false) || ayuGramEditableMediaIds(previous.media) != ayuGramEditableMediaIds(updated.media)
    guard changed else { return previous.ayuHistory }
    let saved = ayuGramRecordHistory(transaction: transaction, mediaBox: mediaBox, ids: [id], event: "edited")
    if saved.contains(id) {
        ayuGramCompleteEditSnapshot(transaction: transaction, id: id, updatedText: ayuGramContentText(text: updated.text, attributes: updated.attributes))
    } else if !(AyuGramSettings.shared.snapshot.messageHistory && ayuGramIsHistoryCandidate(transaction: transaction, id: id)) {
        return previous.ayuHistory
    }
    // Chats outside Message history keep the version before the first edit on the message
    // itself, like deleted messages, so it can still be shown.
    let kept = previous.ayuHistory.flatMap { $0.editedAt == nil || $0.originalText.isEmpty ? nil : $0.originalText }
    return AyuHistoryMessageAttribute(originalText: kept ?? ayuGramContentText(text: previous.text, attributes: previous.attributes), editedAt: Int32(Date().timeIntervalSince1970), deletedAt: nil)
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

func ayuGramHasRichText(_ attributes: [MessageAttribute]) -> Bool {
    return attributes.contains(where: { $0 is RichTextMessageAttribute })
}

func ayuGramRichText(_ attributes: [MessageAttribute], full: Bool) -> String {
    for attribute in attributes {
        if let attribute = attribute as? RichTextMessageAttribute {
            let page = full ? (attribute.fullInstantPage ?? attribute.instantPage) : attribute.instantPage
            return ayuGramBlocksText(page.blocks)
        }
    }
    return ""
}

func ayuGramContentText(text: String, attributes: [MessageAttribute]) -> String {
    let rich = ayuGramRichText(attributes, full: true)
    return rich.isEmpty ? text : rich
}

private func ayuGramJoined(_ pieces: [String]) -> String {
    return pieces.filter { !$0.isEmpty }.joined(separator: "\n")
}

private func ayuGramBlocksText(_ blocks: [InstantPageBlock]) -> String {
    var pieces: [String] = []
    for block in blocks {
        switch block {
        case let .title(text), let .subtitle(text), let .header(text), let .subheader(text), let .paragraph(text), let .footer(text), let .kicker(text):
            pieces.append(text.plainText)
        case let .heading(text, _):
            pieces.append(text.plainText)
        case let .formula(latex):
            pieces.append(latex)
        case let .preformatted(text, _):
            pieces.append(text.plainText)
        case let .list(items, ordered):
            var index = 0
            for item in items {
                index += 1
                var marker = ordered ? "\(index). " : "• "
                var body = ""
                switch item {
                case let .text(text, _, checked):
                    body = text.plainText
                    if let checked {
                        marker = checked ? "☑ " : "☐ "
                    }
                case let .blocks(blocks, _, checked):
                    body = ayuGramBlocksText(blocks)
                    if let checked {
                        marker = checked ? "☑ " : "☐ "
                    }
                case .unknown:
                    break
                }
                if !body.isEmpty {
                    pieces.append(marker + body)
                }
            }
        case let .blockQuote(blocks, caption, _):
            pieces.append(ayuGramJoined([ayuGramBlocksText(blocks), caption.plainText]))
        case let .pullQuote(text, caption):
            pieces.append(ayuGramJoined([text.plainText, caption.plainText]))
        case let .image(_, caption, _, _, _):
            pieces.append(caption.text.plainText)
        case let .video(_, caption, _, _, _):
            pieces.append(caption.text.plainText)
        case let .audio(_, caption):
            pieces.append(caption.text.plainText)
        case let .document(_, caption):
            pieces.append(caption.text.plainText)
        case let .cover(block):
            pieces.append(ayuGramBlocksText([block]))
        case let .collage(items, caption):
            pieces.append(ayuGramJoined([ayuGramBlocksText(items), caption.text.plainText]))
        case let .slideshow(items, caption):
            pieces.append(ayuGramJoined([ayuGramBlocksText(items), caption.text.plainText]))
        case let .table(title, rows, _, _, _):
            var lines: [String] = [title.plainText]
            for row in rows {
                lines.append(row.cells.map { $0.text?.plainText ?? "" }.joined(separator: " | "))
            }
            pieces.append(ayuGramJoined(lines))
        case let .details(title, blocks, _):
            pieces.append(ayuGramJoined([title.plainText, ayuGramBlocksText(blocks)]))
        default:
            break
        }
    }
    return ayuGramJoined(pieces)
}
