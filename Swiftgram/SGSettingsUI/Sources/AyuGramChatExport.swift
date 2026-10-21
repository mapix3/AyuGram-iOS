import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import SaveProgressScreen
import ZipArchive
import SGStrings

// Chat export in the WhatsApp (iOS) format that Telegram's own chat importer reads:
// a ZIP with `_chat.txt` and the attachments named the way the importer recognizes them.

/// Files larger than this are left out of the archive.
private let ayuExportMaxFileSize: Int64 = 1024 * 1024 * 1024

private let ayuExportEncryptionNotice = "\u{200E}Messages and calls are end-to-end encrypted. No one outside of this chat, not even WhatsApp, can read or listen to them."

private enum AyuExportMediaKind {
    case photo
    case video
    case sticker
    case voice
    case file(String)
}

private struct AyuExportAttachment {
    let messageId: EngineMessage.Id
    let timestamp: Int32
    let kind: AyuExportMediaKind
    let reference: MediaResourceReference
    let contentType: MediaResourceUserContentType
}

/// The media of a message that goes into the archive, if any.
private func ayuExportAttachment(message: EngineMessage) -> AyuExportAttachment? {
    let messageReference = MessageReference(message._asMessage())
    for media in message.media {
        if let image = media as? TelegramMediaImage {
            guard let representation = largestImageRepresentation(image.representations) else {
                continue
            }
            let reference = ImageMediaReference.message(message: messageReference, media: image).resourceReference(representation.resource)
            return AyuExportAttachment(messageId: message.id, timestamp: message.timestamp, kind: .photo, reference: reference, contentType: .image)
        } else if let file = media as? TelegramMediaFile {
            if let size = file.size, size > ayuExportMaxFileSize {
                continue
            }
            let kind: AyuExportMediaKind
            if file.isSticker {
                // Only static WebP stickers are importable; animated and video stickers are left out.
                guard file.mimeType == "image/webp", !file.isAnimatedSticker, !file.isVideoSticker else {
                    continue
                }
                kind = .sticker
            } else if file.isVoice {
                kind = .voice
            } else if file.isVideo || file.isInstantVideo || file.isAnimated {
                kind = .video
            } else {
                kind = .file(file.fileName ?? "file")
            }
            let reference = FileMediaReference.message(message: messageReference, media: file).resourceReference(file.resource)
            return AyuExportAttachment(messageId: message.id, timestamp: message.timestamp, kind: kind, reference: reference, contentType: MediaResourceUserContentType(file: file))
        }
    }
    return nil
}

/// The path of the complete resource: taken from the media box when it is already there,
/// otherwise (when `fetch` is set) downloaded. Nil when it cannot be had.
private func ayuExportResourcePath(context: AccountContext, peerId: EnginePeer.Id, attachment: AyuExportAttachment, fetch: Bool) -> Signal<String?, NoError> {
    // Kept copies of deleted messages point at AyuGram's own archive file.
    if let local = attachment.reference.resource as? LocalFileReferenceMediaResource {
        return .single(FileManager.default.fileExists(atPath: local.localFilePath) ? local.localFilePath : nil)
    }
    let resource = EngineMediaResource(attachment.reference.resource)
    if let path = context.engine.resources.completedResourcePath(id: resource.id) {
        return .single(path)
    }
    if !fetch {
        return .single(nil)
    }
    return Signal { subscriber in
        let fetchDisposable = context.engine.resources.fetch(reference: attachment.reference, userLocation: .peer(peerId), userContentType: attachment.contentType).startStandalone(error: { _ in
            subscriber.putNext(nil)
            subscriber.putCompletion()
        })
        let dataDisposable = (context.engine.resources.data(resource: resource)
        |> filter { data in
            return data.isComplete
        }
        |> take(1)).startStandalone(next: { data in
            subscriber.putNext(data.path)
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetchDisposable.dispose()
            dataDisposable.dispose()
        }
    }
}

private func ayuExportDateFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = format
    return formatter
}

private func ayuExportSingleLine(_ text: String) -> String {
    return text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
}

private func ayuExportSafeFileName(_ name: String) -> String {
    var result = name
    for character in ["/", "\\", ":", "\0", "\r", "\n"] {
        result = result.replacingOccurrences(of: character, with: "_")
    }
    result = result.trimmingCharacters(in: .whitespaces)
    if result.isEmpty || result == "." || result == ".." {
        return "file"
    }
    return result
}

/// One export run: collects the media, writes `_chat.txt`, zips everything and shows the share
/// sheet. Owned by the progress screen's cancel handler, so dismissing the screen ends it.
private final class AyuExportJob {
    let context: AccountContext
    let peerId: EnginePeer.Id
    let locale: String
    weak var progress: SaveProgressScreen?
    let disposable = MetaDisposable()
    private(set) var isCancelled = false

