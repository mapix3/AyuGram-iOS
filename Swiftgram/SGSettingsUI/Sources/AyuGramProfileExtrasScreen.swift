import Foundation
import UIKit
import PhotosUI
import AVFoundation
import ImageIO
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import PromptUI
import OverlayStatusController
import UndoUI
import GiftViewScreen
import SGSimpleSettings
import SGStrings
import AyuGramProfileExtras

private enum AyuProfileExtrasSection: Int32 {
    case intro, verify, bubbles, background, nfts, usernames, danger
}

private enum AyuProfileExtrasEntry: ItemListNodeEntry {
    case intro(id: Int, text: String)
    case retry(id: Int, title: String)
    case bubbles(id: Int, title: String, value: Bool, enabled: Bool)
    case header(id: Int, section: AyuProfileExtrasSection, text: String)
    case footer(id: Int, section: AyuProfileExtrasSection, text: String)
    case status(id: Int, section: AyuProfileExtrasSection, symbol: String, title: String, label: String)
    case action(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasAction, symbol: String, title: String, enabled: Bool)
    case destructive(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasAction, title: String, enabled: Bool)
    case nft(id: Int, index: Int, title: String, label: String, enabled: Bool)
    case username(id: Int, index: Int, title: String, enabled: Bool)

    var section: ItemListSectionId {
        switch self {
        case .intro, .retry:
            return AyuProfileExtrasSection.intro.rawValue
        case .bubbles:
            return AyuProfileExtrasSection.bubbles.rawValue
        case let .header(_, section, _), let .footer(_, section, _):
            return section.rawValue
        case let .status(_, section, _, _, _):
            return section.rawValue
        case let .action(_, section, _, _, _, _):
            return section.rawValue
        case let .destructive(_, section, _, _, _):
            return section.rawValue
        case .nft:
            return AyuProfileExtrasSection.nfts.rawValue
        case .username:
            return AyuProfileExtrasSection.usernames.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .intro(id, _), let .retry(id, _):
            return id
        case let .bubbles(id, _, _, _):
            return id
        case let .header(id, _, _), let .footer(id, _, _):
            return id
        case let .status(id, _, _, _, _):
            return id
        case let .action(id, _, _, _, _, _):
            return id
        case let .destructive(id, _, _, _, _):
            return id
        case let .nft(id, _, _, _, _):
            return id
        case let .username(id, _, _, _):
            return id
        }
    }

    static func <(lhs: AyuProfileExtrasEntry, rhs: AyuProfileExtrasEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuProfileExtrasArguments
        switch self {
        case let .intro(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .retry(_, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.perform(.retry)
            })
        case let .bubbles(_, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon("bubbles.and.sparkles.fill", color: AyuGramRowColor.blue), title: title, value: value, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleBubbles(value)
            })
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .status(_, _, symbol, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: AyuGramRowColor.gray), title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .action(_, _, key, symbol, title, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: enabled ? AyuGramRowColor.blue : AyuGramRowColor.gray), title: title, enabled: enabled, label: "", sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.perform(key)
                }
            })
        case let .destructive(_, _, key, title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.perform(key)
                }
            })
        case let .nft(_, index, title, label, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon("gift.fill", color: AyuGramRowColor.purple), title: title, enabled: enabled, label: label, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.openNft(index)
                }
            })
        case let .username(_, index, title, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon("at", color: AyuGramRowColor.teal), title: title, enabled: enabled, label: "", sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.openUsername(index)
                }
            })
        }
    }
}

private enum AyuProfileExtrasAction: Equatable {
    case retry
    case verify
    case choosePhoto
    case chooseVideo
    case removeBackground
    case addNft
    case addUsername
    case deleteAll
}

private final class AyuProfileExtrasArguments {
    let toggleBubbles: (Bool) -> Void
    let perform: (AyuProfileExtrasAction) -> Void
    let openNft: (Int) -> Void
    let openUsername: (Int) -> Void

    init(toggleBubbles: @escaping (Bool) -> Void, perform: @escaping (AyuProfileExtrasAction) -> Void, openNft: @escaping (Int) -> Void, openUsername: @escaping (Int) -> Void) {
        self.toggleBubbles = toggleBubbles
        self.perform = perform
        self.openNft = openNft
        self.openUsername = openUsername
    }
}

