import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit
import SGSimpleSettings

private struct AyuGramSeenReactions: Codable {
    var id: Int32
    var keys: [String]
}

/// With read receipts hidden, mentions and reactions you have seen are read only on this
/// device. The server is told when you next send a message in that chat. Mentions whose read
/// state the sender can see (voice, round video, timer media) are never reported. Both lists
/// also stop a later server sync from showing seen ones again.
private struct AyuGramDeferredReads: Codable {
    var mentions: [Int32]
    var reactions: [Int32]
    var seenReactions: [AyuGramSeenReactions]?
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
    let reactionIds = Set(reads.reactions)
    let seenReactions = (reads.seenReactions ?? []).filter { reactionIds.contains($0.id) }
    reads.seenReactions = seenReactions.isEmpty ? nil : seenReactions
    if reads.mentions.isEmpty && reads.reactions.isEmpty {
        transaction.removeItemCacheEntry(id: ayuGramDeferredReadsEntryId(peerId))
    } else if let entry = CodableEntry(reads) {
        transaction.putItemCacheEntry(id: ayuGramDeferredReadsEntryId(peerId), entry: entry)
    }
}

private struct AyuGramDeferredPeers: Codable {
    var peers: [Int64]
}

private func ayuGramDeferredPeersEntryId() -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: 0)
    return ItemCacheEntryId(collectionId: 122, key: key)
}

private func ayuGramDeferredPeers(transaction: Transaction) -> [PeerId] {
    let stored = transaction.retrieveItemCacheEntry(id: ayuGramDeferredPeersEntryId())?.get(AyuGramDeferredPeers.self)
    return (stored?.peers ?? []).map { PeerId($0) }
}

private func ayuGramRememberDeferredPeer(transaction: Transaction, peerId: PeerId) {
    var peers = transaction.retrieveItemCacheEntry(id: ayuGramDeferredPeersEntryId())?.get(AyuGramDeferredPeers.self)?.peers ?? []
    let value = peerId.toInt64()
    if !peers.contains(value) {
        peers.append(value)
        if let entry = CodableEntry(AyuGramDeferredPeers(peers: Array(peers.suffix(2000)))) {
            transaction.putItemCacheEntry(id: ayuGramDeferredPeersEntryId(), entry: entry)
        }
    }
}

func ayuAdjustedMentionCount(transaction: Transaction, peerId: PeerId, count: Int32) -> Int32 {
    guard count > 0 else { return count }
    let deferred = Int32(ayuGramDeferredReads(transaction: transaction, peerId: peerId).mentions.count)
    return max(0, count - deferred)
}

final class AyuDeferredReadsFlusher {
    private let postbox: Postbox
    private let network: Network
    private let stateManager: AccountStateManager
    private var observer: NSObjectProtocol?
    private var wasSuppressed: Bool
    private let disposable = MetaDisposable()

    init(postbox: Postbox, network: Network, stateManager: AccountStateManager) {
        self.postbox = postbox
        self.network = network
        self.stateManager = stateManager
        self.wasSuppressed = AyuGramSettings.shared.snapshot.suppressRead || AyuGramSettings.shared.snapshot.suppressOnline
        self.observer = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: nil) { [weak self] _ in
            self?.settingsChanged()
        }
        if !self.wasSuppressed {
            self.flushAll()
        }
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
        self.disposable.dispose()
    }

    private func settingsChanged() {
        let suppressed = AyuGramSettings.shared.snapshot.suppressRead || AyuGramSettings.shared.snapshot.suppressOnline
        let shouldFlush = self.wasSuppressed && !suppressed
        self.wasSuppressed = suppressed
        if shouldFlush {
            self.flushAll()
        }
    }

    private func flushAll() {
        let postbox = self.postbox
        let network = self.network
        let stateManager = self.stateManager
        self.disposable.set((postbox.transaction { transaction -> [PeerId] in
            return ayuGramDeferredPeers(transaction: transaction)
        }
        |> mapToSignal { peerIds -> Signal<Void, NoError> in
            let signals = peerIds.map { _internal_ayuFlushDeferredReads(postbox: postbox, network: network, stateManager: stateManager, peerId: $0, includeVisible: true) }
            return combineLatest(signals) |> map { _ in Void() }
        }).start())
    }
}

func ayuDeferMentionRead(transaction: Transaction, id: MessageId) {
    guard id.namespace == Namespaces.Message.Cloud else { return }
    ayuGramRememberDeferredPeer(transaction: transaction, peerId: id.peerId)
    ayuGramUpdateDeferredReads(transaction: transaction, peerId: id.peerId) { reads in
        if !reads.mentions.contains(id.id) {
            reads.mentions.append(id.id)
        }
    }
}

private func ayuReactionKeys(transaction: Transaction, id: MessageId, unseen: Bool) -> [String] {
    guard let attribute = transaction.getMessage(id)?.attributes.first(where: { $0 is ReactionsMessageAttribute }) as? ReactionsMessageAttribute else {
        return []
    }
    return attribute.recentPeers.filter { $0.isUnseen == unseen }.map { recentPeer in
        let value: String
        switch recentPeer.value {
        case let .builtin(emoji):
            value = "b" + emoji
        case let .custom(fileId):
            value = "c\(fileId)"
        case .stars:
            value = "s"
        }
        return "\(recentPeer.peerId.toInt64()):\(value):\(recentPeer.timestamp ?? 0)"
    }
}

func ayuDeferReactionRead(transaction: Transaction, id: MessageId) {
    ayuGramRememberDeferredPeer(transaction: transaction, peerId: id.peerId)
    guard id.namespace == Namespaces.Message.Cloud else { return }
    let keys = ayuReactionKeys(transaction: transaction, id: id, unseen: false)
    ayuGramUpdateDeferredReads(transaction: transaction, peerId: id.peerId) { reads in
        if !reads.reactions.contains(id.id) {
            reads.reactions.append(id.id)
        }
        var seenReactions = reads.seenReactions ?? []
        let previous = seenReactions.first(where: { $0.id == id.id })?.keys ?? []
        seenReactions.removeAll(where: { $0.id == id.id })
        seenReactions.append(AyuGramSeenReactions(id: id.id, keys: Array(Set(previous + keys)).sorted()))
        reads.seenReactions = seenReactions
    }
}

func ayuIsDeferredMentionRead(transaction: Transaction, id: MessageId) -> Bool {
    return ayuGramDeferredReads(transaction: transaction, peerId: id.peerId).mentions.contains(id.id)
}

func ayuIsDeferredReactionRead(transaction: Transaction, id: MessageId) -> Bool {
    let reads = ayuGramDeferredReads(transaction: transaction, peerId: id.peerId)
    guard reads.reactions.contains(id.id), let seen = reads.seenReactions?.first(where: { $0.id == id.id }) else {
        return false
    }
    return Set(ayuReactionKeys(transaction: transaction, id: id, unseen: true)).isSubset(of: Set(seen.keys))
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
func _internal_ayuFlushDeferredReads(postbox: Postbox, network: Network, stateManager: AccountStateManager, peerId: PeerId, includeVisible: Bool = false) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> (Peer?, [Int32]) in
        let reads = ayuGramDeferredReads(transaction: transaction, peerId: peerId)
        let mentions = reads.mentions.filter { id in
            guard let message = transaction.getMessage(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id)) else { return false }
            return includeVisible || ayuMentionReadIsPrivate(media: message.media, attributes: message.attributes)
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
