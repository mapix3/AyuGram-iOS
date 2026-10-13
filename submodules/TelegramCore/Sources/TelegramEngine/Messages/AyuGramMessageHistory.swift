import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

public struct AyuGramHistoryPolicy: Codable, Equatable {
    public var selectedChats: [Int64] = []
    public var savePhotos = true
    public init() {}
}

public struct AyuGramHistoryEntry: Codable, Equatable {
    public let peerId: Int64
    public let messageId: Int32
    public let peerTitle: String
    public let author: String
    public let text: String
    public let event: String
    public let timestamp: Int32
    public var photoFileName: String?
    public var photoResourceId: String?
    public var authorId: Int64?
    public var messageTimestamp: Int32?
    public var mediaKind: String?
    public var mediaTitle: String?
    public var updatedText: String?
}

private struct AyuGramHistory: Codable { var entries: [AyuGramHistoryEntry] }
private let ayuGramHistoryKey = applicationSpecificPreferencesKey(0x415955)
private let ayuGramHistoryPolicyKey = applicationSpecificPreferencesKey(0x415956)

private func archiveDirectory(_ mediaBox: MediaBox) -> URL {
    URL(fileURLWithPath: mediaBox.basePath, isDirectory: true).appendingPathComponent("ayu-message-archive", isDirectory: true)
}

private func archiveFile(_ mediaBox: MediaBox, name: String) -> URL? {
    guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("..") else { return nil }
    return archiveDirectory(mediaBox).appendingPathComponent(name)
}

private func pruneHistory(_ history: inout AyuGramHistory, transaction: Transaction, mediaBox: MediaBox) {
    let previous = history.entries
    let threshold = Int32(Date().timeIntervalSince1970) - 30 * 24 * 60 * 60
    history.entries.removeAll { $0.timestamp < threshold }
    history.entries = Array(history.entries.suffix(200))
    let retained = Set(history.entries.filter { $0.event == "deleted" }.map { MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId) })
    let expired = Set(previous.filter { $0.event == "deleted" }.map { MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId) }).subtracting(retained)
    let tombstones = expired.filter { transaction.getMessage($0)?.ayuHistory?.deletedAt != nil }
    transaction.deleteMessages(Array(tombstones), forEachMedia: { _ in })
    let editedBefore = Set(previous.filter { $0.event == "edited" }.map { MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId) })
    let editedKept = Set(history.entries.filter { $0.event == "edited" }.map { MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId) })
    ayuGramClearLocalEditMarker(transaction: transaction, ids: editedBefore.subtracting(editedKept))
    let keep = Set(history.entries.compactMap { $0.photoFileName })
    let directory = archiveDirectory(mediaBox)
    var total: Int64 = 0
    for entry in history.entries.reversed() {
        guard let name = entry.photoFileName, let url = archiveFile(mediaBox, name: name),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber else { continue }
        total += size.int64Value
        if total > 200 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: url)
            if let index = history.entries.firstIndex(of: entry) { history.entries[index].photoFileName = nil }
        }
    }
    for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !keep.contains(url.lastPathComponent) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Downloads the photos, GIFs, videos and pictures of new messages in Message history
/// chats right away, so a later deletion keeps them even if the chat was never opened.
func ayuGramPrefetchHistoryMedia(postbox: Postbox, ids: [MessageId]) {
    guard AyuGramSettings.shared.snapshot.messageHistory, !ids.isEmpty else { return }
    let mediaBox = postbox.mediaBox
    let _ = (postbox.transaction { transaction -> [(Message, Media, MediaResource, MediaResourceUserContentType)] in
        let policy = transaction.getPreferencesEntry(key: ayuGramHistoryPolicyKey)?.get(AyuGramHistoryPolicy.self) ?? AyuGramHistoryPolicy()
        let selected = Set(policy.selectedChats)
        guard policy.savePhotos, !selected.isEmpty else { return [] }
        var items: [(Message, Media, MediaResource, MediaResourceUserContentType)] = []
        for id in ids where selected.contains(id.peerId.toInt64()) && ayuGramIsHistoryCandidate(transaction: transaction, id: id) {
            guard let message = transaction.getMessage(id) else { continue }
            for media in message.media {
                if let image = media as? TelegramMediaImage, let representation = largestImageRepresentation(image.representations) {
                    items.append((message, image, representation.resource, .image))
                } else if let file = media as? TelegramMediaFile, !file.isSticker, let size = file.size, size <= 20 * 1024 * 1024,
                          file.isVideo || file.isAnimated || file.isVoice || file.isInstantVideo || file.mimeType.hasPrefix("image/") {
                    items.append((message, file, file.resource, MediaResourceUserContentType(file: file)))
                }
            }
        }
        return items
    }
    |> deliverOnMainQueue).startStandalone(next: { items in
        for (message, media, resource, contentType) in items {
            let _ = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(message.id.peerId), userContentType: contentType, reference: .media(media: .message(message: MessageReference(message), media: media), resource: resource)).startStandalone()
        }
    })
}