private final class AyuProfileExtrasModel {
    var loaded = false
    var loadError: AyuGramProfileError?
    var saved: AyuGramProfileEntry?
    var limits = AyuGramProfileLimits.standard
    var nfts: [AyuGramProfileNft] = []
    var usernames: [String] = []
    var bubbles = false
    var verified = true
    var awaitingVerification = false
    var verificationCode: String?
    var checkingVerification = false
    var alive = true
    var busy = false
    var mediaStatus: String?
    var gifts: [String: StarGift.UniqueGift] = [:]
    var resolving = Set<String>()

    var dirty: Bool {
        guard let saved = self.saved else {
            return false
        }
        return self.nfts != saved.nfts || self.usernames != saved.usernames || self.bubbles != saved.bubbles
    }

    func apply(_ own: AyuGramOwnProfile, keepDraft: Bool) {
        let wasDirty = self.dirty
        self.loaded = true
        self.loadError = nil
        self.saved = own.entry
        self.limits = own.limits
        self.verified = own.verified
        if own.verified {
            self.awaitingVerification = false
            self.verificationCode = nil
        }
        if !(keepDraft && wasDirty) {
            self.nfts = own.entry.nfts
            self.usernames = own.entry.usernames
            self.bubbles = own.entry.bubbles
        }
    }
}

private final class AyuProfileExtrasHolder {
    let disposables: DisposableSet
    let picker = AyuProfileMediaPicker()
    let model: AyuProfileExtrasModel
    var foregroundObserver: NSObjectProtocol?

    init(model: AyuProfileExtrasModel, disposables: DisposableSet) {
        self.model = model
        self.disposables = disposables
    }

    deinit {
        self.model.alive = false
        self.disposables.dispose()
        if let foregroundObserver = self.foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }
}

private final class AyuProfileMediaPicker: NSObject, PHPickerViewControllerDelegate {
    weak var controller: UIViewController?
    var completion: ((URL?, Bool) -> Void)?
    private var pickingVideo = false

    func choose(video: Bool) {
        self.pickingVideo = video
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = video ? .videos : .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .compatible
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        self.controller?.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            return
        }
        let video = self.pickingVideo
        provider.loadFileRepresentation(forTypeIdentifier: video ? "public.movie" : "public.image", completionHandler: { [weak self] url, error in
            var copied: URL?
            if error == nil, let url {
                let fileExtension = url.pathExtension.isEmpty ? (video ? "mov" : "jpg") : url.pathExtension
                let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + fileExtension)
                if (try? FileManager.default.copyItem(at: url, to: target)) != nil {
                    copied = target
                }
            }
            DispatchQueue.main.async {
                self?.completion?(copied, video)
            }
        })
    }
}

private struct AyuPreparedProfileMedia {
    let url: URL
    let mime: String
    let width: Int
    let height: Int
    let isVideo: Bool
}

private func ayuPrepareProfilePhoto(_ url: URL, maxBytes: Int) -> AyuPreparedProfileMedia? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }
    let sides: [Int] = [1600, 1280, 1080, 900, 720]
    let qualities: [CGFloat] = [0.86, 0.76, 0.66]
    for side in sides {
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: side
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        for quality in qualities {
            guard let data = UIImage(cgImage: image).jpegData(compressionQuality: quality), data.count <= maxBytes else {
                continue
            }
            let target = AyuGramProfileRelay.makePreviewURL(fileExtension: "jpg")
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                return nil
            }
            return AyuPreparedProfileMedia(url: target, mime: "image/jpeg", width: image.width, height: image.height, isVideo: false)
        }
    }
    return nil
}

private final class AyuProfileVideoExporter {
    private let source: URL
    private let maxSeconds: Double
    private let maxBytes: Int
    private let progress: (Double) -> Void
    private let completion: (AyuPreparedProfileMedia?) -> Void
    private var session: AVAssetExportSession?
    private var timer: Timer?
    private var finished = false
    private var keepAlive: AyuProfileVideoExporter?

    init(source: URL, maxSeconds: Double, maxBytes: Int, progress: @escaping (Double) -> Void, completion: @escaping (AyuPreparedProfileMedia?) -> Void) {
        self.source = source
        self.maxSeconds = maxSeconds
        self.maxBytes = maxBytes
        self.progress = progress
        self.completion = completion
    }

