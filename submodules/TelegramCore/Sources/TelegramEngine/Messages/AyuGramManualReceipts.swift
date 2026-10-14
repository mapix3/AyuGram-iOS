import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit
import SGSimpleSettings

/// Only a transient display copy is changed. The Postbox message retains its
/// lifetime attributes, and server expiry/deletions still update it normally.
public func ayuPrivateMediaDisplayMessage(_ message: Message) -> Message? {
    guard AyuGramSettings.shared.snapshot.suppressRead,
          message.flags.contains(.Incoming), message.containsSecretMedia,
          message.id.peerId.namespace == Namespaces.Peer.CloudUser,
          message.id.namespace == Namespaces.Message.Cloud,
          message.media.contains(where: { $0 is TelegramMediaImage }) else { return nil }
    let attributes = message.attributes.filter {
        !($0 is AutoclearTimeoutMessageAttribute) && !($0 is AutoremoveTimeoutMessageAttribute)
        && !($0 is ConsumableContentMessageAttribute)
    }
    return message.withUpdatedAttributes(attributes)
}

func _internal_ayuReportRead(account: Account, messageId: MessageId, threadId: Int64?) -> Signal<Bool, NoError> {
    return ayuReportRead(postbox: account.postbox, network: account.network, stateManager: account.stateManager, messageId: messageId, requestedThreadId: threadId, allowOutgoing: false)
}

func _internal_ayuReportReadAfterSending(postbox: Postbox, network: Network, stateManager: AccountStateManager, accountPeerId: PeerId, messageId: MessageId) -> Signal<Bool, NoError> {
    guard AyuGramSettings.shared.snapshot.suppressRead,
          messageId.namespace == Namespaces.Message.Cloud,
          messageId.peerId != accountPeerId else { return .single(false) }
    return ayuReportRead(postbox: postbox, network: network, stateManager: stateManager, messageId: messageId, requestedThreadId: nil, allowOutgoing: true)
}

/// Ghost Mode follow-ups for a delivered outgoing message: the server marks
/// the sender online on activity, so report offline again while online status
/// is hidden; optionally acknowledge the chat that was replied to.
func _internal_ayuAfterSending(postbox: Postbox, network: Network, stateManager: AccountStateManager, accountPeerId: PeerId, messageId: MessageId) -> Signal<Bool, NoError> {
    let privacy = AyuGramSettings.shared.snapshot
    let extra = AyuGramSettings.shared.extra
    if privacy.suppressOnline && extra.offlineAfterSending {
        let _ = (network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }).startStandalone()
    }
    guard extra.readOnSend else {
        return .single(false)
    }
    return _internal_ayuReportReadAfterSending(postbox: postbox, network: network, stateManager: stateManager, accountPeerId: accountPeerId, messageId: messageId)
}

// Kept independent of the transport so routing can be exercised in CI.
func ayuReceiptThreadId(requested: Int64?, message: Int64?, isForum: Bool, afterSending: Bool) -> Int64? {
    let value = requested ?? (isForum && afterSending ? message : nil)
    guard let value, value > 0 else { return nil }
    return value
}

func ayuApplyThreadReceipt(transaction: Transaction, index: MessageIndex, threadId: Int64) {
    guard var data = transaction.getMessageHistoryThreadInfo(peerId: index.id.peerId, threadId: threadId)?.data.get(MessageHistoryThreadData.self), index.id.id > data.maxIncomingReadId else { return }
    if let count = transaction.getThreadMessageCount(peerId: index.id.peerId, threadId: threadId, namespace: index.id.namespace, fromIdExclusive: data.maxIncomingReadId, toIndex: index) {
        data.incomingUnreadCount = max(0, data.incomingUnreadCount - Int32(count))
    }
    data.maxIncomingReadId = index.id.id
    data.maxKnownMessageId = max(data.maxKnownMessageId, index.id.id)
    data.isMarkedUnread = false
    if let entry = StoredMessageHistoryThreadInfo(data) {
        transaction.setMessageHistoryThreadInfo(peerId: index.id.peerId, threadId: threadId, info: entry)
    }
}

/// While read receipts are hidden, a mention is still marked read on the server so its
/// counter does not come back after the next sync. That is invisible to the sender unless
/// the message has media with a played or opened state: voice, round video or timer media.
func ayuMentionReadIsPrivate(media: [Media], attributes: [MessageAttribute]) -> Bool {
    if attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute }) {
        return false
    }
    return !media.contains(where: { item in
        guard let file = item as? TelegramMediaFile else { return false }
        return file.isVoice || file.isInstantVideo
    })
}

