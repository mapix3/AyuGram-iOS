import Foundation
import UIKit
import UniformTypeIdentifiers
import AVFoundation
import ImageIO
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import OverlayStatusController
import ChatImportUI
import ZipArchive
import ManagedFile
import SGStrings

// In-app version of the share extension's chat import (ShareExtensionContext.swift,
// `attemptChatImport`): a WhatsApp, LINE or KakaoTalk export (or an AyuGram export, which uses
// the WhatsApp format) is imported into a chat through Telegram's own history import.

private typealias AyuImportEntry = (SSZipEntry, String, TelegramEngine.HistoryImport.MediaType)

private struct AyuImportSource {
    let archivePath: String?
    let mainFile: EngineTempBox.File
    let otherEntries: [AyuImportEntry]
}

/// Copied from ShareExtensionContext.swift: the first ~3 KB of the file as UTF-8.
private func ayuImportTextFileHeader(path: String) -> String? {
    guard let file = ManagedFile(queue: nil, path: path, mode: .read) else {
        return nil
    }
    guard let size = file.getSize() else {
        return nil
    }

    let limit: Int64 = 3000

    var data = file.readData(count: Int(min(size, limit)))
    let additionalCapacity = min(10, max(0, Int(size) - data.count))

    for alignment in 0 ... additionalCapacity {
        if alignment != 0 {
            data.append(file.readData(count: 1))
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
    }
    return nil
}

private func ayuImportMainFileExpressions(_ appConfiguration: AppConfiguration) -> [NSRegularExpression] {
    var mainFileNameExpressions: [String] = [
        "_chat\\.txt",
        "KakaoTalkChats\\.txt",
        "Talk_.*?\\.txt",
    ]
    if let data = appConfiguration.data, let dict = data["history_import_filters"] as? [String: Any] {
        if let zip = dict["zip"] as? [String: Any] {
            if let patterns = zip["main_file_patterns"] as? [String] {
                mainFileNameExpressions = patterns
            }
        }
    }
    return mainFileNameExpressions.compactMap { string -> NSRegularExpression? in
        return try? NSRegularExpression(pattern: string)
    }
}

private func ayuImportMatches(_ expressions: [NSRegularExpression], _ string: String) -> Bool {
    let fullRange = NSRange(string.startIndex ..< string.endIndex, in: string)
    for expression in expressions {
        if expression.firstMatch(in: string, options: [], range: fullRange) != nil {
            return true
        }
    }
    return false
}

/// Finds the chat text and the media in an export, as the share extension does. `path` is a
/// private copy of the picked file.
private func ayuImportPrepare(path: String, fileName: String, appConfiguration: AppConfiguration) -> AyuImportSource? {
    let fileExtension = (fileName as NSString).pathExtension.lowercased()
    if fileExtension == "zip" {
        guard let entries = SSZipArchive.getEntriesForFile(atPath: path) else {
            return nil
        }
        let mainFileNames = ayuImportMainFileExpressions(appConfiguration)

        var maybeMainFileName: String?
        for entry in entries {
            let entryFileName = entry.path.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
            if ayuImportMatches(mainFileNames, entryFileName) {
                maybeMainFileName = entryFileName
                break
            }
        }
        guard let mainFileName = maybeMainFileName else {
            return nil
        }

        let photoRegex = try! NSRegularExpression(pattern: ".*?\\.jpg")
        let videoRegex = try! NSRegularExpression(pattern: "[\\d]+-VIDEO-.*?\\.mp4")
        let stickerRegex = try! NSRegularExpression(pattern: "[\\d]+-STICKER-.*?\\.webp")
        let voiceRegex = try! NSRegularExpression(pattern: "[\\d]+-AUDIO-.*?\\.opus")

        var mainFile: EngineTempBox.File?
        var otherEntries: [AyuImportEntry] = []
        for entry in entries {
            let entryPath = entry.path.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
            if entryPath.isEmpty {
                continue
            }
            if entryPath == mainFileName {
                let tempFile = EngineTempBox.shared.tempFile(fileName: entryPath)
                if SSZipArchive.extractFileFromArchive(atPath: path, filePath: entry.path, toPath: tempFile.path) {
                    mainFile = tempFile
                }
            } else {
                let entryFileName = (entryPath as NSString).lastPathComponent
                if !entryFileName.isEmpty {
                    let mediaType: TelegramEngine.HistoryImport.MediaType
                    if ayuImportMatches([photoRegex], entryFileName) {
                        mediaType = .photo
                    } else if ayuImportMatches([videoRegex], entryFileName) {
                        mediaType = .video
                    } else if ayuImportMatches([stickerRegex], entryFileName) {
                        mediaType = .sticker
                    } else if ayuImportMatches([voiceRegex], entryFileName) {
                        mediaType = .voice
                    } else {
                        mediaType = .file
                    }
                    otherEntries.append((entry, entryFileName, mediaType))
                }
            }
        }
        guard let mainFile else {
            return nil
        }
        return AyuImportSource(archivePath: path, mainFile: mainFile, otherEntries: otherEntries)
    } else if fileExtension == "txt" {
        var fileScanExpressions: [String] = [
            "^\\[LINE\\]",
        ]
        if let data = appConfiguration.data, let dict = data["history_import_filters"] as? [String: Any] {
            if let txt = dict["txt"] as? [String: Any] {
                if let patterns = txt["patterns"] as? [String] {
                    fileScanExpressions = patterns
                }
            }
        }
        let filePatterns: [NSRegularExpression] = fileScanExpressions.compactMap { string -> NSRegularExpression? in
            return try? NSRegularExpression(pattern: string)
        }
        guard let header = ayuImportTextFileHeader(path: path) else {
            return nil
        }
        // A bare WhatsApp or KakaoTalk text keeps its name; the server reads its header too.
        let isKnownMainFile = ayuImportMatches(ayuImportMainFileExpressions(appConfiguration), fileName)
        if !isKnownMainFile && !ayuImportMatches(filePatterns, header) {
            return nil
        }
        let tempFile = EngineTempBox.shared.tempFile(fileName: isKnownMainFile ? fileName : "History.txt")
        guard (try? FileManager.default.copyItem(atPath: path, toPath: tempFile.path)) != nil else {
            return nil
        }
        return AyuImportSource(archivePath: nil, mainFile: tempFile, otherEntries: [])
    } else {
        return nil
    }
}

/// Picks the export with the system document picker. The picker is its own delegate.
private final class AyuImportDocumentPicker: UIDocumentPickerViewController, UIDocumentPickerDelegate {
    var picked: ((URL) -> Void)?

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let picked = self.picked
        self.picked = nil
        if let url = urls.first {
            picked?(url)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.picked = nil
    }
}

/// Opens the document picker for a chat export (ZIP or TXT) and imports it into a chat the user
/// chooses, through Telegram's history import.
func ayuGramImportChat(context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let picker = AyuImportDocumentPicker(forOpeningContentTypes: [.zip, .plainText], asCopy: true)
    picker.delegate = picker
    if presentationData.theme.overallDarkAppearance {
        picker.overrideUserInterfaceStyle = .dark
    }
    picker.picked = { url in
        ayuImportPicked(context: context, url: url)
    }
    context.sharedContext.mainWindow?.presentNative(picker)
}

private func ayuImportPresent(context: AccountContext, _ controller: ViewController) {
    context.sharedContext.mainWindow?.present(controller, on: .root)
}

private func ayuImportAlert(context: AccountContext, _ text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    ayuImportPresent(context: context, textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
}

private func ayuImportPicked(context: AccountContext, url: URL) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let appConfiguration = context.currentAppConfiguration.with { $0 }
    let fileName = url.lastPathComponent

    let progress = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
    ayuImportPresent(context: context, progress)

    Queue.concurrentDefaultQueue().async {
        // Work on a private copy: the picked URL may only be readable for a moment.
        let accessing = url.startAccessingSecurityScopedResource()
        let copy = EngineTempBox.shared.tempFile(fileName: (fileName as NSString).pathExtension.lowercased() == "zip" ? "History.zip" : "Picked.txt")
        let copied = (try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: copy.path))) != nil
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
        let source = copied ? ayuImportPrepare(path: copy.path, fileName: fileName, appConfiguration: appConfiguration) : nil
        let header = source.flatMap { ayuImportTextFileHeader(path: $0.mainFile.path) }

        Queue.mainQueue().async {
            guard let source, let header else {
                progress.dismiss()
                ayuImportAlert(context: context, i18n("Ayu.ImportChatInvalid", locale))
                return
            }
            let _ = (context.engine.historyImport.getInfo(header: header)
            |> deliverOnMainQueue).startStandalone(next: { parseInfo in
                progress.dismiss()
                ayuImportSelectPeer(context: context, parseInfo: parseInfo, source: source)
            }, error: { _ in
                progress.dismiss()
                ayuImportAlert(context: context, i18n("Ayu.ImportChatInvalid", locale))
            })
        }
    }
}

