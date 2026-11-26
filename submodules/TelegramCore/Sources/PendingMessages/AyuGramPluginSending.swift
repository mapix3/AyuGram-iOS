import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

func ayuApplyPluginSendHooks(peerId: PeerId, messages: [(Bool, EnqueueMessage)]) -> [(Bool, EnqueueMessage)] {
    guard let hook = AyuGramPluginHooks.beforeSend, peerId.namespace != Namespaces.Peer.SecretChat else {
        return messages
    }
    var result: [(Bool, EnqueueMessage)] = []
    for (transformed, message) in messages {
        guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, !text.isEmpty else {
            result.append((transformed, message))
            continue
        }
        switch hook(peerId.toInt64(), text) {
        case .keep:
            result.append((transformed, message))
            AyuGramPluginHooks.didSend?(peerId.toInt64(), text)
        case .cancel:
            continue
        case let .replace(updated):
            if updated == text {
                result.append((transformed, message))
                AyuGramPluginHooks.didSend?(peerId.toInt64(), text)
                continue
            }
            if updated.isEmpty && mediaReference == nil {
                continue
            }
            let cleaned = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            result.append((transformed, .message(text: updated, attributes: cleaned, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)))
            AyuGramPluginHooks.didSend?(peerId.toInt64(), updated)
        }
    }
    return result
}
