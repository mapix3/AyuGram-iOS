import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit
import SGSimpleSettings


public enum EarliestUnseenPersonalMentionMessageResult: Equatable {
    case loading
    case result(MessageId?)
}


private enum AyuEarliestUnseen {
    case loading
    case result(MessageId?)
    /// The counter has no unseen message behind it; check the server's list once.
    case refetch
}

/// Shared by mentions and reactions. With read receipts hidden, mentions and reactions read
/// here stay unread on the server until a message is sent, and history never loaded has no
/// local copy, so a counter without an unseen message is first checked against the server's
/// list (once) instead of being cleared, and nothing is marked read there. Messages the server
/// brings back that were already read here are read again locally and skipped.
private func ayuEarliestUnseen(account: Account, peerId: PeerId, threadId: Int64?, tag: MessageTags, refetched: Bool, isDeferred: @escaping (Transaction, MessageId) -> Bool, readLocally: @escaping (Transaction, MessageId) -> Void, clear: @escaping (Transaction, MessageId) -> Void) -> Signal<AyuEarliestUnseen, NoError> {
    return account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .lowerBound, anchorIndex: .lowerBound, count: 4, fixedCombinedReadStates: nil, tag: .tag(tag), additionalData: [.peerChatState(peerId)])
    |> mapToSignal { view -> Signal<AyuEarliestUnseen, NoError> in
        if view.0.isLoading {
            return .single(.loading)
        }
        if case .FillHole = view.1 {
            return ayuEarliestUnseen(account: account, peerId: peerId, threadId: threadId, tag: tag, refetched: refetched, isDeferred: isDeferred, readLocally: readLocally, clear: clear)
        }
        let suppressRead = AyuGramSettings.shared.snapshot.suppressRead
        if let message = view.0.entries.first?.message {
            let historyView = view.0
            return account.postbox.transaction { transaction -> Bool in
                guard suppressRead, isDeferred(transaction, message.id) else { return false }
                // The view then moves on to the next one.
                readLocally(transaction, message.id)
                return true
            }
            |> map { skipped -> AyuEarliestUnseen in
                if skipped {
                    return .loading
                }
                switch ayuEarliestUnseenResult(view: historyView, message: message, peerId: peerId) {
                case .loading:
                    return .loading
                case let .result(id):
                    return .result(id)
                }
            }
        }
        return account.postbox.transaction { transaction -> AyuEarliestUnseen in
            if let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud) {
                let staleCount = transaction.getMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: tag, namespace: Namespaces.Message.Cloud, customTag: nil)?.count ?? 0
                if staleCount > 0, !refetched, suppressRead {
                    return .refetch
                }
                transaction.replaceMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: tag, namespace: Namespaces.Message.Cloud, customTag: nil, count: 0, maxId: topId.id)
                
                transaction.removeHole(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .tag(tag), range: 1 ... (Int32.max - 1))
                let ids = transaction.getMessageIndicesWithTag(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, tag: tag).map({ $0.id })
                for id in ids {
                    clear(transaction, id)
                }
            }
            return .result(nil)
        }
    }
    |> take(until: { value in
        switch value {
        case .loading:
            return SignalTakeAction(passthrough: true, complete: false)
        case .result, .refetch:
            return SignalTakeAction(passthrough: true, complete: true)
        }
    })
}

/// Runs the lookup; a `.refetch` reopens the tag's history to the server and looks again.
/// The first lookup has completed by then, so its view cannot start another refetch.
private func ayuEarliestUnseenWithRefetch(account: Account, peerId: PeerId, threadId: Int64?, tag: MessageTags, isDeferred: @escaping (Transaction, MessageId) -> Bool, readLocally: @escaping (Transaction, MessageId) -> Void, clear: @escaping (Transaction, MessageId) -> Void) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    let lookup: (Bool) -> Signal<AyuEarliestUnseen, NoError> = { refetched in
        return ayuEarliestUnseen(account: account, peerId: peerId, threadId: threadId, tag: tag, refetched: refetched, isDeferred: isDeferred, readLocally: readLocally, clear: clear)
    }
    return lookup(false)
    |> mapToSignal { value -> Signal<AyuEarliestUnseen, NoError> in
        guard case .refetch = value else {
            return .single(value)
        }
        return account.postbox.transaction { transaction -> Void in
            transaction.addHole(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .tag(tag), range: 1 ... (Int32.max - 1))
        }
        |> mapToSignal { _ -> Signal<AyuEarliestUnseen, NoError> in
            return lookup(true)
        }
    }
    |> mapToSignal { value -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> in
        switch value {
        case .loading:
            return .single(.loading)
        case let .result(id):
            return .single(.result(id))
        case .refetch:
            // Not produced by a lookup that has already refetched.
            return .single(.result(nil))
        }
    }
    |> distinctUntilChanged
}