/// Peer selection, checks and confirmation as in the share extension's `attemptChatImport`.
private func ayuImportSelectPeer(context: AccountContext, parseInfo: TelegramEngine.HistoryImport.ParsedInfo, source: AyuImportSource) {
    guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }

    let filter: ChatListNodePeersFilter
    let hasChatListSelector: Bool
    let hasContactSelector: Bool
    let importTitle: String?
    switch parseInfo {
    case let .privateChat(title):
        filter = [.onlyPrivateChats, .excludeDisabled, .doNotSearchMessages, .excludeSecretChats]
        hasChatListSelector = true
        hasContactSelector = false
        importTitle = title
    case let .group(title):
        filter = [.onlyGroups, .onlyManageable, .excludeDisabled, .doNotSearchMessages]
        hasChatListSelector = true
        hasContactSelector = false
        importTitle = title
    case let .unknown(title):
        filter = [.excludeDisabled, .doNotSearchMessages]
        hasChatListSelector = true
        hasContactSelector = false
        importTitle = title
    }

    var attemptSelectionImpl: ((EnginePeer) -> Void)?
    let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: filter, hasChatListSelector: hasChatListSelector, hasContactSelector: hasContactSelector, hasGlobalSearch: false, title: presentationData.strings.ChatImport_Title, attemptSelection: { peer, _, _ in
        attemptSelectionImpl?(peer)
    }, selectForumThreads: false))
    controller.peerSelected = { peer, _ in
        attemptSelectionImpl?(peer)
    }

    let beginWithPeer: (EnginePeer.Id) -> Void = { [weak controller, weak navigationController] peerId in
        guard let navigationController else {
            return
        }
        navigationController.view.endEditing(true)
        var dismissImpl: (() -> Void)?
        let screen = ChatImportActivityScreen(context: context, cancel: {
            dismissImpl?()
        }, peerId: peerId, archivePath: source.archivePath, mainEntry: source.mainFile, otherEntries: source.otherEntries)
        dismissImpl = { [weak navigationController, weak screen] in
            if let navigationController, let screen {
                navigationController.filterController(screen, animated: true)
            }
        }
        if let controller, navigationController.viewControllers.contains(where: { $0 === controller }) {
            navigationController.replaceController(controller, with: screen, animated: true)
        } else {
            navigationController.pushViewController(screen)
        }
    }

    attemptSelectionImpl = { [weak controller] peer in
        var errorText: String?
        if case let .channel(channel) = peer {
            if channel.hasPermission(.changeInfo), (channel.flags.contains(.isCreator) || channel.adminRights != nil) {
            } else {
                errorText = presentationData.strings.ChatImport_SelectionErrorNotAdmin
            }
        } else if case let .legacyGroup(group) = peer {
            switch group.role {
            case .creator:
                break
            default:
                errorText = presentationData.strings.ChatImport_SelectionErrorNotAdmin
            }
        } else if case .user = peer {
        } else {
            errorText = presentationData.strings.ChatImport_SelectionErrorGroupGeneric
        }
        if let errorText {
            ayuImportAlert(context: context, errorText)
            return
        }

        controller?.inProgress = true
        let _ = (context.engine.historyImport.checkPeerImport(peerId: peer.id)
        |> deliverOnMainQueue).startStandalone(next: { result in
            controller?.inProgress = false

            let text: String
            switch result {
            case .allowed:
                if case .user = peer {
                    if let importTitle {
                        text = presentationData.strings.ChatImport_SelectionConfirmationUserWithTitle(importTitle, peer.debugDisplayTitle).string
                    } else {
                        text = presentationData.strings.ChatImport_SelectionConfirmationUserWithoutTitle(peer.debugDisplayTitle).string
                    }
                } else {
                    if let importTitle {
                        text = presentationData.strings.ChatImport_SelectionConfirmationGroupWithTitle(importTitle, peer.debugDisplayTitle).string
                    } else {
                        text = presentationData.strings.ChatImport_SelectionConfirmationGroupWithoutTitle(peer.debugDisplayTitle).string
                    }
                }
            case let .alert(textValue):
                text = textValue
            }
            ayuImportPresent(context: context, textAlertController(context: context, title: presentationData.strings.ChatImport_SelectionConfirmationAlertTitle, text: text, actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .defaultAction, title: presentationData.strings.ChatImport_SelectionConfirmationAlertImportAction, action: {
                    beginWithPeer(peer.id)
                })
            ], parseMarkdown: true))
        }, error: { error in
            controller?.inProgress = false

            let errorText: String
            switch error {
            case .generic:
                errorText = presentationData.strings.Login_UnknownError
            case .chatAdminRequired:
                errorText = presentationData.strings.ChatImportActivity_ErrorNotAdmin
            case .invalidChatType:
                errorText = presentationData.strings.ChatImportActivity_ErrorInvalidChatType
            case .userBlocked:
                errorText = presentationData.strings.ChatImportActivity_ErrorUserBlocked
            case .limitExceeded:
                errorText = presentationData.strings.ChatImportActivity_ErrorLimitExceeded
            case .notMutualContact:
                errorText = presentationData.strings.ChatImport_UserErrorNotMutual
            }
            if case .user = peer {
                let locale = presentationData.strings.baseLanguageCode
                ayuImportPresent(context: context, textAlertController(context: context, title: nil, text: errorText + "\n\n" + i18n("Ayu.ImportLocallyInfo", locale), actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .defaultAction, title: i18n("Ayu.ImportLocally", locale), action: { [weak controller] in
                        ayuImportLocally(context: context, peer: peer, title: importTitle, source: source, completion: {
                            if let controller, let navigationController = controller.navigationController as? NavigationController {
                                navigationController.filterController(controller, animated: false)
                            }
                        })
                    })
                ]))
            } else {
                ayuImportAlert(context: context, errorText)
            }
        })
    }

    navigationController.pushViewController(controller)
}