/// A playable extension for files without a usable name; a voice message without one was saved as .bin.
private func ayuGramFileExtension(_ file: TelegramMediaFile) -> String {
    if file.isVoice { return "ogg" }
    if file.isVideo || file.isInstantVideo || file.isAnimated { return "mp4" }
    switch file.mimeType.lowercased() {
    case "image/jpeg", "image/jpg": return "jpg"
    case "image/png": return "png"
    case "image/gif": return "gif"
    case "image/webp": return "webp"
    case "image/heic": return "heic"
    case "audio/mpeg", "audio/mp3": return "mp3"
    case "audio/ogg", "audio/opus": return "ogg"
    case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
    case "application/pdf": return "pdf"
    default: return "bin"
    }
}

/// Messages Message history may archive: cloud messages outside secret chats that are not
/// copy-protected and carry no secret or self-destructing media. One-time and timer
/// content is meant to disappear, so it is never kept.
func ayuGramIsHistoryCandidate(transaction: Transaction, id: MessageId) -> Bool {
    guard id.namespace == Namespaces.Message.Cloud, id.peerId.namespace != Namespaces.Peer.SecretChat,
          let message = transaction.getMessage(id), !message.isCopyProtected(), !message.containsSecretMedia,
          !message.attributes.contains(where: { $0 is AutoremoveTimeoutMessageAttribute || $0 is AutoclearTimeoutMessageAttribute }) else { return false }
    return !message.text.isEmpty || !message.media.isEmpty
}

/// Messages Save Deleted Messages keeps in chats outside Message history.
func ayuGramIsRetainable(transaction: Transaction, id: MessageId) -> Bool {
    return ayuGramIsHistoryCandidate(transaction: transaction, id: id)
}

