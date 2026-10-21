import Foundation
import UIKit
import UniformTypeIdentifiers
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
        hasChatListSelector = false
        hasContactSelector = true
        importTitle = title
    case let .group(title):
        filter = [.onlyGroups, .onlyManageable, .excludeDisabled, .doNotSearchMessages]
        hasChatListSelector = true
        hasContactSelector = false
        importTitle = title
    case let .unknown(title):
        filter = [.excludeDisabled, .doNotSearchMessages]
        hasChatListSelector = true
        hasContactSelector = true
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
            ayuImportAlert(context: context, errorText)
        })
    }

    navigationController.pushViewController(controller)
}