func _internal_earliestUnseenPersonalMentionMessage(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    return ayuEarliestUnseenWithRefetch(account: account, peerId: peerId, threadId: threadId, tag: .unseenPersonalMessage, isDeferred: { transaction, id in
        // Also mentions read here by builds that did not remember them: still tagged, but consumed.
        let consumed = transaction.getMessage(id)?.attributes.contains(where: { ($0 as? ConsumablePersonalMentionMessageAttribute)?.consumed == true }) ?? false
        return consumed || ayuIsDeferredMentionRead(transaction: transaction, id: id)
    }, readLocally: { transaction, id in
        ayuConsumeMentionLocally(transaction: transaction, id: id)
    }, clear: { transaction, id in
        markUnseenPersonalMessage(transaction: transaction, id: id, addSynchronizeAction: false)
    })
}

func _internal_earliestUnseenPersonalReactionMessage(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    return ayuEarliestUnseenWithRefetch(account: account, peerId: peerId, threadId: threadId, tag: .unseenReaction, isDeferred: { transaction, id in
        return ayuIsDeferredReactionRead(transaction: transaction, id: id)
    }, readLocally: { transaction, id in
        ayuMarkReactionsSeenLocally(transaction: transaction, id: id)
    }, clear: { transaction, id in
        markUnseenReactionOrPollVotesMessage(transaction: transaction, id: id, addSynchronizeAction: false)
    })
}

/// The lookup's answer for a found message: a channel message from before an invalidated
/// state is not trusted yet.
private func ayuEarliestUnseenResult(view: MessageHistoryView, message: Message, peerId: PeerId) -> EarliestUnseenPersonalMentionMessageResult {
    if peerId.namespace == Namespaces.Peer.CloudChannel {
        var invalidatedPts: Int32?
        for data in view.additionalData {
            if case let .peerChatState(_, state) = data, let state = state as? ChannelState {
                invalidatedPts = state.invalidatedPts
            }
        }
        if let invalidatedPts, let messagePts = message.attributes.compactMap({ ($0 as? ChannelMessageStateVersionAttribute)?.pts }).first, messagePts < invalidatedPts {
            return .loading
        }
    }
    return .result(message.id)
}

func _internal_earliestUnseenPollVoteMessage(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    return account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .lowerBound, anchorIndex: .lowerBound, count: 4, fixedCombinedReadStates: nil, tag: .tag(.unseenPollVote), additionalData: [.peerChatState(peerId)])
    |> mapToSignal { view -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> in
        if view.0.isLoading {
            return .single(.loading)
        }
        if case .FillHole = view.1 {
            return _internal_earliestUnseenPollVoteMessage(account: account, peerId: peerId, threadId: threadId)
        }
        if let message = view.0.entries.first?.message {
            if peerId.namespace == Namespaces.Peer.CloudChannel {
                var invalidatedPts: Int32?
                for data in view.0.additionalData {
                    switch data {
                        case let .peerChatState(_, state):
                            if let state = state as? ChannelState {
                                invalidatedPts = state.invalidatedPts
                            }
                        default:
                            break
                    }
                }
                if let invalidatedPts = invalidatedPts {
                    var messagePts: Int32?
                    for attribute in message.attributes {
                        if let attribute = attribute as? ChannelMessageStateVersionAttribute {
                            messagePts = attribute.pts
                            break
                        }
                    }
                    
                    if let messagePts = messagePts {
                        if messagePts < invalidatedPts {
                            return .single(.loading)
                        }
                    }
                }
                return .single(.result(message.id))
            } else {
                return .single(.result(message.id))
            }
        } else {
            return account.postbox.transaction { transaction -> EarliestUnseenPersonalMentionMessageResult in
                if let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud) {
                    transaction.replaceMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: .unseenPollVote, namespace: Namespaces.Message.Cloud, customTag: nil, count: 0, maxId: topId.id)
                    
                    transaction.removeHole(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .tag(.unseenPollVote), range: 1 ... (Int32.max - 1))
                    let ids = transaction.getMessageIndicesWithTag(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, tag: .unseenPollVote).map({ $0.id })
                    for id in ids {
                        markUnseenReactionOrPollVotesMessage(transaction: transaction, id: id, addSynchronizeAction: false)
                    }
                }
                
                return .result(nil)
            }
        }
    }
    |> distinctUntilChanged
    |> take(until: { value in
        if case .result = value {
            return SignalTakeAction(passthrough: true, complete: true)
        } else {
            return SignalTakeAction(passthrough: true, complete: false)
        }
    })
}