@discardableResult
func ayuGramRecordHistory(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], event: String) -> Set<MessageId> {
    guard AyuGramSettings.shared.snapshot.messageHistory else { return [] }
    let policy = transaction.getPreferencesEntry(key: ayuGramHistoryPolicyKey)?.get(AyuGramHistoryPolicy.self) ?? AyuGramHistoryPolicy()
    let selected = Set(policy.selectedChats)
    guard !selected.isEmpty else { return [] }
    var history = transaction.getPreferencesEntry(key: ayuGramHistoryKey)?.get(AyuGramHistory.self) ?? AyuGramHistory(entries: [])
    let now = Int32(Date().timeIntervalSince1970)
    var recorded = Set<MessageId>()
    for id in ids {
        guard selected.contains(id.peerId.toInt64()), ayuGramIsHistoryCandidate(transaction: transaction, id: id),
              let message = transaction.getMessage(id) else { continue }
        if event == "deleted", message.ayuHistory?.deletedAt != nil {
            recorded.insert(id)
            continue
        }
        var kind = "photo"
        var mediaTitle: String?
        var fileExtension = "jpg"
        var source: String?
        var resourceId: String?
        if policy.savePhotos {
            for image in message.media.compactMap({ $0 as? TelegramMediaImage }) {
                for representation in image.representations.sorted(by: { $0.dimensions.width * $0.dimensions.height > $1.dimensions.width * $1.dimensions.height }) {
                    if let path = mediaBox.completedResourcePath(representation.resource) {
                        source = path
                        resourceId = representation.resource.id.stringRepresentation
                        break
                    }
                }
                if source != nil { break }
            }
            if source == nil {
                for file in message.media.compactMap({ $0 as? TelegramMediaFile }) {
                    if let path = mediaBox.completedResourcePath(file.resource) {
                        source = path
                        resourceId = file.resource.id.stringRepresentation
                        // Pictures sent as files, GIFs, round videos and voice messages are shown as such, not as files.
                        kind = file.isInstantVideo ? "round" : file.isVoice ? "voice" : file.isAnimated ? "gif" : file.isVideo ? "video" : file.mimeType.hasPrefix("image/") ? "photo" : "file"
                        mediaTitle = file.fileName
                        if file.isVoice || file.isInstantVideo, let duration = file.duration {
                            let seconds = Int(duration.rounded())
                            mediaTitle = String(format: "%d:%02d", seconds / 60, seconds % 60)
                        }
                        let suffix = URL(fileURLWithPath: file.fileName ?? "").pathExtension
                        fileExtension = !suffix.isEmpty && suffix.count <= 10 && suffix.allSatisfy({ $0.isLetter || $0.isNumber }) ? suffix : ayuGramFileExtension(file)
                        break
                    }
                }
            }
        }
        let text = String(message.text.prefix(4096))
        guard !text.isEmpty || source != nil else { continue }
        if let previous = history.entries.last(where: { $0.peerId == id.peerId.toInt64() && $0.messageId == id.id && $0.event == event }), previous.text == text, previous.photoResourceId == resourceId { recorded.insert(id); continue }
        var fileName: String?
        if let source, let size = (try? FileManager.default.attributesOfItem(atPath: source)[.size]) as? NSNumber, size.int64Value <= 20 * 1024 * 1024 {
            let name = UUID().uuidString + "." + fileExtension
            let directory = archiveDirectory(mediaBox)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                var excluded = directory
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? excluded.setResourceValues(values)
                if let destination = archiveFile(mediaBox, name: name) {
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: destination)
                    fileName = name
                }
            } catch { fileName = nil }
        }
        guard !text.isEmpty || fileName != nil else { continue }
        history.entries.append(AyuGramHistoryEntry(peerId: id.peerId.toInt64(), messageId: id.id, peerTitle: String((transaction.getPeer(id.peerId)?.debugDisplayTitle ?? "").prefix(256)), author: String((message.author?.debugDisplayTitle ?? "").prefix(256)), text: text, event: event, timestamp: now, photoFileName: fileName, photoResourceId: resourceId, authorId: message.author?.id.toInt64(), messageTimestamp: message.timestamp, mediaKind: kind, mediaTitle: mediaTitle))
        recorded.insert(id)
    }
    pruneHistory(&history, transaction: transaction, mediaBox: mediaBox)
    transaction.setPreferencesEntry(key: ayuGramHistoryKey, value: PreferencesEntry(history))
    let kept = Set(history.entries.filter { $0.event == event }.map { MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId) })
    return recorded.intersection(kept)
}

func ayuGramCompleteEditSnapshot(transaction: Transaction, id: MessageId, updatedText: String) {
    guard var history = transaction.getPreferencesEntry(key: ayuGramHistoryKey)?.get(AyuGramHistory.self), let index = history.entries.lastIndex(where: { $0.peerId == id.peerId.toInt64() && $0.messageId == id.id && $0.event == "edited" }) else { return }
    history.entries[index].updatedText = String(updatedText.prefix(4096))
    transaction.setPreferencesEntry(key: ayuGramHistoryKey, value: PreferencesEntry(history))
}

func ayuGramRetainedMedia(transaction: Transaction, mediaBox: MediaBox, message: Message) -> [Media] {
    guard let history = transaction.getPreferencesEntry(key: ayuGramHistoryKey)?.get(AyuGramHistory.self), let entry = history.entries.last(where: { $0.peerId == message.id.peerId.toInt64() && $0.messageId == message.id.id && $0.event == "deleted" }), let name = entry.photoFileName, let sourceId = entry.photoResourceId, let url = archiveFile(mediaBox, name: name), let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber else { return message.media }
    let randomId = Int64.random(in: Int64.min ... Int64.max)
    let resource = LocalFileReferenceMediaResource(localFilePath: url.path, randomId: randomId, size: size.int64Value)
    return message.media.map { media in
        if let image = media as? TelegramMediaImage, let representation = image.representations.first(where: { $0.resource.id.stringRepresentation == sourceId }) {
            let local = TelegramMediaImageRepresentation(dimensions: representation.dimensions, resource: resource, progressiveSizes: [], immediateThumbnailData: representation.immediateThumbnailData)
            return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: randomId), representations: [local], immediateThumbnailData: image.immediateThumbnailData, emojiMarkup: image.emojiMarkup, reference: nil, partialReference: nil, flags: image.flags)
        }
        if let file = media as? TelegramMediaFile, file.resource.id.stringRepresentation == sourceId {
            return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: randomId), partialReference: nil, resource: resource, previewRepresentations: file.previewRepresentations, videoThumbnails: file.videoThumbnails, videoCover: file.videoCover, immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])
        }
        return media
    }
}

