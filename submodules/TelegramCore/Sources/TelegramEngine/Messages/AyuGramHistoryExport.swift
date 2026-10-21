import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

/// One page of a chat's history straight from the server, newest first: up to `limit` messages
/// older than `offsetId` (0 starts from the newest). `totalCount` is the server's count for the
/// whole chat. Nil when the request fails; an empty page means the start of the chat was reached.
/// Nothing is stored in the local history.
func _internal_ayuExportHistoryPage(account: Account, peerId: PeerId, offsetId: Int32, limit: Int32) -> Signal<(messages: [Message], totalCount: Int)?, NoError> {
    let accountPeerId = account.peerId
    return account.postbox.transaction { transaction -> Peer? in
        return transaction.getPeer(peerId)
    }
    |> mapToSignal { peer -> Signal<(messages: [Message], totalCount: Int)?, NoError> in
        guard let peer = peer, let inputPeer = apiInputPeer(peer) else {
            return .single(nil)
        }
        return account.network.request(Api.functions.messages.getHistory(peer: inputPeer, offsetId: offsetId, offsetDate: 0, addOffset: 0, limit: limit, maxId: Int32.max - 1, minId: 0, hash: 0))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.messages.Messages?, NoError> in
            return .single(nil)
        }
        |> map { result -> (messages: [Message], totalCount: Int)? in
            guard let result = result else {
                return nil
            }
            let apiMessages: [Api.Message]
            let apiChats: [Api.Chat]
            let apiUsers: [Api.User]
            let totalCount: Int
            switch result {
            case let .channelMessages(channelMessagesData):
                apiMessages = channelMessagesData.messages
                apiChats = channelMessagesData.chats
                apiUsers = channelMessagesData.users
                totalCount = Int(channelMessagesData.count)
            case let .messages(messagesData):
                apiMessages = messagesData.messages
                apiChats = messagesData.chats
                apiUsers = messagesData.users
                totalCount = messagesData.messages.count
            case let .messagesSlice(messagesSliceData):
                apiMessages = messagesSliceData.messages
                apiChats = messagesSliceData.chats
                apiUsers = messagesSliceData.users
                totalCount = Int(messagesSliceData.count)
            case .messagesNotModified:
                apiMessages = []
                apiChats = []
                apiUsers = []
                totalCount = 0
            }

            var peers: [PeerId: Peer] = [:]
            peers[peer.id] = peer
            for chat in apiChats {
                if let groupOrChannel = parseTelegramGroupOrChannel(chat: chat) {
                    peers[groupOrChannel.id] = groupOrChannel
                }
            }
            for user in apiUsers {
                let telegramUser = TelegramUser(user: user)
                peers[telegramUser.id] = telegramUser
            }

            var messages: [Message] = []
            for apiMessage in apiMessages {
                if let storeMessage = StoreMessage(apiMessage: apiMessage, accountPeerId: accountPeerId, peerIsForum: peer.isForumOrMonoForum), let message = locallyRenderedMessage(message: storeMessage, peers: peers) {
                    messages.append(message)
                }
            }
            messages.sort(by: { $0.index > $1.index })
            return (messages: messages, totalCount: max(totalCount, messages.count))
        }
    }
}
