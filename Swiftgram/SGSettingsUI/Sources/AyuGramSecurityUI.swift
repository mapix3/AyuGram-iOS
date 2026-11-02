import Foundation
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import PromptUI
import OverlayStatusController
import SGSimpleSettings
import SGStrings

var ayuGramVariant: String {
    return ayuGramHasAppearanceEntry ? "custom" : "standard"
}

private var ayuGramBlockPresented = false
private var ayuGramSecurityObserver: NSObjectProtocol?
private var ayuGramActiveObserver: NSObjectProtocol?
private var ayuGramWarningPresented = false

func ayuGramStartSecurity(context: AccountContext) {
    AyuGramUpdates.manifestObserver = { data in
        AyuGramSecurity.shared.applyManifest(data)
    }
    if let observer = ayuGramSecurityObserver {
        NotificationCenter.default.removeObserver(observer)
    }
    ayuGramSecurityObserver = NotificationCenter.default.addObserver(forName: AyuGramSecurity.didChange, object: nil, queue: .main, using: { [weak context] _ in
        guard let context else {
            return
        }
        ayuGramPresentBlockIfNeeded(context: context)
        ayuGramPresentWarningIfNeeded(context: context)
    })
    if let observer = ayuGramActiveObserver {
        NotificationCenter.default.removeObserver(observer)
    }
    ayuGramActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { _ in
        AyuGramSecurity.shared.refreshModeration()
    })
    AyuGramSecurity.shared.noteAccount(context.account.peerId.id._internalGetInt64Value())
    AyuGramSecurity.shared.refreshModeration()
    AyuGramSecurity.shared.start(variant: ayuGramVariant, statsEnabled: {
        return AyuGramSettings.shared.extra.anonymousStats
    })
    ayuGramPresentBlockIfNeeded(context: context)
    ayuGramPresentWarningIfNeeded(context: context)
}

private var ayuGramTamperWindow: UIWindow?

public func ayuGramArmTamperWatchdog() {
    AyuGramSecurity.shared.armTamperWatchdog(after: 25.0, onTamper: {
        ayuGramPresentTamperScreen()
    })
}

private func ayuGramPresentTamperScreen() {
    if AyuGramSecurity.shared.hasStarted {
        return
    }
    let message = AyuGramSecurity.tamperMessage
    if ayuGramTamperWindow == nil {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1.0)
        window.backgroundColor = .black
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        label.text = message
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 32.0),
            label.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -32.0)
        ])
        window.rootViewController = controller
        window.makeKeyAndVisible()
        ayuGramTamperWindow = window
    }
    Queue.mainQueue().after(3.0, {
        preconditionFailure(message)
    })
}

func ayuGramReportUsername(_ text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: "(?:@|t\\.me/|telegram\\.me/)([A-Za-z][A-Za-z0-9_]{3,31})", options: [.caseInsensitive]) else {
        return nil
    }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range), let name = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[name])
}

func ayuGramBuildStatusTitle(_ status: AyuGramBuildStatus, locale: String) -> String {
    switch status {
    case .official:
        return i18n("Ayu.BuildOfficial", locale)
    case .modified:
        return i18n("Ayu.BuildModified", locale)
    case .checking:
        return i18n("Ayu.BuildChecking", locale)
    case .unknown:
        return i18n("Ayu.BuildUnknown", locale)
    }
}

private func ayuGramSourceTitle(_ source: AyuGramInstallSource, locale: String) -> String {
    switch source {
    case .sideload:
        return i18n("Ayu.SourceSideload", locale)
    case .enterprise:
        return i18n("Ayu.SourceEnterprise", locale)
    case .testflight:
        return "TestFlight"
    case .appstore:
        return "App Store"
    case .unknown:
        return i18n("Ayu.BuildUnknown", locale)
    }
}

func ayuGramBuildInfoAlert(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let security = AyuGramSecurity.shared
    let summary: String
    switch security.status {
    case .official:
        summary = i18n("Ayu.BuildInfoOfficial", locale)
    case .modified:
        summary = i18n("Ayu.BuildInfoModified", locale)
    case .checking, .unknown:
        summary = i18n("Ayu.BuildInfoUnknown", locale)
    }
    var certificate = security.signing.certificate
    if certificate.isEmpty {
        certificate = security.signing.teamName
    }
    if certificate.isEmpty {
        certificate = "-"
    }
    let team = security.signing.teamId.isEmpty ? "-" : security.signing.teamId
    let details = i18n("Ayu.BuildDetails", locale, "\(security.build)", ayuGramSourceTitle(security.signing.source, locale: locale), certificate, team)
    return textAlertController(context: context, title: ayuGramBuildStatusTitle(security.status, locale: locale), text: summary + "\n\n" + details, actions: [
        TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})
    ])
}