    init(context: AccountContext, peerId: EnginePeer.Id, progress: SaveProgressScreen) {
        self.context = context
        self.peerId = peerId
        self.locale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        self.progress = progress
    }

    deinit {
        self.disposable.dispose()
    }

    func cancel() {
        self.isCancelled = true
        self.disposable.dispose()
    }

    func update(_ text: String, _ value: Float) {
        if !self.isCancelled {
            self.progress?.content = .progress(text, max(0.0, min(1.0, value)))
        }
    }

    func fail(_ text: String) {
        guard !self.isCancelled else {
            return
        }
        self.isCancelled = true
        self.disposable.set(nil)
        self.progress?.dismiss()
        let data = self.context.sharedContext.currentPresentationData.with { $0 }
        self.context.sharedContext.mainWindow?.present(textAlertController(context: self.context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), on: .root)
    }

    /// Writes the archive from `messages` (any order). `fetchMedia` downloads media that is not in
    /// the media box yet; otherwise only what is already on the device is included.
    func writeArchive(title: String, messages: [EngineMessage], includeMedia: Bool, fetchMedia: Bool) {
        let context = self.context
        let _ = (context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: self.peerId),
            TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)
        )
        |> deliverOnMainQueue).startStandalone(next: { [weak self] peer, accountPeer in
            guard let self, !self.isCancelled else {
                return
            }
            var isPrivate = false
            if case .user? = peer {
                isPrivate = true
            } else if peer == nil, self.peerId.namespace == Namespaces.Peer.CloudUser {
                isPrivate = true
            }
            let ownName = ayuExportSingleLine(accountPeer?.debugDisplayTitle ?? "Me")
            let sorted = messages.filter { message in
                return !message.media.contains(where: { $0 is TelegramMediaAction })
            }.sorted(by: { $0.index < $1.index })
            if sorted.isEmpty {
                self.fail(i18n("Ayu.ExportChatEmpty", self.locale))
                return
            }
            let attachments = sorted.compactMap { message in
                return ayuExportAttachment(message: message)
            }
            self.collectMedia(attachments: includeMedia ? attachments : [], index: 0, fetch: fetchMedia, paths: [:], completion: { [weak self] paths in
                self?.finish(title: title, messages: sorted, isPrivate: isPrivate, ownName: ownName, attachments: attachments, paths: paths)
            })
        })
    }

    private func collectMedia(attachments: [AyuExportAttachment], index: Int, fetch: Bool, paths: [EngineMessage.Id: String], completion: @escaping ([EngineMessage.Id: String]) -> Void) {
        guard !self.isCancelled else {
            return
        }
        if index >= attachments.count {
            completion(paths)
            return
        }
        self.update(i18n("Ayu.ExportChatDownloading", self.locale, "\(index + 1) / \(attachments.count)"), Float(index) / Float(attachments.count))
        let attachment = attachments[index]
        self.disposable.set((ayuExportResourcePath(context: self.context, peerId: self.peerId, attachment: attachment, fetch: fetch)
        |> take(1)
        |> deliverOnMainQueue).startStrict(next: { [weak self] path in
            guard let self else {
                return
            }
            var paths = paths
            if let path {
                paths[attachment.messageId] = path
            }
            self.collectMedia(attachments: attachments, index: index + 1, fetch: fetch, paths: paths, completion: completion)
        }))
    }

    private func finish(title: String, messages: [EngineMessage], isPrivate: Bool, ownName: String, attachments: [AyuExportAttachment], paths: [EngineMessage.Id: String]) {
        guard !self.isCancelled else {
            return
        }
        self.update(i18n("Ayu.ExportChatSaving", self.locale), 1.0)
        // Ends the last page or media request; it holds the completion that led here.
        self.disposable.set(nil)
        let peerId = self.peerId
        let chatTitle = ayuExportSingleLine(title).isEmpty ? "Chat" : ayuExportSingleLine(title)
        Queue.concurrentDefaultQueue().async { [weak self] in
            let zipPath = ayuExportWriteZip(peerId: peerId, title: chatTitle, messages: messages, isPrivate: isPrivate, ownName: ownName, attachments: attachments, paths: paths)
            Queue.mainQueue().async {
                guard let self, !self.isCancelled else {
                    if let zipPath {
                        try? FileManager.default.removeItem(atPath: (zipPath as NSString).deletingLastPathComponent)
                    }
                    return
                }
                guard let zipPath else {
                    let data = self.context.sharedContext.currentPresentationData.with { $0 }
                    self.fail(data.strings.ChatImportActivity_ErrorGeneric)
                    return
                }
                self.isCancelled = true
                self.progress?.dismiss()
                ayuExportShare(context: self.context, path: zipPath)
            }
        }
    }
}