private let ayuImportLinePatterns: [NSRegularExpression] = [
    try! NSRegularExpression(pattern: "^\\[(\\d{1,2})[./-](\\d{1,2})[./-](\\d{2,4}),? (\\d{1,2}):(\\d{2})(?::(\\d{2}))?(?:\\s?([AaPp][Mm]))?\\] ([^:]+?): (.*)$"),
    try! NSRegularExpression(pattern: "^(\\d{1,2})[./-](\\d{1,2})[./-](\\d{2,4}),? (\\d{1,2}):(\\d{2})(?::(\\d{2}))?(?:\\s?([AaPp][Mm]))? - ([^:]+?): (.*)$")
]

private struct AyuImportParsedMessage {
    let timestamp: Int32
    let incoming: Bool
    let text: String
    let attachmentName: String?
}

private func ayuImportAttachmentName(_ text: String) -> (String, String)? {
    let firstLine = text.components(separatedBy: "\n").first ?? text
    let rest = text.count > firstLine.count ? String(text.dropFirst(firstLine.count + 1)) : ""
    let trimmed = firstLine.trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{200F} "))
    if trimmed.hasPrefix("<attached: "), trimmed.hasSuffix(">") {
        return (String(trimmed.dropFirst("<attached: ".count).dropLast()), rest)
    }
    for suffix in [" (file attached)", " (файл прикреплён)", " (файл прикреплен)"] where trimmed.hasSuffix(suffix) {
        return (String(trimmed.dropLast(suffix.count)), rest)
    }
    return nil
}