func ayuGramScamReportPrompt(context: AccountContext, completion: @escaping () -> Void) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    var finished = false
    let finish: () -> Void = {
        if !finished {
            finished = true
            completion()
        }
    }
    return promptController(context: context, text: i18n("Ayu.ReportScamInfo", locale), value: "", placeholder: "@username", characterLimit: 600, apply: { value in
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finish()
            return
        }
        finished = true
        let username = ayuGramReportUsername(value)
        let resolve: Signal<EnginePeer?, NoError>
        if let username {
            resolve = context.engine.peers.resolvePeerByName(name: username, referrer: nil)
            |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                if case let .result(peer) = result {
                    return .single(peer)
                }
                return .complete()
            }
            |> then(.single(nil))
            |> take(1)
            |> timeout(10.0, queue: .mainQueue(), alternate: .single(nil))
        } else {
            resolve = .single(nil)
        }
        let _ = (resolve |> deliverOnMainQueue).start(next: { peer in
            var target: Int64 = 0
            var targetName = username.flatMap { "@" + $0 } ?? ""
            if let peer, case .user = peer {
                target = peer.id.id._internalGetInt64Value()
                targetName = targetName + " " + peer.debugDisplayTitle
            }
            let send: ([AyuGramAttachment]) -> Void = { attachments in
                ayuGramSubmitScamReport(context: context, text: value, target: target, targetName: targetName, attachments: attachments, completion: completion)
            }
            let ask = textAlertController(context: context, title: nil, text: i18n("Ayu.ReportAttachInfo", locale), actions: [
                TextAlertAction(type: .defaultAction, title: i18n("Ayu.ReportAttach", locale), action: {
                    ayuGramPickAttachments(context: context, completion: send)
                }),
                TextAlertAction(type: .genericAction, title: i18n("Ayu.ReportSendNow", locale), action: {
                    send([])
                })
            ], actionLayout: .vertical, dismissOnOutsideTap: false)
            context.sharedContext.mainWindow?.present(ask, on: .root)
        })
    }, dismissed: {
        finish()
    })
}

func ayuGramPresentBlockIfNeeded(context: AccountContext) {
    guard AyuGramSecurity.shared.isBlocked, !ayuGramBlockPresented else {
        return
    }
    ayuGramBlockPresented = true
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let reshow: () -> Void = { [weak context] in
        guard let context else {
            return
        }
        Queue.mainQueue().after(0.8, {
            ayuGramBlockPresented = false
            ayuGramPresentBlockIfNeeded(context: context)
        })
    }
    if AyuGramSecurity.shared.isBanned {
        var bannedText = i18n("Ayu.BannedText", locale)
        if let reason = AyuGramSecurity.shared.banReason {
            bannedText = i18n("Ayu.BannedTextReason", locale) + "\n\n" + i18n("Ayu.Reason", locale, i18n("Ayu.Reason." + reason, locale))
        }
        let alert = textAlertController(context: context, title: i18n("Ayu.BannedTitle", locale), text: bannedText, actions: [
            TextAlertAction(type: .defaultAction, title: i18n("Ayu.ScamChannel", locale), action: {
                ayuGramOpenLink(context: context, url: AyuGramUpdates.channelURL)
                reshow()
            })
        ], actionLayout: .vertical, dismissOnOutsideTap: false)
        context.sharedContext.mainWindow?.present(alert, on: .root)
        return
    }
    var text = AyuGramSecurity.shared.blockMessage ?? i18n("Ayu.ScamText", locale)
    if let reason = AyuGramSecurity.shared.blockReason {
        text += "\n\n" + i18n("Ayu.Reason", locale, i18n("Ayu.Reason." + reason, locale))
    }
    let alert = textAlertController(context: context, title: i18n("Ayu.ScamTitle", locale), text: text, actions: [
        TextAlertAction(type: .defaultAction, title: i18n("Ayu.ScamChannel", locale), action: {
            ayuGramOpenLink(context: context, url: AyuGramUpdates.channelURL)
            reshow()
        }),
        TextAlertAction(type: .genericAction, title: i18n("Ayu.ReportScam", locale), action: {
            context.sharedContext.mainWindow?.present(ayuGramScamReportPrompt(context: context, completion: reshow), on: .root)
        })
    ], actionLayout: .vertical, dismissOnOutsideTap: false)
    context.sharedContext.mainWindow?.present(alert, on: .root)
}

func ayuGramPresentWarningIfNeeded(context: AccountContext) {
    guard AyuGramSecurity.shared.pendingWarning != nil, !AyuGramSecurity.shared.isBlocked, !ayuGramWarningPresented else {
        return
    }
    ayuGramWarningPresented = true
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let alert = textAlertController(context: context, title: i18n("Ayu.WarnTitle", locale), text: i18n("Ayu.WarnText", locale), actions: [
        TextAlertAction(type: .defaultAction, title: i18n("Ayu.WarnOk", locale), action: {
            AyuGramSecurity.shared.acknowledgeWarning()
            ayuGramWarningPresented = false
        })
    ], actionLayout: .vertical, dismissOnOutsideTap: false)
    context.sharedContext.mainWindow?.present(alert, on: .root)
}

