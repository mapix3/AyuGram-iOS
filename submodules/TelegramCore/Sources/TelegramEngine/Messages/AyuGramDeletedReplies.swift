import Foundation
import Postbox
import SwiftSignalKit

private let ayuDeletedReplyQuoteLimit = 200

private func ayuDeletedReplyMediaLabel(_ message: Message) -> String {
    for media in message.media {
        if media is TelegramMediaImage {
            return "🖼"
        } else if let file = media as? TelegramMediaFile {
            if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                for attribute in file.attributes {
                    if case let .Sticker(displayText, _, _) = attribute, !displayText.isEmpty {
                        return displayText
                    }
                }
                return "🏷"
            } else if file.isVoice {
                return "🎤"
            } else if file.isInstantVideo || file.isVideo {
                return "📹"
            } else if file.isMusic {
                return "🎵"
            }
            return "📎"
        } else if media is TelegramMediaMap {
            return "📍"
        } else if media is TelegramMediaContact {
            return "👤"
        } else if media is TelegramMediaPoll {
            return "📊"
        }
    }
    return "💬"
}

func ayuPrepareDeletedReplies(account: Account, messages: [(Bool, EnqueueMessage)]) -> Signal<[(Bool, EnqueueMessage)], NoError> {
    let hasReplies = messages.contains(where: { _, message in
        if case let .message(_, _, _, _, _, replyToMessageId, _, _, _, _) = message, let replyToMessageId, replyToMessageId.messageId.namespace == Namespaces.Message.Cloud {
            return true
        }
        return false
    })
    if !hasReplies {
        return .single(messages)
    }
    return account.postbox.transaction { transaction -> [(Bool, EnqueueMessage)] in
        return messages.map { transformed, message -> (Bool, EnqueueMessage) in
            guard case let .message(text, attributes, _, _, _, replyToMessageId, _, _, _, _) = message, let replyToMessageId, let source = transaction.getMessage(replyToMessageId.messageId), source.flags.contains(.AyuLocallyDeleted) else {
                return (transformed, message)
            }
            let author = source.author ?? transaction.getPeer(source.id.peerId)
            let name = author?.debugDisplayTitle ?? ""
            var quote = replyToMessageId.quote?.text ?? source.text
            quote = quote.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            if quote.isEmpty {
                quote = ayuDeletedReplyMediaLabel(source)
            } else if quote.count > ayuDeletedReplyQuoteLimit {
                quote = String(quote.prefix(ayuDeletedReplyQuoteLimit)) + "…"
            }
            let header = name.isEmpty ? quote : name + ": " + quote
            let headerLength = (header as NSString).length
            let nameLength = (name as NSString).length
            var entities: [MessageTextEntity] = [MessageTextEntity(range: 0 ..< headerLength, type: .BlockQuote(isCollapsed: false))]
            if nameLength > 0, let author {
                if author is TelegramUser {
                    entities.append(MessageTextEntity(range: 0 ..< nameLength, type: .TextMention(peerId: author.id)))
                } else {
                    entities.append(MessageTextEntity(range: 0 ..< nameLength, type: .Bold))
                }
            }
            let offset = headerLength + 1
            let existing = attributes.compactMap({ $0 as? TextEntitiesMessageAttribute }).first?.entities ?? []
            for entity in existing {
                entities.append(MessageTextEntity(range: (entity.range.lowerBound + offset) ..< (entity.range.upperBound + offset), type: entity.type))
            }
            var updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            updatedAttributes.append(TextEntitiesMessageAttribute(entities: entities))
            let updatedText = text.isEmpty ? header : header + "\n" + text
            guard case let .message(_, _, inlineStickers, mediaReference, threadId, _, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else {
                return (transformed, message)
            }
            return (transformed, .message(text: updatedText, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: nil, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets))
        }
    }
}