private func ayuImportParseLocal(text: String, peerNames: Set<String>) -> [AyuImportParsedMessage] {
    var result: [(timestamp: Int32, author: String, text: String)] = []
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{200F}\u{FEFF}"))
        let range = NSRange(line.startIndex..., in: line)
        var matched = false
        for pattern in ayuImportLinePatterns {
            guard let match = pattern.firstMatch(in: line, range: range) else {
                continue
            }
            func group(_ index: Int) -> String? {
                let groupRange = match.range(at: index)
                guard groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: line) else {
                    return nil
                }
                return String(line[swiftRange])
            }
            guard let day = group(1).flatMap(Int.init), let month = group(2).flatMap(Int.init), var year = group(3).flatMap(Int.init), var hour = group(4).flatMap(Int.init), let minute = group(5).flatMap(Int.init), let author = group(8), let body = group(9) else {
                continue
            }
            if year < 100 {
                year += 2000
            }
            if let meridiem = group(7)?.lowercased() {
                if meridiem == "pm" && hour < 12 {
                    hour += 12
                } else if meridiem == "am" && hour == 12 {
                    hour = 0
                }
            }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            components.hour = hour
            components.minute = minute
            components.second = group(6).flatMap(Int.init) ?? 0
            guard let date = calendar.date(from: components) else {
                continue
            }
            let messageText = body.trimmingCharacters(in: CharacterSet(charactersIn: "\u{200E}\u{200F}"))
            result.append((Int32(date.timeIntervalSince1970), author.trimmingCharacters(in: .whitespaces), messageText))
            matched = true
            break
        }
        if !matched, !result.isEmpty, !line.isEmpty {
            result[result.count - 1].text += "\n" + line
        }
    }
    if let first = result.first, first.text.contains("end-to-end encrypted") {
        result.removeFirst()
    }
    var authors: [String: Int] = [:]
    for item in result {
        authors[item.author, default: 0] += 1
    }
    var incomingNames = peerNames.filter { authors[$0] != nil }
    if incomingNames.isEmpty, authors.count == 2, let least = authors.min(by: { $0.value < $1.value })?.key {
        incomingNames = [least]
    }
    var lastTimestamp: Int32 = 0
    return result.map { item -> AyuImportParsedMessage in
        let timestamp = max(item.timestamp, lastTimestamp)
        lastTimestamp = timestamp
        if let attachment = ayuImportAttachmentName(item.text) {
            return AyuImportParsedMessage(timestamp: timestamp, incoming: incomingNames.contains(item.author), text: attachment.1.trimmingCharacters(in: .whitespacesAndNewlines), attachmentName: attachment.0)
        }
        return AyuImportParsedMessage(timestamp: timestamp, incoming: incomingNames.contains(item.author), text: item.text, attachmentName: nil)
    }
}