public extension TelegramEngine {
    func ayuGramHistoryPolicy() -> Signal<(AyuGramHistoryPolicy, [EnginePeer]), NoError> {
        return self.account.postbox.transaction { transaction in
            let policy = transaction.getPreferencesEntry(key: ayuGramHistoryPolicyKey)?.get(AyuGramHistoryPolicy.self) ?? AyuGramHistoryPolicy()
            return (policy, policy.selectedChats.compactMap { transaction.getPeer(PeerId($0)).map(EnginePeer.init) })
        }
    }
    func ayuGramSetHistoryPolicy(_ policy: AyuGramHistoryPolicy) -> Signal<Void, NoError> {
        return self.account.postbox.transaction { transaction in
            var policy = policy
            policy.selectedChats = Array(Set(policy.selectedChats)).sorted()
            transaction.setPreferencesEntry(key: ayuGramHistoryPolicyKey, value: PreferencesEntry(policy))
        }
    }
    func ayuGramArchivedPhotoURL(_ name: String) -> URL? { archiveFile(self.account.postbox.mediaBox, name: name) }
    /// Removes a single history record. If it was the last entry for a deleted
    /// message, its local tombstone and archived file are removed too.
    func ayuGramDeleteHistoryEntry(peerId: Int64, messageId: Int32, event: String, timestamp: Int32) -> Signal<Void, NoError> {
        return self.account.postbox.transaction { transaction in
            guard var history = transaction.getPreferencesEntry(key: ayuGramHistoryKey)?.get(AyuGramHistory.self),
                  let index = history.entries.firstIndex(where: { $0.peerId == peerId && $0.messageId == messageId && $0.event == event && $0.timestamp == timestamp }) else { return }
            history.entries.remove(at: index)
            let id = MessageId(peerId: PeerId(peerId), namespace: Namespaces.Message.Cloud, id: messageId)
            let stillReferenced = history.entries.contains { $0.peerId == peerId && $0.messageId == messageId && $0.event == event }
            if !stillReferenced {
                if event == "deleted", transaction.getMessage(id)?.ayuHistory?.deletedAt != nil {
                    transaction.deleteMessages([id], forEachMedia: { _ in })
                } else if event == "edited" {
                    ayuGramClearLocalEditMarker(transaction: transaction, ids: [id])
                }
            }
            pruneHistory(&history, transaction: transaction, mediaBox: self.account.postbox.mediaBox)
            transaction.setPreferencesEntry(key: ayuGramHistoryKey, value: PreferencesEntry(history))
        }
    }
    func ayuGramMessageHistory() -> Signal<[AyuGramHistoryEntry], NoError> {
        return self.account.postbox.transaction { transaction -> Void in
            var history = transaction.getPreferencesEntry(key: ayuGramHistoryKey)?.get(AyuGramHistory.self) ?? AyuGramHistory(entries: [])
            pruneHistory(&history, transaction: transaction, mediaBox: self.account.postbox.mediaBox)
            transaction.setPreferencesEntry(key: ayuGramHistoryKey, value: PreferencesEntry(history))
        }
        |> mapToSignal { _ in
            self.account.postbox.preferencesView(keys: [ayuGramHistoryKey])
            |> map { view in Array((view.values[ayuGramHistoryKey]?.get(AyuGramHistory.self)?.entries ?? []).reversed()) }
        }
    }
    func ayuGramClearMessageHistory() -> Signal<Void, NoError> {
        return self.account.postbox.transaction { transaction in
            var empty = AyuGramHistory(entries: [])
            var old = transaction.getPreferencesEntry(key: ayuGramHistoryKey)?.get(AyuGramHistory.self) ?? empty
            let ids = Set(old.entries.filter { $0.event == "deleted" }.map { MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId) })
            transaction.deleteMessages(Array(ids.filter { transaction.getMessage($0)?.ayuHistory?.deletedAt != nil }), forEachMedia: { _ in })
            let edits = Set(old.entries.filter { $0.event == "edited" }.map { MessageId(peerId: PeerId($0.peerId), namespace: Namespaces.Message.Cloud, id: $0.messageId) })
            ayuGramClearLocalEditMarker(transaction: transaction, ids: edits)
            old.entries.removeAll()
            pruneHistory(&empty, transaction: transaction, mediaBox: self.account.postbox.mediaBox)
            transaction.setPreferencesEntry(key: ayuGramHistoryKey, value: nil)
        }
    }
}