    func start() {
        self.keepAlive = self
        let asset = AVURLAsset(url: self.source)
        asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"], completionHandler: {
            DispatchQueue.main.async {
                self.build(asset: asset)
            }
        })
    }

    private func finish(_ result: AyuPreparedProfileMedia?) {
        if self.finished {
            return
        }
        self.finished = true
        self.timer?.invalidate()
        self.timer = nil
        self.session = nil
        self.completion(result)
        self.keepAlive = nil
    }

    private func build(asset: AVURLAsset) {
        guard let track = asset.tracks(withMediaType: .video).first else {
            self.finish(nil)
            return
        }
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            self.finish(nil)
            return
        }
        let totalSeconds = CMTimeGetSeconds(track.timeRange.duration)
        let seconds = min(totalSeconds.isFinite ? totalSeconds : 0.0, self.maxSeconds - 0.3)
        guard seconds > 0.2 else {
            self.finish(nil)
            return
        }
        let range = CMTimeRange(start: track.timeRange.start, duration: CMTime(seconds: seconds, preferredTimescale: 600))
        do {
            try compositionTrack.insertTimeRange(range, of: track, at: .zero)
        } catch {
            self.finish(nil)
            return
        }
        compositionTrack.preferredTransform = track.preferredTransform
        let presets = [AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480]
        self.export(composition: composition, presets: presets, index: 0)
    }

    private func export(composition: AVMutableComposition, presets: [String], index: Int) {
        guard index < presets.count, let session = AVAssetExportSession(asset: composition, presetName: presets[index]) else {
            self.finish(nil)
            return
        }
        let target = AyuGramProfileRelay.makePreviewURL(fileExtension: "mp4")
        session.outputURL = target
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        self.session = session
        self.timer?.invalidate()
        let base = Double(index) / Double(presets.count)
        let span = 1.0 / Double(presets.count)
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: { [weak self, weak session] _ in
            guard let self, let session else {
                return
            }
            self.progress(base + span * Double(session.progress))
        })
        session.exportAsynchronously(completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                let size = ((try? FileManager.default.attributesOfItem(atPath: target.path))?[.size] as? NSNumber)?.intValue ?? 0
                if session.status == .completed && size > 0 && size <= self.maxBytes {
                    self.finish(AyuPreparedProfileMedia(url: target, mime: "video/mp4", width: 0, height: 0, isVideo: true))
                } else {
                    try? FileManager.default.removeItem(at: target)
                    if session.status == .completed {
                        self.export(composition: composition, presets: presets, index: index + 1)
                    } else {
                        self.finish(nil)
                    }
                }
            }
        })
    }
}

private let ayuProfileReservedExact: Set<String> = ["botfather", "spambot", "premium", "stars", "gift", "gifts", "wallet", "notoscam", "verify", "username", "usernames", "jobs", "news", "team", "durov", "pavel", "nikolai"]
private let ayuProfileReservedParts: [String] = ["telegram", "ayugram", "official", "support", "admin", "fragment", "security", "moderator"]

private func ayuProfileErrorText(_ error: AyuGramProfileError, locale: String) -> String {
    switch error {
    case .network:
        return i18n("Ayu.ProfileExtras.Error.Network", locale)
    case .unavailable:
        return i18n("Ayu.ProfileExtras.Error.Unavailable", locale)
    case .locked:
        return i18n("Ayu.ProfileExtras.Error.Locked", locale)
    case .unverified:
        return i18n("Ayu.ProfileExtras.Error.Unverified", locale)
    case .banned, .blocked:
        return i18n("Ayu.ProfileExtras.Error.Banned", locale)
    case .rateLimited:
        return i18n("Ayu.ProfileExtras.Error.RateLimited", locale)
    case .tooLarge:
        return i18n("Ayu.ProfileExtras.Error.TooLarge", locale)
    case .tooLong:
        return i18n("Ayu.ProfileExtras.Error.TooLong", locale)
    case .badMedia, .unsupported:
        return i18n("Ayu.ProfileExtras.Error.BadMedia", locale)
    case let .reservedUsername(value):
        return i18n("Ayu.ProfileExtras.Error.Reserved", locale, "@" + value)
    case .badUsername:
        return i18n("Ayu.ProfileExtras.Error.BadUsername", locale)
    case .invalid, .server:
        return i18n("Ayu.ProfileExtras.Error.Invalid", locale)
    }
}