private func ayuImportPixelSize(path: String) -> (Int32, Int32)? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.int32Value, let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.int32Value else {
        return nil
    }
    if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
        return (height, width)
    }
    return (width, height)
}

private func ayuImportAttachment(name: String, source: AyuImportSource, entries: [String: SSZipEntry]) -> AyuGramImportedAttachment? {
    guard let archivePath = source.archivePath, let entry = entries[name] else {
        return nil
    }
    let fileExtension = (name as NSString).pathExtension.lowercased()
    let file = EngineTempBox.shared.tempFile(fileName: "import." + (fileExtension.isEmpty ? "bin" : fileExtension))
    guard SSZipArchive.extractFileFromArchive(atPath: archivePath, filePath: entry.path, toPath: file.path) else {
        return nil
    }
    switch fileExtension {
    case "jpg", "jpeg", "png", "heic":
        let size = ayuImportPixelSize(path: file.path) ?? (1280, 1280)
        let mimeType = fileExtension == "png" ? "image/png" : (fileExtension == "heic" ? "image/heic" : "image/jpeg")
        return AyuGramImportedAttachment(kind: .photo, path: file.path, fileName: name, mimeType: mimeType, width: size.0, height: size.1, duration: 0, thumbnailPath: nil)
    case "webp":
        let size = ayuImportPixelSize(path: file.path) ?? (512, 512)
        return AyuGramImportedAttachment(kind: .sticker, path: file.path, fileName: name, mimeType: "image/webp", width: size.0, height: size.1, duration: 0, thumbnailPath: nil)
    case "mp4", "mov", "m4v", "3gp":
        let asset = AVURLAsset(url: URL(fileURLWithPath: file.path))
        var size = CGSize(width: 1280, height: 720)
        if let track = asset.tracks(withMediaType: .video).first {
            let transformed = track.naturalSize.applying(track.preferredTransform)
            size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        }
        let duration = CMTimeGetSeconds(asset.duration)
        var thumbnailPath: String?
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        if let image = try? generator.copyCGImage(at: .zero, actualTime: nil), let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.7) {
            let thumbnail = EngineTempBox.shared.tempFile(fileName: "thumbnail.jpg")
            if (try? data.write(to: URL(fileURLWithPath: thumbnail.path))) != nil {
                thumbnailPath = thumbnail.path
            }
        }
        return AyuGramImportedAttachment(kind: .video, path: file.path, fileName: name, mimeType: fileExtension == "mov" ? "video/quicktime" : "video/mp4", width: Int32(size.width), height: Int32(size.height), duration: duration.isFinite ? duration : 0, thumbnailPath: thumbnailPath)
    case "opus", "ogg":
        let duration = CMTimeGetSeconds(AVURLAsset(url: URL(fileURLWithPath: file.path)).duration)
        return AyuGramImportedAttachment(kind: .voice, path: file.path, fileName: name, mimeType: "audio/ogg", width: 0, height: 0, duration: duration.isFinite ? duration : 0, thumbnailPath: nil)
    default:
        let mimeTypes: [String: String] = ["pdf": "application/pdf", "mp3": "audio/mpeg", "m4a": "audio/mp4", "aac": "audio/aac", "gif": "image/gif", "txt": "text/plain", "vcf": "text/vcard", "zip": "application/zip"]
        return AyuGramImportedAttachment(kind: .file, path: file.path, fileName: name, mimeType: mimeTypes[fileExtension] ?? "application/octet-stream", width: 0, height: 0, duration: 0, thumbnailPath: nil)
    }
}

