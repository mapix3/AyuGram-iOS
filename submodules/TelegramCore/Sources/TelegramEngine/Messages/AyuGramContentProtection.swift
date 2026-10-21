import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

/// Local AyuGram option: treat "Restrict saving content" chats and messages
/// like ordinary ones on this device (save, copy, share, forward).
public func ayuGramIgnoresCopyProtection() -> Bool {
    return AyuGramSettings.shared.extra.ignoreCopyProtection
}

/// Raw server-side protection of the source, independent of the local option.
/// The server rejects messages.forwardMessages for these sources.
private func ayuIsSourceCopyProtected(transaction: Transaction, message: Message) -> Bool {
    if message.flags.contains(.CopyProtected) {
        return true
    }
    if let group = transaction.getPeer(message.id.peerId) as? TelegramGroup, group.flags.contains(.copyProtectionEnabled) {
        return true
    }
    if let channel = transaction.getPeer(message.id.peerId) as? TelegramChannel, channel.flags.contains(.copyProtectionEnabled) {
        return true
    }
    if let cachedUserData = transaction.getPeerCachedData(peerId: message.id.peerId) as? CachedUserData, cachedUserData.flags.contains(.copyProtectionEnabled) || cachedUserData.flags.contains(.myCopyProtectionEnabled) {
        return true
    }
    return false
}

/// Forwards from protected sources are sent as new messages: text and entities
/// are copied and photos/files are downloaded and uploaded again, because the
/// server refuses both forwarding and reusing the protected media references.
/// A source that cannot be copied keeps its original forward request.
/// Deleted messages AyuGram kept no longer exist on the server either, so forwarding them is
/// also refused; they are sent as new messages from you the same way, whatever the option.
func ayuPrepareProtectedForwards(account: Account, peerId: PeerId, messages: [(Bool, EnqueueMessage)]) -> Signal<[(Bool, EnqueueMessage)], NoError> {
    guard peerId.namespace != Namespaces.Peer.SecretChat else {
        return .single(messages)
    }
    let ignoresProtection = ayuGramIgnoresCopyProtection()
    let hasForwards = messages.contains(where: { _, message in
        if case .forward = message {
            return true
        } else {
            return false
        }
    })
    if !hasForwards {
        return .single(messages)
    }
    return account.postbox.transaction { transaction -> [Int: Message] in
        var result: [Int: Message] = [:]
        for i in 0 ..< messages.count {
            if case let .forward(sourceId, _, _, _, _) = messages[i].1, sourceId.namespace == Namespaces.Message.Cloud, let source = transaction.getMessage(sourceId), source.flags.contains(.AyuLocallyDeleted) || (ignoresProtection && ayuIsSourceCopyProtected(transaction: transaction, message: source)) {
                result[i] = source
            }
        }
        return result
    }
    |> mapToSignal { protectedSources -> Signal<[(Bool, EnqueueMessage)], NoError> in
        if protectedSources.isEmpty {
            return .single(messages)
        }
        var groupingKeys: [Int64: Int64] = [:]
        var signals: [Signal<(Bool, EnqueueMessage), NoError>] = []
        for i in 0 ..< messages.count {
            let original = messages[i]
            guard let source = protectedSources[i], case let .forward(_, threadId, grouping, attributes, correlationId) = original.1 else {
                signals.append(.single(original))
                continue
            }
            var localGroupingKey: Int64?
            if case .auto = grouping, let sourceKey = source.groupingKey {
                if let current = groupingKeys[sourceKey] {
                    localGroupingKey = current
                } else {
                    let value = Int64.random(in: 1 ... Int64.max)
                    groupingKeys[sourceKey] = value
                    localGroupingKey = value
                }
            }
            signals.append(ayuCopyProtectedMessage(account: account, peerId: peerId, source: source, threadId: threadId, attributes: attributes, correlationId: correlationId, localGroupingKey: localGroupingKey)
            |> map { copy -> (Bool, EnqueueMessage) in
                return copy ?? original
            })
        }
        return combineLatest(signals)
    }
}