private func ayuProfileExtrasEntries(data: PresentationData, model: AyuProfileExtrasModel) -> [AyuProfileExtrasEntry] {
    let locale = data.strings.baseLanguageCode
    func s(_ key: String) -> String {
        return i18n(key, locale)
    }
    var entries: [AyuProfileExtrasEntry] = []
    entries.append(.intro(id: 0, text: s("Ayu.ProfileExtras.Intro")))
    guard model.loaded else {
        if let loadError = model.loadError {
            entries.append(.footer(id: 1, section: .intro, text: ayuProfileErrorText(loadError, locale: locale)))
            entries.append(.retry(id: 2, title: s("Ayu.ProfileExtras.Retry")))
        } else {
            entries.append(.status(id: 3, section: .intro, symbol: "hourglass", title: s("Ayu.ProfileExtras.Loading"), label: ""))
        }
        return entries
    }
    let editable = !model.busy && model.mediaStatus == nil && model.verified

    if !model.verified {
        entries.append(.header(id: 5, section: .verify, text: s("Ayu.ProfileExtras.Verify.Section")))
        if model.awaitingVerification {
            let code = model.verificationCode.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
            entries.append(.status(id: 6, section: .verify, symbol: "hourglass", title: s("Ayu.ProfileExtras.Verify.Waiting"), label: code))
            entries.append(.action(id: 7, section: .verify, key: .verify, symbol: "paperplane.fill", title: s("Ayu.ProfileExtras.Verify.Again"), enabled: !model.busy))
            entries.append(.footer(id: 8, section: .verify, text: i18n("Ayu.ProfileExtras.Verify.WaitingInfo", locale, code)))
        } else {
            entries.append(.action(id: 7, section: .verify, key: .verify, symbol: "checkmark.shield.fill", title: s("Ayu.ProfileExtras.Verify.Action"), enabled: !model.busy))
            entries.append(.footer(id: 8, section: .verify, text: s("Ayu.ProfileExtras.Verify.Info")))
        }
    }

    entries.append(.header(id: 10, section: .bubbles, text: s("Ayu.ProfileExtras.BubblesSection")))
    entries.append(.bubbles(id: 11, title: s("Ayu.ProfileExtras.Bubbles"), value: model.bubbles, enabled: editable))
    entries.append(.footer(id: 12, section: .bubbles, text: s("Ayu.ProfileExtras.BubblesInfo")))

    entries.append(.header(id: 20, section: .background, text: s("Ayu.ProfileExtras.BackgroundSection")))
    if let mediaStatus = model.mediaStatus {
        entries.append(.status(id: 21, section: .background, symbol: "arrow.up.circle.fill", title: mediaStatus, label: ""))
    } else if let background = model.saved?.background {
        entries.append(.status(id: 21, section: .background, symbol: background.isVideo ? "video.fill" : "photo.fill", title: s("Ayu.ProfileExtras.CurrentBackground"), label: s(background.isVideo ? "Ayu.ProfileExtras.Video" : "Ayu.ProfileExtras.Photo")))
    }
    entries.append(.action(id: 22, section: .background, key: .choosePhoto, symbol: "photo.on.rectangle", title: s("Ayu.ProfileExtras.ChoosePhoto"), enabled: editable))
    entries.append(.action(id: 23, section: .background, key: .chooseVideo, symbol: "video.badge.plus", title: s("Ayu.ProfileExtras.ChooseVideo"), enabled: editable))
    if model.saved?.background != nil {
        entries.append(.destructive(id: 24, section: .background, key: .removeBackground, title: s("Ayu.ProfileExtras.RemoveBackground"), enabled: editable))
    }
    entries.append(.footer(id: 25, section: .background, text: s("Ayu.ProfileExtras.BackgroundInfo")))

    entries.append(.header(id: 100, section: .nfts, text: s("Ayu.ProfileExtras.NftsSection") + " · \(model.nfts.count)/\(model.limits.nfts)"))
    entries.append(.action(id: 101, section: .nfts, key: .addNft, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.AddNft"), enabled: editable && model.nfts.count < model.limits.nfts))
    for (index, nft) in model.nfts.enumerated() {
        var title = nft.title
        if let slug = nft.slug, let gift = model.gifts[slug.lowercased()] {
            title = "\(gift.title) #\(gift.number)"
        }
        entries.append(.nft(id: 200 + index, index: index, title: title, label: nft.pinned ? "📌 " + s("Ayu.ProfileExtras.Pinned") : "", enabled: editable))
    }
    entries.append(.footer(id: 300, section: .nfts, text: s("Ayu.ProfileExtras.NftsInfo")))

    entries.append(.header(id: 400, section: .usernames, text: s("Ayu.ProfileExtras.UsernamesSection") + " · \(model.usernames.count)/\(model.limits.usernames)"))
    entries.append(.action(id: 401, section: .usernames, key: .addUsername, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.AddUsername"), enabled: editable && model.usernames.count < model.limits.usernames))
    for (index, name) in model.usernames.enumerated() {
        entries.append(.username(id: 500 + index, index: index, title: "@" + name, enabled: editable))
    }
    entries.append(.footer(id: 600, section: .usernames, text: s("Ayu.ProfileExtras.UsernamesInfo")))

    let hasAnything = !(model.saved?.isEmpty ?? true)
    entries.append(.destructive(id: 700, section: .danger, key: .deleteAll, title: s("Ayu.ProfileExtras.DeleteAll"), enabled: editable && hasAnything))
    entries.append(.footer(id: 701, section: .danger, text: s("Ayu.ProfileExtras.Footer")))
    return entries
}

public func ayuGramProfileExtrasController(context: AccountContext) -> ViewController {
    let accountId = context.account.peerId.id._internalGetInt64Value()
    let model = AyuProfileExtrasModel()
    let disposables = DisposableSet()
    let holder = AyuProfileExtrasHolder(model: model, disposables: disposables)
    let updates = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    let changed: () -> Void = {
        revision += 1
        updates.set(revision)
    }
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    func locale() -> String {
        return context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    }

    func showText(_ text: String) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
    }

    func showError(_ error: AyuGramProfileError) {
        showText(ayuProfileErrorText(error, locale: locale()))
    }

    func startVerification() {
        guard !model.busy else {
            return
        }
        model.busy = true
        changed()
        AyuGramProfileRelay.shared.startVerification(accountId: accountId, completion: { result in
            model.busy = false
            switch result {
            case let .success(verification):
                model.awaitingVerification = true
                model.verificationCode = verification.code
                changed()
                ayuGramOpenLink(context: context, url: verification.url.absoluteString)
            case let .failure(error):
                changed()
                showError(error)
            }
        })
    }

    func askToVerify() {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        presentControllerImpl?(textAlertController(context: context, title: i18n("Ayu.ProfileExtras.Verify.Title", locale), text: i18n("Ayu.ProfileExtras.Verify.Prompt", locale), actions: [
            TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: i18n("Ayu.ProfileExtras.Verify.Action", locale), action: {
                startVerification()
            })
        ]))
    }

    func handleFailure(_ error: AyuGramProfileError) {
        if error == .unverified {
            model.verified = false
            changed()
            askToVerify()
        } else {
            showError(error)
        }
    }

    func resolveGifts() {
        for nft in model.nfts {
            guard let slug = nft.slug else {
                continue
            }
            let key = slug.lowercased()
            if model.gifts[key] != nil || model.resolving.contains(key) {
                continue
            }
            model.resolving.insert(key)
            disposables.add((AyuGramFakeNftResolver.shared.resolve(engine: context.engine, slug: slug)
            |> deliverOnMainQueue).start(next: { gift in
                model.resolving.remove(key)
                if let gift {
                    model.gifts[key] = gift
                    changed()
                }
            }))
        }
    }

    func load() {
        model.loadError = nil
        model.busy = true
        changed()
        AyuGramProfileRelay.shared.loadOwn(accountId: accountId, completion: { result in
            model.busy = false
            switch result {
            case let .success(own):
                model.apply(own, keepDraft: false)
                resolveGifts()
            case let .failure(error):
                model.loadError = error
            }
            changed()
        })
    }

    func reloadAfterVerification() {
        model.busy = true
        changed()
        AyuGramProfileRelay.shared.loadOwn(accountId: accountId, completion: { result in
            model.busy = false
            switch result {
            case let .success(own):
                model.apply(own, keepDraft: true)
                resolveGifts()
                if own.verified {
                    let data = context.sharedContext.currentPresentationData.with { $0 }
                    presentControllerImpl?(UndoOverlayController(presentationData: data, content: .succeed(text: i18n("Ayu.ProfileExtras.Verify.Done", locale()), timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
                }
            case let .failure(error):
                showError(error)
            }
            changed()
        })
    }

    func checkVerification(remaining: Int) {
        guard model.alive, model.loaded, !model.verified, !model.busy, !model.checkingVerification, remaining > 0 else {
            return
        }
        model.checkingVerification = true
        AyuGramProfileRelay.shared.verificationStatus(accountId: accountId, completion: { result in
            model.checkingVerification = false
            guard model.alive, !model.verified else {
                return
            }
            if case .success(true) = result {
                reloadAfterVerification()
                return
            }
            if remaining > 1 {
                Queue.mainQueue().after(2.0, {
                    checkVerification(remaining: remaining - 1)
                })
            }
        })
    }

    func save(completion: (() -> Void)? = nil) {
        guard model.dirty, !model.busy else {
            completion?()
            return
        }
        model.busy = true
        changed()
        AyuGramProfileRelay.shared.updateOwn(accountId: accountId, nfts: model.nfts, usernames: model.usernames, bubbles: model.bubbles, completion: { result in
            model.busy = false
            switch result {
            case let .success(own):
                model.apply(own, keepDraft: false)
                resolveGifts()
                let data = context.sharedContext.currentPresentationData.with { $0 }
                presentControllerImpl?(UndoOverlayController(presentationData: data, content: .succeed(text: i18n("Ayu.ProfileExtras.Saved", locale()), timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
                completion?()
            case let .failure(error):
                handleFailure(error)
            }
            changed()
        })
    }

    func upload(_ prepared: AyuPreparedProfileMedia) {
        AyuGramProfileRelay.shared.setPreview(rawId: accountId, url: prepared.url, isVideo: prepared.isVideo)
        model.mediaStatus = i18n("Ayu.ProfileExtras.Uploading", locale(), "0%")
        changed()
        AyuGramProfileRelay.shared.uploadBackground(accountId: accountId, file: prepared.url, mime: prepared.mime, width: prepared.width, height: prepared.height, progress: { value in
            model.mediaStatus = i18n("Ayu.ProfileExtras.Uploading", locale(), "\(Int((value * 100.0).rounded()))%")
            changed()
        }, completion: { result in
            model.mediaStatus = nil
            AyuGramProfileRelay.shared.clearPreview(rawId: accountId)
            switch result {
            case let .success(own):
                model.apply(own, keepDraft: true)
            case let .failure(error):
                handleFailure(error)
            }
            changed()
        })
    }

    func handlePicked(url: URL?, isVideo: Bool) {
        guard let url else {
            showError(.badMedia)
            return
        }
        model.mediaStatus = i18n("Ayu.ProfileExtras.Preparing", locale())
        changed()
        let limits = model.limits
        if isVideo {
            let exporter = AyuProfileVideoExporter(source: url, maxSeconds: limits.seconds, maxBytes: limits.video, progress: { value in
                model.mediaStatus = i18n("Ayu.ProfileExtras.Preparing", locale()) + " \(Int((value * 100.0).rounded()))%"
                changed()
            }, completion: { prepared in
                try? FileManager.default.removeItem(at: url)
                if let prepared {
                    upload(prepared)
                } else {
                    model.mediaStatus = nil
                    changed()
                    showError(.badMedia)
                }
            })
            exporter.start()
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                let prepared = ayuPrepareProfilePhoto(url, maxBytes: limits.photo)
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    if let prepared {
                        upload(prepared)
                    } else {
                        model.mediaStatus = nil
                        changed()
                        showError(.badMedia)
                    }
                }
            }
        }
    }

    holder.picker.completion = { url, isVideo in
        handlePicked(url: url, isVideo: isVideo)
    }

    func confirm(text: String, action: String, perform: @escaping () -> Void) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [
            TextAlertAction(type: .genericAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: action, action: perform)
        ]))
    }

    func addNft(_ value: String) {
        guard let slug = AyuGramProfileNft.parseSlug(value) else {
            showText(i18n("Ayu.ProfileExtras.Error.NftNotFound", locale()))
            return
        }
        if model.nfts.contains(where: { $0.slug?.lowercased() == slug.lowercased() }) {
            showText(i18n("Ayu.ProfileExtras.Error.NftExists", locale()))
            return
        }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let progress = OverlayStatusController(theme: data.theme, type: .loading(cancelled: nil))
        presentControllerImpl?(progress)
        disposables.add((AyuGramFakeNftResolver.shared.fetch(engine: context.engine, slug: slug)
        |> deliverOnMainQueue).start(next: { gift in
            progress.dismiss()
            let canonical = AyuGramProfileNft.isValidSlug(gift.slug) ? gift.slug : slug
            model.gifts[canonical.lowercased()] = gift
            model.gifts[slug.lowercased()] = gift
            if model.nfts.contains(where: { $0.slug?.lowercased() == canonical.lowercased() }) || model.nfts.count >= model.limits.nfts {
                return
            }
            let pinned = model.nfts.filter { $0.pinned }.count < model.limits.pinned
            model.nfts.append(AyuGramProfileNft(slug: canonical, pinned: pinned))
            changed()
        }, error: { error in
            progress.dismiss()
            switch error {
            case .alreadyBurned:
                showText(i18n("Ayu.ProfileExtras.Error.NftBurned", locale()))
            case .invalidSlug:
                showText(i18n("Ayu.ProfileExtras.Error.NftNotFound", locale()))
            case .generic:
                showText(i18n("Ayu.ProfileExtras.Error.Network", locale()))
            }
        }))
    }

    func addUsername(_ value: String) {
        guard let name = AyuGramProfileEntry.normalizeUsername(value) else {
            showText(i18n("Ayu.ProfileExtras.Error.BadUsername", locale()))
            return
        }
        if ayuProfileReservedExact.contains(name) || ayuProfileReservedParts.contains(where: { name.contains($0) }) {
            showError(.reservedUsername(name))
            return
        }
        if model.usernames.contains(name) {
            return
        }
        model.usernames.append(name)
        changed()
    }

    func moveItem<T>(_ items: inout [T], from index: Int, by offset: Int) {
        let target = index + offset
        guard index >= 0, index < items.count, target >= 0, target < items.count else {
            return
        }
        let item = items.remove(at: index)
        items.insert(item, at: target)
    }

    let arguments = AyuProfileExtrasArguments(toggleBubbles: { value in
        model.bubbles = value
        changed()
    }, perform: { action in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        switch action {
        case .retry:
            load()
        case .verify:
            startVerification()
        case .choosePhoto:
            holder.picker.choose(video: false)
        case .chooseVideo:
            holder.picker.choose(video: true)
        case .removeBackground:
            confirm(text: i18n("Ayu.ProfileExtras.RemoveBackgroundConfirm", locale), action: i18n("Ayu.ProfileExtras.RemoveBackground", locale), perform: {
                model.busy = true
                changed()
                AyuGramProfileRelay.shared.removeBackground(accountId: accountId, completion: { result in
                    model.busy = false
                    switch result {
                    case let .success(own):
                        model.apply(own, keepDraft: true)
                    case let .failure(error):
                        handleFailure(error)
                    }
                    changed()
                })
            })
        case .addNft:
            presentControllerImpl?(promptController(context: context, text: i18n("Ayu.ProfileExtras.AddNftPrompt", locale), value: "", placeholder: "t.me/nft/PlushPepe-1", characterLimit: 200, apply: { value in
                if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    addNft(value)
                }
            }))
        case .addUsername:
            presentControllerImpl?(promptController(context: context, text: i18n("Ayu.ProfileExtras.AddUsernamePrompt", locale), value: "", placeholder: "@username", characterLimit: 40, apply: { value in
                if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    addUsername(value)
                }
            }))
        case .deleteAll:
            confirm(text: i18n("Ayu.ProfileExtras.DeleteAllConfirm", locale), action: i18n("Ayu.ProfileExtras.DeleteAll", locale), perform: {
                model.busy = true
                changed()
                AyuGramProfileRelay.shared.removeAll(accountId: accountId, completion: { result in
                    model.busy = false
                    switch result {
                    case let .success(own):
                        model.apply(own, keepDraft: false)
                    case let .failure(error):
                        handleFailure(error)
                    }
                    changed()
                })
            })
        }
    }, openNft: { index in
        guard index >= 0, index < model.nfts.count else {
            return
        }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        let nft = model.nfts[index]
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = []
        var title = nft.title
        var previewGift: StarGift.UniqueGift?
        if let slug = nft.slug, let gift = model.gifts[slug.lowercased()] {
            title = "\(gift.title) #\(gift.number)"
            previewGift = gift
        }
        items.append(ActionSheetTextItem(title: title, parseMarkdown: false))
        if let previewGift {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.Preview", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                pushControllerImpl?(ayuGramFakeNftViewScreen(context: context, gift: previewGift))
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n(nft.pinned ? "Ayu.ProfileExtras.Unpin" : "Ayu.ProfileExtras.Pin", locale), color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            guard index < model.nfts.count else {
                return
            }
            if !model.nfts[index].pinned && model.nfts.filter({ $0.pinned }).count >= model.limits.pinned {
                showText(i18n("Ayu.ProfileExtras.Error.PinLimit", locale))
                return
            }
            model.nfts[index] = model.nfts[index].withPinned(!model.nfts[index].pinned)
            changed()
        }))
        if index > 0 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveUp", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.nfts, from: index, by: -1)
                changed()
            }))
        }
        if index < model.nfts.count - 1 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveDown", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.nfts, from: index, by: 1)
                changed()
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.Delete", locale), color: .destructive, action: { [weak sheet] in
            sheet?.dismissAnimated()
            guard index < model.nfts.count else {
                return
            }
            model.nfts.remove(at: index)
            changed()
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(sheet)
    }, openUsername: { index in
        guard index >= 0, index < model.usernames.count else {
            return
        }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetTextItem(title: "@" + model.usernames[index], parseMarkdown: false))
        if index > 0 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveUp", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.usernames, from: index, by: -1)
                changed()
            }))
        }
        if index < model.usernames.count - 1 {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.MoveDown", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                moveItem(&model.usernames, from: index, by: 1)
                changed()
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.Delete", locale), color: .destructive, action: { [weak sheet] in
            sheet?.dismissAnimated()
            guard index < model.usernames.count else {
                return
            }
            model.usernames.remove(at: index)
            changed()
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        presentControllerImpl?(sheet)
    })

    let signal = combineLatest(context.sharedContext.presentationData, updates.get())
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, AyuProfileExtrasArguments)) in
        let locale = data.strings.baseLanguageCode
        let rightButton: ItemListNavigationButton?
        if model.busy {
            rightButton = ItemListNavigationButton(content: .none, style: .activity, enabled: true, action: {})
        } else if model.loaded {
            rightButton = ItemListNavigationButton(content: .text(data.strings.Common_Save), style: .bold, enabled: model.dirty && model.mediaStatus == nil, action: {
                save()
            })
        } else {
            rightButton = nil
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(i18n("Ayu.ProfileExtras.Title", locale)), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: ayuProfileExtrasEntries(data: data, model: model), style: .blocks, animateChanges: true)
        return (state, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    holder.picker.controller = controller
    controller.didDisappear = { _ in
        let _ = holder
    }
    controller.didAppear = { firstTime in
        if !firstTime && model.loaded && model.awaitingVerification && !model.verified {
            checkVerification(remaining: 5)
        }
    }
    holder.foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { _ in
        if model.loaded && model.awaitingVerification && !model.verified {
            checkVerification(remaining: 5)
        }
    })
    controller.attemptNavigation = { proceed in
        guard model.dirty else {
            return true
        }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        presentControllerImpl?(textAlertController(context: context, title: nil, text: i18n("Ayu.ProfileExtras.UnsavedChanges", locale), actions: [
            TextAlertAction(type: .genericAction, title: i18n("Ayu.ProfileExtras.Discard", locale), action: {
                model.nfts = model.saved?.nfts ?? []
                model.usernames = model.saved?.usernames ?? []
                model.bubbles = model.saved?.bubbles ?? false
                proceed()
            }),
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Save, action: {
                save(completion: proceed)
            })
        ]))
        return false
    }
    presentControllerImpl = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    load()
    return controller
}