private func ayuImportLocally(context: AccountContext, peer: EnginePeer, title: String?, source: AyuImportSource, completion: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    var peerNames = Set<String>()
    peerNames.insert(peer.debugDisplayTitle)
    if case let .user(user) = peer {
        if let firstName = user.firstName {
            peerNames.insert(firstName)
        }
        if let username = user.addressName {
            peerNames.insert(username)
        }
    }
    if let title {
        peerNames.insert(title)
    }
    let progress = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
    ayuImportPresent(context: context, progress)
    let path = source.mainFile.path
    Queue.concurrentDefaultQueue().async {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        var entries: [String: SSZipEntry] = [:]
        for (entry, fileName, _) in source.otherEntries {
            entries[fileName] = entry
        }
        let messages = ayuImportParseLocal(text: text, peerNames: peerNames).map { item -> AyuGramImportedMessage in
            let attachment = item.attachmentName.flatMap { ayuImportAttachment(name: $0, source: source, entries: entries) }
            var text = item.text
            if attachment == nil, let name = item.attachmentName {
                text = text.isEmpty ? "📎 " + name : "📎 " + name + "\n" + text
            }
            return AyuGramImportedMessage(timestamp: item.timestamp, incoming: item.incoming, text: text, attachment: attachment)
        }
        Queue.mainQueue().async {
            guard !messages.isEmpty else {
                progress.dismiss()
                ayuImportAlert(context: context, i18n("Ayu.ImportChatInvalid", locale))
                return
            }
            let _ = (context.engine.ayuGramImportLocally(peerId: peer.id, messages: messages)
            |> deliverOnMainQueue).startStandalone(next: { count in
                progress.dismiss()
                completion()
                context.sharedContext.navigateToChat(accountId: context.account.id, peerId: peer.id, messageId: nil)
                ayuImportAlert(context: context, i18n("Ayu.ImportLocallyDone", locale, "\(count)"))
            })
        }
    }
}
