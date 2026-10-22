import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit
import SGSimpleSettings

/// With read receipts hidden, mentions and reactions you have seen are read only on this
/// device. The server is told when you next send a message in that chat. Mentions whose read
/// state the sender can see (voice, round video, timer media) are never reported. Both lists
/// also stop a later server sync from showing seen ones again.
private struct AyuGramDeferredReads: Codable {
    var mentions: [Int32]
    var reactions: [Int32]
}

private let ayuGramDeferredReadsLimit = 500

private func ayuGramDeferredReadsEntryId(_ peerId: PeerId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.toInt64())
    return ItemCacheEntryId(collectionId: 121, key: key)
}

private func ayuGramDeferredReads(transaction: Transaction, peerId: PeerId) -> AyuGramDeferredReads {
    return transaction.retrieveItemCacheEntry(id: ayuGramDeferredReadsEntryId(peerId))?.get(AyuGramDeferredReads.self) ?? AyuGramDeferredReads(mentions: [], reactions: [])
}

private func ayuGramUpdateDeferredReads(transaction: Transaction, peerId: PeerId, _ f: (inout AyuGramDeferredReads) -> Void) {
    var reads = ayuGramDeferredReads(transaction: transaction, peerId: peerId)
    f(&reads)
    reads.mentions = Array(reads.mentions.suffix(ayuGramDeferredReadsLimit))
    reads.reactions = Array(reads.reactions.suffix(ayuGramDeferredReadsLimit))
    if reads.mentions.isEmpty && reads.reactions.isEmpty {
        transaction.removeItemCacheEntry(id: ayuGramDeferredReadsEntryId(peerId))
    } else if let entry = CodableEntry(reads) {
        transaction.putItemCacheEntry(id: ayuGramDeferredReadsEntryId(peerId), entry: entry)
    }
}

func ayuDeferMentionRead(transaction: Transaction, id: MessageId) {
    guard id.namespace == Namespaces.Message.Cloud else { return }
    ayuGramUpdateDeferredReads(transaction: transaction, peerId: id.peerId) { reads in
        if !reads.mentions.contains(id.id) {
            reads.mentions.append(id.id)
        }
    }
}

func ayuDeferReactionRead(transaction: Transaction, id: MessageId) {
    guard id.namespace == Namespaces.Message.Cloud else { return }
    ayuGramUpdateDeferredReads(transaction: transaction, peerId: id.peerId) { reads in
        if !reads.reactions.contains(id.id) {
            reads.reactions.append(id.id)
        }
    }
}

func ayuIsDeferredMentionRead(transaction: Transaction, id: MessageId) -> Bool {
    return ayuGramDeferredReads(transaction: transaction, peerId: id.peerId).mentions.contains(id.id)
}

func ayuIsDeferredReactionRead(transaction: Transaction, id: MessageId) -> Bool {
    return ayuGramDeferredReads(transaction: transaction, peerId: id.peerId).reactions.contains(id.id)
}

/// Marks reactions and poll votes seen on this device only.
func ayuMarkReactionsSeenLocally(transaction: Transaction, id: MessageId) {
    transaction.updateMessage(id, update: { currentMessage in
        var attributes = currentMessage.attributes
        for j in 0 ..< attributes.count {
            if let attribute = attributes[j] as? ReactionsMessageAttribute, attribute.hasUnseen {
                attributes[j] = attribute.withAllSeen()
            }
        }
        var media = currentMessage.media
        for j in 0 ..< media.count {
            if let poll = media[j] as? TelegramMediaPoll {
                media[j] = poll.withoutUnreadResults()
            }
        }
        var tags = currentMessage.tags
        tags.remove(.unseenReaction)
        tags.remove(.unseenPollVote)
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: media))
    })
}

/// Reports the mentions and reactions read on this device in a chat you just wrote to.
func _internal_ayuFlushDeferredReads(postbox: Postbox, network: Network, stateManager: AccountStateManager, peerId: PeerId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> (Peer?, [Int32]) in
        let reads = ayuGramDeferredReads(transaction: transaction, peerId: peerId)
        let mentions = reads.mentions.filter { id in
            guard let message = transaction.getMessage(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id)) else { return false }
            return ayuMentionReadIsPrivate(media: message.media, attributes: message.attributes)
        }
        // At most 100 per request; the rest goes with the next message.
        return (transaction.getPeer(peerId), Array(Set(mentions + reads.reactions).sorted().suffix(100)))
    }
    |> mapToSignal { peer, ids -> Signal<Void, NoError> in
        guard let peer, !ids.isEmpty else { return .complete() }
        let request: Signal<Bool, NoError>
        if peerId.namespace == Namespaces.Peer.CloudChannel {
            guard let inputChannel = apiInputChannel(peer) else { return .complete() }
            request = network.request(Api.functions.channels.readMessageContents(channel: inputChannel, id: ids))
            |> map { _ in true }
            |> `catch` { _ in .single(false) }
        } else if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup {
            request = network.request(Api.functions.messages.readMessageContents(id: ids))
            |> map { result -> Bool in
                if case let .affectedMessages(data) = result {
                    stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
                }
                return true
            }
            |> `catch` { _ in .single(false) }
        } else {
            return .complete()
        }
        return request
        |> mapToSignal { success -> Signal<Void, NoError> in
            guard success else { return .complete() }
            return postbox.transaction { transaction -> Void in
                let reported = Set(ids)
                ayuGramUpdateDeferredReads(transaction: transaction, peerId: peerId) { reads in
                    reads.mentions.removeAll(where: { reported.contains($0) })
                    reads.reactions.removeAll(where: { reported.contains($0) })
                }
            }
        }
    }
}