struct AyuGramAttachment {
    let data: Data
    let contentType: String
}

private final class AyuGramAttachmentPicker: NSObject, PHPickerViewControllerDelegate {
    var picked: (([PHPickerResult]) -> Void)?

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let picked = self.picked
        self.picked = nil
        ayuGramAttachmentPicker = nil
        picked?(results)
    }
}

private var ayuGramAttachmentPicker: AyuGramAttachmentPicker?
private let ayuGramMaxAttachments = 5
private let ayuGramMaxVideoBytes = 20 * 1024 * 1024

private func ayuGramCompressAttachment(_ image: UIImage) -> Data? {
    let size = image.size
    guard size.width > 0, size.height > 0 else {
        return nil
    }
    let scale = min(1.0, 2048.0 / max(size.width, size.height))
    let target = CGSize(width: max(1.0, floor(size.width * scale)), height: max(1.0, floor(size.height * scale)))
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1.0
    let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    return rendered.jpegData(compressionQuality: 0.8)
}

private func ayuGramLoadAttachments(_ results: [PHPickerResult], completion: @escaping ([AyuGramAttachment]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var items: [(Int, AyuGramAttachment)] = []
    let add: (Int, AyuGramAttachment) -> Void = { index, item in
        lock.lock()
        items.append((index, item))
        lock.unlock()
    }
    for (index, result) in results.prefix(ayuGramMaxAttachments).enumerated() {
        let provider = result.itemProvider
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            let isMP4 = provider.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier)
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier, completionHandler: { url, _ in
                if let url, let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 0, size <= ayuGramMaxVideoBytes, let data = try? Data(contentsOf: url) {
                    add(index, AyuGramAttachment(data: data, contentType: isMP4 ? "video/mp4" : "video/quicktime"))
                }
                group.leave()
            })
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            provider.loadObject(ofClass: UIImage.self, completionHandler: { object, _ in
                if let image = object as? UIImage, let data = ayuGramCompressAttachment(image) {
                    add(index, AyuGramAttachment(data: data, contentType: "image/jpeg"))
                }
                group.leave()
            })
        }
    }
    group.notify(queue: .main, execute: {
        completion(items.sorted(by: { $0.0 < $1.0 }).map { $0.1 })
    })
}

func ayuGramPickAttachments(context: AccountContext, completion: @escaping ([AyuGramAttachment]) -> Void) {
    var configuration = PHPickerConfiguration()
    configuration.selectionLimit = ayuGramMaxAttachments
    configuration.filter = .any(of: [.images, .videos])
    let picker = PHPickerViewController(configuration: configuration)
    let delegate = AyuGramAttachmentPicker()
    delegate.picked = { results in
        if results.isEmpty {
            completion([])
            return
        }
        ayuGramLoadAttachments(results, completion: completion)
    }
    ayuGramAttachmentPicker = delegate
    picker.delegate = delegate
    if context.sharedContext.currentPresentationData.with({ $0 }).theme.overallDarkAppearance {
        picker.overrideUserInterfaceStyle = .dark
    }
    context.sharedContext.mainWindow?.presentNative(picker)
}

private func ayuGramUploadAttachments(_ attachments: [AyuGramAttachment], ticket: AyuGramReportTicket, failed: Int, completion: @escaping (Int) -> Void) {
    guard let first = attachments.first else {
        completion(failed)
        return
    }
    AyuGramSecurity.shared.attach(ticket: ticket, data: first.data, contentType: first.contentType, completion: { ok in
        ayuGramUploadAttachments(Array(attachments.dropFirst()), ticket: ticket, failed: failed + (ok ? 0 : 1), completion: completion)
    })
}

func ayuGramSubmitScamReport(context: AccountContext, text: String, target: Int64, targetName: String, attachments: [AyuGramAttachment], completion: @escaping () -> Void) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let progress = OverlayStatusController(theme: data.theme, type: .loading(cancelled: nil))
    context.sharedContext.mainWindow?.present(progress, on: .root)
    let finish: (String) -> Void = { key in
        progress.dismiss()
        let result = textAlertController(context: context, title: nil, text: i18n(key, locale), actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {
                completion()
            })
        ], dismissOnOutsideTap: false)
        context.sharedContext.mainWindow?.present(result, on: .root)
    }
    AyuGramSecurity.shared.report(text: text, target: target, targetName: targetName, attachments: attachments.count, variant: ayuGramVariant, completion: { ok, ticket in
        guard ok else {
            finish("Ayu.ReportScamFailed")
            return
        }
        guard let ticket, !attachments.isEmpty else {
            finish(attachments.isEmpty ? "Ayu.ReportScamSent" : "Ayu.ReportAttachFailed")
            return
        }
        ayuGramUploadAttachments(attachments, ticket: ticket, failed: 0, completion: { failed in
            finish(failed == 0 ? "Ayu.ReportScamSent" : "Ayu.ReportAttachFailed")
        })
    })
}