// Mention-only consumption never starts media timers or sends a content receipt.
// It also repairs pending=true mentions left behind by older private builds.
func ayuConsumeMentionLocally(transaction: Transaction, id: MessageId) {
    transaction.updateMessage(id, update: { currentMessage in
        var attributes = currentMessage.attributes
        for j in 0 ..< attributes.count {
            if attributes[j] is ConsumablePersonalMentionMessageAttribute {
                attributes[j] = ConsumablePersonalMentionMessageAttribute(consumed: true, pending: false)
            }
        }
        var tags = currentMessage.tags
        tags.remove(.unseenPersonalMessage)
        return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
    })
    transaction.setPendingMessageAction(type: .consumeUnseenPersonalMessage, id: id, action: nil)
}

private func ayuReportRead(postbox: Postbox, network: Network, stateManager: AccountStateManager, messageId: MessageId, requestedThreadId: Int64?, allowOutgoing: Bool) -> Signal<Bool, NoError> {
    guard messageId.namespace == Namespaces.Message.Cloud else { return .single(false) }
    return postbox.transaction { transaction -> (Peer?, Message?) in
        return (transaction.getPeer(messageId.peerId), transaction.getMessage(messageId))
    }
    |> mapToSignal { peer, message -> Signal<Bool, NoError> in
        guard let peer, let message, message.flags.contains(.Incoming) || allowOutgoing else { return .single(false) }
        // A reply's threadId is also populated in an ordinary supergroup.
        // Only the open UI thread (or a forum topic after sending) scopes a receipt.
        let threadId = ayuReceiptThreadId(requested: requestedThreadId, message: message.threadId, isForum: peer.isForumOrMonoForum, afterSending: allowOutgoing)
        let request: Signal<Bool, MTRpcError>
        if let threadId, let inputPeer = apiInputPeer(peer) {
            if peer.isMonoForum {
                request = postbox.transaction { transaction -> Api.InputPeer? in
                    transaction.getPeer(PeerId(threadId)).flatMap(apiInputPeer)
                }
                |> castError(MTRpcError.self)
                |> mapToSignal { subPeer -> Signal<Bool, MTRpcError> in
                    guard let subPeer else { return .single(false) }
                    return network.request(Api.functions.messages.readSavedHistory(parentPeer: inputPeer, peer: subPeer, maxId: messageId.id))
                    |> map { result in if case .boolTrue = result { return true }; return false }
                }
            } else {
            request = network.request(Api.functions.messages.readDiscussion(peer: inputPeer, msgId: Int32(clamping: threadId), readMaxId: messageId.id))
            |> map { result in if case .boolTrue = result { return true }; return false }
            }
        } else if let channel = peer as? TelegramChannel, let inputChannel = apiInputChannel(channel) {
            request = network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: messageId.id))
            |> map { result in if case .boolTrue = result { return true }; return false }
        } else if let inputPeer = apiInputPeer(peer) {
            request = network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: messageId.id))
            |> map { affected in
                if case let .affectedMessages(data) = affected {
                    stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
                }
                return true
            }
        } else {
            return .single(false)
        }
        return request
        |> `catch` { _ in .single(false) }
        |> mapToSignal { success -> Signal<Bool, NoError> in
            guard success else { return .single(false) }
            return postbox.transaction { transaction -> Bool in
                if let threadId {
                    ayuApplyThreadReceipt(transaction: transaction, index: message.index, threadId: threadId)
                } else {
                    let _ = transaction.applyInteractiveReadMaxIndex(message.index, synchronize: false)
                }
                for index in transaction.getMessageIndicesWithTag(peerId: messageId.peerId, threadId: threadId, namespace: messageId.namespace, tag: .unseenPersonalMessage) where index.id.id <= messageId.id {
                    ayuConsumeMentionLocally(transaction: transaction, id: index.id)
                }
                return true
            }
        }
    }
}

func _internal_ayuReportContentViewed(account: Account, messageId: MessageId) -> Signal<Bool, NoError> {
    guard messageId.namespace == Namespaces.Message.Cloud,
          messageId.peerId.namespace == Namespaces.Peer.CloudUser else { return .single(false) }
    return account.postbox.transaction { transaction -> Bool in
        guard let message = transaction.getMessage(messageId), message.flags.contains(.Incoming) else { return false }
        return message.media.contains(where: { $0 is TelegramMediaImage }) && message.containsSecretMedia
    }
    |> mapToSignal { available -> Signal<Bool, NoError> in
        guard available else { return .single(false) }
        return account.network.request(Api.functions.messages.readMessageContents(id: [messageId.id]))
        |> map { affected -> Bool in
            if case let .affectedMessages(data) = affected {
                account.stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
            }
            return true
        }
        |> `catch` { _ in .single(false) }
        |> mapToSignal { success -> Signal<Bool, NoError> in
            guard success else { return .single(false) }
            return _internal_markMessageContentAsConsumedInteractively(postbox: account.postbox, messageId: messageId, reportToServer: false, allowPrivateConsumption: true)
            |> map { true }
        }
    }
}