/// Writes `_chat.txt` and the attachments into a new temporary folder and zips them as
/// `WhatsApp Chat - <title>.zip` next to it. Returns the archive's path.
private func ayuExportWriteZip(peerId: EnginePeer.Id, title: String, messages: [EngineMessage], isPrivate: Bool, ownName: String, attachments: [AyuExportAttachment], paths: [EngineMessage.Id: String]) -> String? {
    let fileManager = FileManager.default
    let root = NSTemporaryDirectory() + "ayu-export-\(Int64.random(in: 1 ... Int64.max))"
    let contentsPath = root + "/contents"
    do {
        try fileManager.createDirectory(atPath: contentsPath, withIntermediateDirectories: true, attributes: nil)
    } catch {
        return nil
    }

    let lineDate = ayuExportDateFormatter("dd.MM.yy, HH:mm:ss")
    let fileDate = ayuExportDateFormatter("yyyy-MM-dd-HH-mm-ss")
    func date(_ timestamp: Int32) -> String {
        return lineDate.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    var kinds: [EngineMessage.Id: AyuExportMediaKind] = [:]
    var filePaths: [String] = []
    var fileNames: [EngineMessage.Id: String] = [:]
    var counter = 0
    for attachment in attachments {
        kinds[attachment.messageId] = attachment.kind
        guard let sourcePath = paths[attachment.messageId] else {
            continue
        }
        counter += 1
        let counterString = "\(counter)"
        let number = String(repeating: "0", count: max(0, 8 - counterString.count)) + counterString
        let stamp = fileDate.string(from: Date(timeIntervalSince1970: TimeInterval(attachment.timestamp)))
        let name: String
        switch attachment.kind {
        case .photo:
            name = "\(number)-PHOTO-\(stamp).jpg"
        case .video:
            name = "\(number)-VIDEO-\(stamp).mp4"
        case .sticker:
            name = "\(number)-STICKER-\(stamp).webp"
        case .voice:
            name = "\(number)-AUDIO-\(stamp).opus"
        case let .file(fileName):
            name = "\(number)-\(ayuExportSafeFileName(fileName))"
        }
        let targetPath = contentsPath + "/" + name
        // A hard link avoids copying large media; it fails across volumes, so copy then.
        if (try? fileManager.linkItem(atPath: sourcePath, toPath: targetPath)) == nil {
            if (try? fileManager.copyItem(atPath: sourcePath, toPath: targetPath)) == nil {
                continue
            }
        }
        filePaths.append(targetPath)
        fileNames[attachment.messageId] = name
    }

    var lines: [String] = []
    let firstTimestamp = messages.first?.timestamp ?? Int32(Date().timeIntervalSince1970)
    lines.append("[\(date(firstTimestamp))] \(title): \(ayuExportEncryptionNotice)")
    if !isPrivate {
        lines.append("[\(date(firstTimestamp))] \(title): \u{200E}\(ownName) created group “\(title)”")
    }
    for message in messages {
        let author: String
        if !message.flags.contains(.Incoming) {
            author = ownName
        } else if isPrivate {
            author = title
        } else if let peer = message.author, peer.id != peerId {
            author = ayuExportSingleLine(peer.debugDisplayTitle)
        } else {
            author = title
        }
        let prefix = "[\(date(message.timestamp))] \(author.isEmpty ? title : author): "
        if let name = fileNames[message.id] {
            lines.append(prefix + "\u{200E}<attached: \(name)>")
        }
        var text = message.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if fileNames[message.id] == nil, let kind = kinds[message.id] {
            // As WhatsApp writes media it left out of an export.
            let omitted: String
            switch kind {
            case .photo:
                omitted = "image omitted"
            case .video:
                omitted = "video omitted"
            case .sticker:
                omitted = "sticker omitted"
            case .voice:
                omitted = "audio omitted"
            case .file:
                omitted = "document omitted"
            }
            lines.append(prefix + "\u{200E}" + omitted)
        } else if text.isEmpty, fileNames[message.id] == nil {
            for media in message.media {
                if let map = media as? TelegramMediaMap {
                    text = "\u{200E}Location: https://maps.google.com/?q=\(map.latitude),\(map.longitude)"
                    break
                }
            }
        }
        if !text.isEmpty {
            lines.append(prefix + text)
        }
    }

    let chatPath = contentsPath + "/_chat.txt"
    guard let chatData = (lines.joined(separator: "\n") + "\n").data(using: .utf8), (try? chatData.write(to: URL(fileURLWithPath: chatPath))) != nil else {
        try? fileManager.removeItem(atPath: root)
        return nil
    }

    let zipPath = root + "/WhatsApp Chat - \(ayuExportSafeFileName(title)).zip"
    let created = SSZipArchive.createZipFile(atPath: zipPath, withFilesAtPaths: [chatPath] + filePaths)
    try? fileManager.removeItem(atPath: contentsPath)
    if !created {
        try? fileManager.removeItem(atPath: root)
        return nil
    }
    return zipPath
}

private func ayuExportShare(context: AccountContext, path: String) {
    let folder = (path as NSString).deletingLastPathComponent
    let activity = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
    activity.completionWithItemsHandler = { _, _, _, _ in
        try? FileManager.default.removeItem(atPath: folder)
    }
    guard let window = context.sharedContext.mainWindow else {
        try? FileManager.default.removeItem(atPath: folder)
        return
    }
    if let view = window.viewController?.view {
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: view.bounds.midX, y: view.bounds.midY), size: CGSize(width: 1.0, height: 1.0))
    }
    window.presentNative(activity)
}