private func ayuCopyProtectedMessage(account: Account, peerId: PeerId, source: Message, threadId: Int64?, attributes: [MessageAttribute], correlationId: Int64?, localGroupingKey: Int64?) -> Signal<(Bool, EnqueueMessage)?, NoError> {
    var hideCaptions = false
    var outgoingAttributes: [MessageAttribute] = []
    for attribute in attributes {
        if let options = attribute as? ForwardOptionsMessageAttribute {
            hideCaptions = options.hideCaptions
        } else {
            outgoingAttributes.append(attribute)
        }
    }
    let media = source.media.first(where: { !($0 is TelegramMediaWebpage) })
    let hasCaptionMedia = media.flatMap { $0 is TelegramMediaImage || $0 is TelegramMediaFile } ?? false
    let text = hideCaptions && hasCaptionMedia ? "" : source.text
    if !text.isEmpty, let entities = source.textEntitiesAttribute?.entities, !entities.isEmpty {
        outgoingAttributes.append(TextEntitiesMessageAttribute(entities: entities))
    }
    let messageAttributes = outgoingAttributes
    let replyToMessageId = threadId.flatMap { EngineMessageReplySubject(messageId: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: $0)), quote: nil, innerSubject: nil) }

    func makeMessage(_ mediaReference: AnyMediaReference?) -> (Bool, EnqueueMessage) {
        return (true, .message(text: text, attributes: messageAttributes, inlineStickers: [:], mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: nil, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: []))
    }

    // The media of a deleted message may be gone from the server; its text is still sent.
    let textOnlyFallback: (Bool, EnqueueMessage)? = source.flags.contains(.AyuLocallyDeleted) && !text.isEmpty ? makeMessage(nil) : nil

    guard let media else {
        if text.isEmpty {
            return .single(nil)
        }
        return .single(makeMessage(nil))
    }
    if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
        return ayuLocalResourceCopy(account: account, source: source, media: image, resource: largest.resource, size: nil)
        |> map { resource -> (Bool, EnqueueMessage)? in
            guard let resource else {
                return textOnlyFallback
            }
            let copy = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: [TelegramMediaImageRepresentation(dimensions: largest.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil)], immediateThumbnailData: image.immediateThumbnailData, reference: nil, partialReference: nil, flags: [])
            return makeMessage(.standalone(media: copy))
        }
    } else if let file = media as? TelegramMediaFile {
        if file.isSticker || file.isAnimatedSticker || file.isVideoSticker || file.isCustomEmoji {
            // Pack stickers are public documents and stay reusable.
            return .single(makeMessage(.standalone(media: file)))
        }
        return ayuLocalResourceCopy(account: account, source: source, media: file, resource: file.resource, size: file.size)
        |> map { resource -> (Bool, EnqueueMessage)? in
            guard let resource else {
                return textOnlyFallback
            }
            let copy = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])
            return makeMessage(.standalone(media: copy))
        }
    } else if media is TelegramMediaContact {
        return .single(makeMessage(.standalone(media: media)))
    } else if let map = media as? TelegramMediaMap, map.liveBroadcastingTimeout == nil {
        return .single(makeMessage(.standalone(media: map)))
    } else {
        return .single(nil)
    }
}

/// Downloads the source resource (if needed) and copies it into a new local
/// resource, so the pending message manager uploads it as a new file.
private func ayuLocalResourceCopy(account: Account, source: Message, media: Media, resource: MediaResource, size: Int64?) -> Signal<TelegramMediaResource?, NoError> {
    // A kept deleted message points at AyuGram's archived copy, which is uploaded from there.
    if let archived = resource as? LocalFileReferenceMediaResource {
        guard FileManager.default.fileExists(atPath: archived.localFilePath) else {
            return .single(nil)
        }
        return .single(LocalFileReferenceMediaResource(localFilePath: archived.localFilePath, randomId: Int64.random(in: Int64.min ... Int64.max), size: archived.size))
    }
    let mediaBox = account.postbox.mediaBox
    let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(source.id.peerId), userContentType: .other, reference: .media(media: .message(message: MessageReference(source), media: media), resource: resource))
    let data = mediaBox.resourceData(resource)
    |> filter { $0.complete }
    |> take(1)
    return Signal { subscriber in
        let fetchDisposable = fetch.start(error: { _ in
            subscriber.putNext(nil)
            subscriber.putCompletion()
        })
        let dataDisposable = data.start(next: { _ in
            let localResource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: size)
            mediaBox.copyResourceData(from: resource.id, to: localResource.id, synchronous: true)
            subscriber.putNext(localResource as TelegramMediaResource)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetchDisposable.dispose()
            dataDisposable.dispose()
        }
    }
}
