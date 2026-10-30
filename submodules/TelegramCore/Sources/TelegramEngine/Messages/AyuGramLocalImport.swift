import Foundation
import Postbox
import SwiftSignalKit

public struct AyuGramImportedAttachment: Equatable {
    public enum Kind: Equatable {
        case photo
        case video
        case sticker
        case voice
        case file
    }

    public let kind: Kind
    public let path: String
    public let fileName: String
    public let mimeType: String
    public let width: Int32
    public let height: Int32
    public let duration: Double
    public let thumbnailPath: String?

    public init(kind: Kind, path: String, fileName: String, mimeType: String, width: Int32, height: Int32, duration: Double, thumbnailPath: String?) {
        self.kind = kind
        self.path = path
        self.fileName = fileName
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.duration = duration
        self.thumbnailPath = thumbnailPath
    }
}

public struct AyuGramImportedMessage: Equatable {
    public let timestamp: Int32
    public let incoming: Bool
    public let text: String
    public let attachment: AyuGramImportedAttachment?

    public init(timestamp: Int32, incoming: Bool, text: String, attachment: AyuGramImportedAttachment? = nil) {
        self.timestamp = timestamp
        self.incoming = incoming
        self.text = text
        self.attachment = attachment
    }
}

private func ayuImportStore(mediaBox: MediaBox, path: String) -> LocalFileMediaResource? {
    guard let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber, size.int64Value > 0 else {
        return nil
    }
    let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max), size: size.int64Value)
    let destination = mediaBox.storePathsForId(resource.id).complete
    let _ = try? FileManager.default.removeItem(atPath: destination)
    do {
        try FileManager.default.moveItem(atPath: path, toPath: destination)
    } catch {
        return nil
    }
    return resource
}

private func ayuImportMedia(mediaBox: MediaBox, attachment: AyuGramImportedAttachment) -> Media? {
    guard let resource = ayuImportStore(mediaBox: mediaBox, path: attachment.path) else {
        return nil
    }
    let dimensions = PixelDimensions(width: max(1, attachment.width), height: max(1, attachment.height))
    let fileId = MediaId(namespace: Namespaces.Media.LocalFile, id: resource.fileId)
    switch attachment.kind {
    case .photo:
        let representation = TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: nil)
        return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: resource.fileId), representations: [representation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    case .video:
        var previews: [TelegramMediaImageRepresentation] = []
        if let thumbnailPath = attachment.thumbnailPath, let thumbnail = ayuImportStore(mediaBox: mediaBox, path: thumbnailPath) {
            previews.append(TelegramMediaImageRepresentation(dimensions: dimensions, resource: thumbnail, progressiveSizes: [], immediateThumbnailData: nil))
        }
        return TelegramMediaFile(fileId: fileId, partialReference: nil, resource: resource, previewRepresentations: previews, videoThumbnails: [], immediateThumbnailData: nil, mimeType: attachment.mimeType, size: resource.size, attributes: [.Video(duration: attachment.duration, size: dimensions, flags: [.supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: nil), .FileName(fileName: attachment.fileName)], alternativeRepresentations: [])
    case .sticker:
        return TelegramMediaFile(fileId: fileId, partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: attachment.mimeType, size: resource.size, attributes: [.Sticker(displayText: "", packReference: nil, maskData: nil), .ImageSize(size: dimensions), .FileName(fileName: attachment.fileName)], alternativeRepresentations: [])
    case .voice:
        return TelegramMediaFile(fileId: fileId, partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: attachment.mimeType, size: resource.size, attributes: [.Audio(isVoice: true, duration: Int(attachment.duration), title: nil, performer: nil, waveform: nil)], alternativeRepresentations: [])
    case .file:
        return TelegramMediaFile(fileId: fileId, partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: attachment.mimeType, size: resource.size, attributes: [.FileName(fileName: attachment.fileName)], alternativeRepresentations: [])
    }
}

public extension TelegramEngine {
    func ayuGramImportLocally(peerId: EnginePeer.Id, messages: [AyuGramImportedMessage]) -> Signal<Int, NoError> {
        let accountPeerId = self.account.peerId
        let mediaBox = self.account.postbox.mediaBox
        return self.account.postbox.transaction { transaction -> Int in
            guard transaction.getPeer(peerId) != nil else {
                return 0
            }
            let stored = messages.compactMap { message -> StoreMessage? in
                let media: [Media] = message.attachment.flatMap { ayuImportMedia(mediaBox: mediaBox, attachment: $0) }.map { [$0] } ?? []
                var text = message.text
                if media.isEmpty, let attachment = message.attachment {
                    text = text.isEmpty ? "📎 " + attachment.fileName : "📎 " + attachment.fileName + "\n" + text
                }
                if text.isEmpty && media.isEmpty {
                    return nil
                }
                let tags = tagsForStoreMessage(incoming: message.incoming, attributes: [], media: media, textEntities: nil, isPinned: false).0
                return StoreMessage(peerId: peerId, namespace: Namespaces.Message.Local, customStableId: nil, globallyUniqueId: Int64.random(in: Int64.min ... Int64.max), groupingKey: nil, threadId: nil, timestamp: message.timestamp, flags: message.incoming ? [.Incoming] : [], tags: tags, globalTags: [], localTags: [], forwardInfo: nil, authorId: message.incoming ? peerId : accountPeerId, text: text, attributes: [], media: media)
            }
            var index = 0
            while index < stored.count {
                let end = min(index + 500, stored.count)
                let _ = transaction.addMessages(Array(stored[index ..< end]), location: .Random)
                index = end
            }
            return stored.count
        }
    }
}