private func ayuExportProgressScreen(context: AccountContext, peerId: EnginePeer.Id, text: String, present: (ViewController) -> Void) -> AyuExportJob {
    let screen = SaveProgressScreen(context: context, content: .progress(text, 0.0))
    let job = AyuExportJob(context: context, peerId: peerId, progress: screen)
    // The screen owns the job: cancelling or dismissing it ends the export.
    screen.cancelled = {
        job.cancel()
    }
    present(screen)
    return job
}

/// Writes `messages` of the chat as a Telegram-importable archive and shows the share sheet.
/// Media is taken from the media box when already downloaded; with `fetchMedia` missing media
/// is downloaded first. Media that cannot be had is left out.
func ayuGramExportChatArchive(context: AccountContext, peerId: EnginePeer.Id, title: String, messages: [EngineMessage], includeMedia: Bool = true, fetchMedia: Bool = false, present: @escaping (ViewController) -> Void) {
    let locale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    let job = ayuExportProgressScreen(context: context, peerId: peerId, text: i18n("Ayu.ExportChatSaving", locale), present: present)
    job.writeArchive(title: title, messages: messages, includeMedia: includeMedia, fetchMedia: fetchMedia)
}

/// Loads the chat's whole history from the server (not only what is cached), then exports it
/// with `ayuGramExportChatArchive`. Asks first whether to include media.
public func ayuGramExportChat(context: AccountContext, peerId: EnginePeer.Id, present: @escaping (ViewController) -> Void) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let start: (Bool) -> Void = { includeMedia in
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> deliverOnMainQueue).startStandalone(next: { peer in
            let title = peer?.debugDisplayTitle ?? ""
            let job = ayuExportProgressScreen(context: context, peerId: peerId, text: i18n("Ayu.ExportChatLoading", locale, "0"), present: present)
            ayuExportLoadHistory(job: job, offsetId: 0, loaded: [], completion: { [weak job] messages in
                job?.writeArchive(title: title, messages: messages, includeMedia: includeMedia, fetchMedia: true)
            })
        })
    }
    present(textAlertController(context: context, title: i18n("Ayu.ExportChat", locale), text: i18n("Ayu.ExportChatMedia", locale), actions: [
        TextAlertAction(type: .defaultAction, title: i18n("Ayu.ExportChatWithMedia", locale), action: {
            start(true)
        }),
        TextAlertAction(type: .genericAction, title: i18n("Ayu.ExportChatTextOnly", locale), action: {
            start(false)
        }),
        TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {})
    ], actionLayout: .vertical))
}

/// Pages the history newest to oldest until the server returns an empty page.
private func ayuExportLoadHistory(job: AyuExportJob, offsetId: Int32, loaded: [EngineMessage], completion: @escaping ([EngineMessage]) -> Void) {
    guard !job.isCancelled else {
        return
    }
    job.disposable.set((job.context.engine.messages.ayuExportHistoryPage(peerId: job.peerId, offsetId: offsetId)
    |> deliverOnMainQueue).startStrict(next: { [weak job] result in
        guard let job, !job.isCancelled else {
            return
        }
        guard let result else {
            let data = job.context.sharedContext.currentPresentationData.with { $0 }
            job.fail(data.strings.ChatImportActivity_ErrorGeneric)
            return
        }
        let messages = loaded + result.messages
        guard let oldest = result.messages.last, offsetId == 0 || oldest.id.id < offsetId, oldest.id.id > 1 else {
            completion(messages)
            return
        }
        let total = max(result.totalCount, messages.count)
        job.update(i18n("Ayu.ExportChatLoading", job.locale, "\(messages.count) / \(total)"), Float(messages.count) / Float(max(total, 1)))
        ayuExportLoadHistory(job: job, offsetId: oldest.id.id, loaded: messages, completion: completion)
    }))
}
