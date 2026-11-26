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
import SGItemListUI
import GiftViewScreen
import SGSimpleSettings
import SGStrings
import AyuGramProfileExtras

private enum AyuProfileExtrasSection: Int32 {
    case intro, verify, nfts, number, usernames, bubbles, background, brightness, danger
}

private enum AyuProfileExtrasEntry: ItemListNodeEntry {
    case intro(id: Int, text: String)
    case retry(id: Int, title: String)
    case toggle(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasToggle, symbol: String, title: String, value: Bool, enabled: Bool)
    case brightness(id: Int, value: Int32, enabled: Bool)
    case header(id: Int, section: AyuProfileExtrasSection, text: String)
    case footer(id: Int, section: AyuProfileExtrasSection, text: String)
    case status(id: Int, section: AyuProfileExtrasSection, symbol: String, title: String, label: String)
    case action(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasAction, symbol: String, title: String, enabled: Bool)
    case destructive(id: Int, section: AyuProfileExtrasSection, key: AyuProfileExtrasAction, title: String, enabled: Bool)
    case nft(id: Int, sortIndex: Int, index: Int, title: String, label: String, color: UInt32, isReordering: Bool, enabled: Bool)
    case username(id: Int, index: Int, title: String, enabled: Bool)

    var section: ItemListSectionId {
        switch self {
        case .intro, .retry:
            return AyuProfileExtrasSection.intro.rawValue
        case let .toggle(_, section, _, _, _, _, _):
            return section.rawValue
        case .brightness:
            return AyuProfileExtrasSection.brightness.rawValue
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
        case let .toggle(id, _, _, _, _, _, _):
            return id
        case let .brightness(id, _, _):
            return id
        case let .header(id, _, _), let .footer(id, _, _):
            return id
        case let .status(id, _, _, _, _):
            return id
        case let .action(id, _, _, _, _, _):
            return id
        case let .destructive(id, _, _, _, _):
            return id
        case let .nft(id, _, _, _, _, _, _, _):
            return id
        case let .username(id, _, _, _):
            return id
        }
    }

    var sortIndex: Int {
        if case let .nft(_, sortIndex, _, _, _, _, _, _) = self {
            return sortIndex
        }
        return self.stableId
    }

    static func <(lhs: AyuProfileExtrasEntry, rhs: AyuProfileExtrasEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
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
        case let .toggle(_, _, key, symbol, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: AyuGramRowColor.blue), title: title, value: value, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .brightness(_, value, enabled):
            return SliderPercentageItem(theme: presentationData.theme, strings: presentationData.strings, value: value, sectionId: self.section, updated: { value in
                if enabled {
                    arguments.updateBrightness(value)
                }
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
        case let .nft(_, _, index, title, label, color, isReordering, enabled):
            return AyuGramFakeNftRowItem(presentationData: presentationData, title: title, subtitle: label, color: color == 0 ? AyuGramRowColor.purple : UIColor(rgb: color), symbol: "gift.fill", isReordering: isReordering, enabled: enabled, sectionId: self.section, action: {
                arguments.openNft(index)
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

private enum AyuProfileExtrasToggle: Equatable {
    case bubbles
    case showBubbles
    case hideReal
}

private enum AyuProfileExtrasAction: Equatable {
    case retry
    case verify
    case choosePhoto
    case chooseVideo
    case removeBackground
    case addNft
    case reorder
    case addUsername
    case number
    case deleteAll
}

private final class AyuProfileExtrasArguments {
    let toggle: (AyuProfileExtrasToggle, Bool) -> Void
    let updateBrightness: (Int32) -> Void
    let perform: (AyuProfileExtrasAction) -> Void
    let openNft: (Int) -> Void
    let openUsername: (Int) -> Void

    init(toggle: @escaping (AyuProfileExtrasToggle, Bool) -> Void, updateBrightness: @escaping (Int32) -> Void, perform: @escaping (AyuProfileExtrasAction) -> Void, openNft: @escaping (Int) -> Void, openUsername: @escaping (Int) -> Void) {
        self.toggle = toggle
        self.updateBrightness = updateBrightness
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
    var hideReal = false
    var statusSlug: String?
    var number: String?
    var brightness: Double = 0.0
    var verified = true
    var awaitingVerification = false
    var verificationCode: String?
    var checkingVerification = false
    var alive = true
    var busy = false
    var mediaStatus: String?
    var gifts: [String: StarGift.UniqueGift] = [:]
    var resolving = Set<String>()
    var reordering = false
    var numberBusy = false
    private var nftIds: [String: Int] = [:]
    private var nextNftId = 0

    func nftStableId(_ nft: AyuGramProfileNft) -> Int {
        if let id = self.nftIds[nft.key] {
            return id
        }
        self.nextNftId += 1
        self.nftIds[nft.key] = self.nextNftId
        return self.nextNftId
    }

    var dirty: Bool {
        guard let saved = self.saved else {
            return false
        }
        return !self.patch(saved: saved).isEmpty
    }

    func patch(saved: AyuGramProfileEntry) -> AyuGramProfilePatch {
        var patch = AyuGramProfilePatch()
        if self.nfts != saved.nfts {
            patch.nfts = self.nfts
        }
        if self.usernames != saved.usernames {
            patch.usernames = self.usernames
        }
        if AyuGramVariant.isCustom && self.bubbles != saved.bubbles {
            patch.bubbles = self.bubbles
        }
        if self.hideReal != saved.hideReal {
            patch.hideReal = self.hideReal
        }
        if self.statusSlug?.lowercased() != saved.statusSlug?.lowercased() {
            if let statusSlug = self.statusSlug {
                patch.status = .set(statusSlug)
            } else {
                patch.status = .clear
            }
        }
        if AyuGramVariant.isCustom && AyuGramProfileEntry.clampBrightness(self.brightness) != saved.brightness {
            patch.brightness = self.brightness
        }
        return patch
    }

    func discard() {
        self.nfts = self.saved?.nfts ?? []
        self.usernames = self.saved?.usernames ?? []
        self.bubbles = self.saved?.bubbles ?? false
        self.hideReal = self.saved?.hideReal ?? false
        self.statusSlug = self.saved?.statusSlug
        self.number = self.saved?.number
        self.brightness = self.saved?.brightness ?? 0.0
    }

    func dropStatusIfMissing() {
        guard let statusSlug = self.statusSlug?.lowercased() else {
            return
        }
        if !self.nfts.contains(where: { $0.slug?.lowercased() == statusSlug }) {
            self.statusSlug = nil
        }
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
            self.discard()
        }
        self.number = own.entry.number
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
    private var timer: Foundation.Timer?
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
        let oriented = track.naturalSize.applying(track.preferredTransform)
        self.naturalSize = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        self.transform = track.preferredTransform
        let rate = track.nominalFrameRate
        self.frameRate = Int32(max(24.0, min(120.0, rate > 0 ? Double(rate).rounded() : 30.0)))
        self.duration = range.duration
        let sourceSize = ((try? FileManager.default.attributesOfItem(atPath: self.source.path))?[.size] as? NSNumber)?.intValue ?? Int.max
        var presets = [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHEVC1920x1080, AVAssetExportPreset1280x720, AVAssetExportPreset960x540]
        if sourceSize <= self.maxBytes && max(self.naturalSize.width, self.naturalSize.height) <= 2560.5 {
            presets.insert(AVAssetExportPresetPassthrough, at: 0)
        }
        self.passthrough = presets.first == AVAssetExportPresetPassthrough
        self.export(composition: composition, presets: presets, index: 0)
    }

    private var naturalSize = CGSize()
    private var transform = CGAffineTransform.identity
    private var frameRate: Int32 = 30
    private var duration = CMTime.zero
    private var passthrough = false

    private func videoComposition(composition: AVMutableComposition, index rawIndex: Int) -> AVMutableVideoComposition? {
        if self.passthrough && rawIndex == 0 {
            return nil
        }
        let index = self.passthrough ? rawIndex - 1 : rawIndex
        let sides: [CGFloat] = [2560.0, 1920.0, 1920.0, 1280.0, 960.0]
        let rates: [Int32] = [self.frameRate, min(self.frameRate, 60), min(self.frameRate, 60), min(self.frameRate, 30), min(self.frameRate, 30)]
        guard index >= 0, index < sides.count, let track = composition.tracks(withMediaType: .video).first, self.naturalSize.width > 0, self.naturalSize.height > 0 else {
            return nil
        }
        let scale = min(1.0, sides[index] / max(self.naturalSize.width, self.naturalSize.height))
        let render = CGSize(width: max(2.0, floor(self.naturalSize.width * scale / 2.0) * 2.0), height: max(2.0, floor(self.naturalSize.height * scale / 2.0) * 2.0))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: self.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(self.transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        instruction.layerInstructions = [layer]
        let video = AVMutableVideoComposition()
        video.renderSize = render
        video.frameDuration = CMTime(value: 1, timescale: rates[index])
        video.instructions = [instruction]
        return video
    }

    private func export(composition: AVMutableComposition, presets: [String], index: Int) {
        guard index < presets.count, let session = AVAssetExportSession(asset: composition, presetName: presets[index]) else {
            self.finish(nil)
            return
        }
        if let video = self.videoComposition(composition: composition, index: index) {
            session.videoComposition = video
        }
        let target = AyuGramProfileRelay.makePreviewURL(fileExtension: "mp4")
        session.outputURL = target
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        self.session = session
        self.timer?.invalidate()
        let base = Double(index) / Double(presets.count)
        let span = 1.0 / Double(presets.count)
        self.timer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: { [weak self, weak session] _ in
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
                    if session.status == .completed || (self.passthrough && index == 0) {
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

private func ayuProfileNftColor(_ gift: StarGift.UniqueGift?) -> UInt32 {
    guard let gift else {
        return 0
    }
    for attribute in gift.attributes {
        if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
            return UInt32(bitPattern: innerColor)
        }
    }
    return 0
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
            entries.append(.footer(id: 1, section: .intro, text: ayuGramProfileErrorText(loadError, locale: locale)))
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

    let reordering = model.reordering && model.nfts.count > 1
    entries.append(.header(id: 100, section: .nfts, text: s("Ayu.ProfileExtras.NftsSection") + " · \(model.nfts.count)/\(model.limits.nfts)"))
    if !reordering {
        entries.append(.action(id: 101, section: .nfts, key: .addNft, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.AddNft"), enabled: editable && model.nfts.count < model.limits.nfts))
    }
    for (index, nft) in model.nfts.enumerated() {
        var title = nft.title
        var gift: StarGift.UniqueGift?
        if let slug = nft.slug, let resolved = model.gifts[slug.lowercased()] {
            title = "\(resolved.title) #\(resolved.number)"
            gift = resolved
        }
        var marks: [String] = []
        if let slug = nft.slug, slug.lowercased() == model.statusSlug?.lowercased() {
            marks.append(s("Ayu.ProfileExtras.Status"))
        }
        if nft.pinned {
            marks.append(s("Ayu.ProfileExtras.Pinned"))
        }
        entries.append(.nft(id: 100000 + model.nftStableId(nft), sortIndex: 200 + index, index: index, title: title, label: marks.joined(separator: " · "), color: ayuProfileNftColor(gift), isReordering: reordering, enabled: editable))
    }
    if model.nfts.count > 1 {
        entries.append(.action(id: 280, section: .nfts, key: .reorder, symbol: reordering ? "checkmark.circle.fill" : "arrow.up.arrow.down", title: s(reordering ? "Ayu.ProfileExtras.ReorderDone" : "Ayu.ProfileExtras.Reorder"), enabled: editable))
    }
    entries.append(.toggle(id: 290, section: .nfts, key: .hideReal, symbol: "eye.slash.fill", title: s("Ayu.ProfileExtras.HideReal"), value: model.hideReal, enabled: editable))
    entries.append(.footer(id: 300, section: .nfts, text: reordering ? s("Ayu.ProfileExtras.ReorderInfo") : s("Ayu.ProfileExtras.NftsInfo") + "\n" + s("Ayu.ProfileExtras.HideRealInfo")))

    entries.append(.header(id: 310, section: .number, text: s("Ayu.ProfileExtras.NumberSection")))
    if model.numberBusy {
        entries.append(.status(id: 311, section: .number, symbol: "hourglass", title: s("Ayu.ProfileExtras.Loading"), label: ""))
    } else if let number = model.number {
        entries.append(.action(id: 311, section: .number, key: .number, symbol: "phone.fill", title: AyuGramProfileEntry.formatNumber(number), enabled: editable && !model.dirty))
    } else {
        entries.append(.action(id: 311, section: .number, key: .number, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.ClaimNumber"), enabled: editable && !model.dirty))
    }
    entries.append(.footer(id: 312, section: .number, text: model.dirty ? s("Ayu.ProfileExtras.NumberSaveFirst") : s("Ayu.ProfileExtras.NumberInfo")))

    entries.append(.header(id: 400, section: .usernames, text: s("Ayu.ProfileExtras.UsernamesSection") + " · \(model.usernames.count)/\(model.limits.usernames)"))
    entries.append(.action(id: 401, section: .usernames, key: .addUsername, symbol: "plus.circle.fill", title: s("Ayu.ProfileExtras.AddUsername"), enabled: editable && model.usernames.count < model.limits.usernames))
    for (index, name) in model.usernames.enumerated() {
        entries.append(.username(id: 500 + index, index: index, title: "@" + name, enabled: editable))
    }
    entries.append(.footer(id: 600, section: .usernames, text: s("Ayu.ProfileExtras.UsernamesInfo")))

    let fullEditing = AyuGramVariant.isCustom
    entries.append(.header(id: 610, section: .bubbles, text: s("Ayu.ProfileExtras.BubblesSection")))
    if fullEditing {
        entries.append(.toggle(id: 611, section: .bubbles, key: .bubbles, symbol: "bubbles.and.sparkles.fill", title: s("Ayu.ProfileExtras.Bubbles"), value: model.bubbles, enabled: editable))
    }
    entries.append(.toggle(id: 612, section: .bubbles, key: .showBubbles, symbol: "eye.fill", title: s("Ayu.ProfileExtras.ShowBubbles"), value: AyuGramProfileRelay.bubblesEnabled, enabled: true))
    entries.append(.footer(id: 613, section: .bubbles, text: fullEditing ? s("Ayu.ProfileExtras.BubblesInfo") : s("Ayu.ProfileExtras.BubblesInfoStandard")))

    if fullEditing {
        entries.append(.header(id: 620, section: .background, text: s("Ayu.ProfileExtras.BackgroundSection")))
        if let mediaStatus = model.mediaStatus {
            entries.append(.status(id: 621, section: .background, symbol: "arrow.up.circle.fill", title: mediaStatus, label: ""))
        } else if let background = model.saved?.background {
            entries.append(.status(id: 621, section: .background, symbol: background.isVideo ? "video.fill" : "photo.fill", title: s("Ayu.ProfileExtras.CurrentBackground"), label: s(background.isVideo ? "Ayu.ProfileExtras.Video" : "Ayu.ProfileExtras.Photo")))
        }
        entries.append(.action(id: 622, section: .background, key: .choosePhoto, symbol: "photo.on.rectangle", title: s("Ayu.ProfileExtras.ChoosePhoto"), enabled: editable))
        entries.append(.action(id: 623, section: .background, key: .chooseVideo, symbol: "video.badge.plus", title: s("Ayu.ProfileExtras.ChooseVideo"), enabled: editable))
        if model.saved?.background != nil {
            entries.append(.destructive(id: 624, section: .background, key: .removeBackground, title: s("Ayu.ProfileExtras.RemoveBackground"), enabled: editable))
        }
        entries.append(.footer(id: 625, section: .background, text: s("Ayu.ProfileExtras.BackgroundInfo")))
        if model.saved?.background != nil {
            entries.append(.header(id: 630, section: .brightness, text: s("Ayu.ProfileExtras.Brightness")))
            entries.append(.brightness(id: 631, value: Int32(((model.brightness + 1.0) * 50.0).rounded()), enabled: editable))
            entries.append(.footer(id: 632, section: .brightness, text: s("Ayu.ProfileExtras.BrightnessInfo")))
        }
    } else if let background = model.saved?.background {
        entries.append(.header(id: 620, section: .background, text: s("Ayu.ProfileExtras.BackgroundSection")))
        entries.append(.status(id: 621, section: .background, symbol: background.isVideo ? "video.fill" : "photo.fill", title: s("Ayu.ProfileExtras.CurrentBackground"), label: s(background.isVideo ? "Ayu.ProfileExtras.Video" : "Ayu.ProfileExtras.Photo")))
        entries.append(.destructive(id: 624, section: .background, key: .removeBackground, title: s("Ayu.ProfileExtras.RemoveBackground"), enabled: editable))
        entries.append(.footer(id: 625, section: .background, text: s("Ayu.ProfileExtras.CustomOnly")))
    }

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
    var popToSelfImpl: (() -> Void)?

    func locale() -> String {
        return context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    }

    func showText(_ text: String) {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
    }

    func showError(_ error: AyuGramProfileError) {
        showText(ayuGramProfileErrorText(error, locale: locale()))
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
        guard let saved = model.saved else {
            model.busy = false
            changed()
            completion?()
            return
        }
        AyuGramProfileRelay.shared.updateOwn(accountId: accountId, patch: model.patch(saved: saved), completion: { result in
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

    func applyNumber(_ change: AyuGramProfileNumberChange) {
        guard !model.numberBusy, !model.busy else {
            return
        }
        model.numberBusy = true
        changed()
        AyuGramProfileRelay.shared.updateOwn(accountId: accountId, patch: AyuGramProfilePatch(number: change), completion: { result in
            model.numberBusy = false
            switch result {
            case let .success(own):
                model.apply(own, keepDraft: true)
                let data = context.sharedContext.currentPresentationData.with { $0 }
                let text: String
                if let number = own.entry.number {
                    text = i18n("Ayu.ProfileExtras.NumberClaimed", locale(), AyuGramProfileEntry.formatNumber(number))
                } else {
                    text = i18n("Ayu.ProfileExtras.NumberFreed", locale())
                }
                presentControllerImpl?(UndoOverlayController(presentationData: data, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
            case let .failure(error):
                handleFailure(error)
            }
            changed()
        })
    }

    func setNumber(_ value: String) {
        guard let number = AyuGramProfileEntry.normalizeNumber(value) else {
            showError(.badNumber)
            return
        }
        if number == model.number {
            return
        }
        applyNumber(.set(number))
    }

    func askNumber() {
        presentControllerImpl?(promptController(context: context, text: i18n("Ayu.ProfileExtras.NumberPrompt", locale()), value: model.number.map(AyuGramProfileEntry.formatNumber) ?? "+888 ", placeholder: "+888 1234 5678", characterLimit: 24, apply: { value in
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                setNumber(value)
            }
        }))
    }

    func addGift(_ gift: StarGift.UniqueGift) -> Bool {
        guard AyuGramProfileNft.isValidSlug(gift.slug) else {
            showText(i18n("Ayu.ProfileExtras.Error.NftNotFound", locale()))
            return false
        }
        if model.nfts.contains(where: { $0.slug?.lowercased() == gift.slug.lowercased() }) {
            showText(i18n("Ayu.ProfileExtras.Error.NftExists", locale()))
            return false
        }
        if model.nfts.count >= model.limits.nfts {
            showText(i18n("Ayu.ProfileExtras.Error.NftLimit", locale(), "\(model.limits.nfts)"))
            return false
        }
        model.gifts[gift.slug.lowercased()] = gift
        let pinned = model.nfts.filter { $0.pinned }.count < model.limits.pinned
        model.nfts.append(AyuGramProfileNft(slug: gift.slug, pinned: pinned))
        changed()
        return true
    }

    let arguments = AyuProfileExtrasArguments(toggle: { key, value in
        switch key {
        case .bubbles:
            if AyuGramVariant.isCustom {
                model.bubbles = value
            }
        case .showBubbles:
            AyuGramProfileRelay.bubblesEnabled = value
        case .hideReal:
            model.hideReal = value
        }
        changed()
    }, updateBrightness: { value in
        guard AyuGramVariant.isCustom else {
            return
        }
        model.brightness = AyuGramProfileEntry.clampBrightness(Double(value) / 50.0 - 1.0)
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
            if AyuGramVariant.isCustom {
                holder.picker.choose(video: false)
            }
        case .chooseVideo:
            if AyuGramVariant.isCustom {
                holder.picker.choose(video: true)
            }
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
            guard model.nfts.count < model.limits.nfts else {
                showText(i18n("Ayu.ProfileExtras.Error.NftLimit", locale, "\(model.limits.nfts)"))
                return
            }
            pushControllerImpl?(ayuGramNftSearchController(context: context, onPick: { gift in
                if addGift(gift) {
                    popToSelfImpl?()
                }
            }))
        case .reorder:
            model.reordering = !model.reordering
            changed()
        case .number:
            if model.dirty {
                showText(i18n("Ayu.ProfileExtras.NumberSaveFirst", locale))
                return
            }
            let sheet = ActionSheetController(presentationData: data)
            var numberItems: [ActionSheetItem] = []
            if let number = model.number {
                numberItems.append(ActionSheetTextItem(title: AyuGramProfileEntry.formatNumber(number), parseMarkdown: false))
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.ChangeNumber", locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    askNumber()
                }))
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.ClearNumber", locale), color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    confirm(text: i18n("Ayu.ProfileExtras.ClearNumberConfirm", locale), action: i18n("Ayu.ProfileExtras.ClearNumber", locale), perform: {
                        applyNumber(.clear)
                    })
                }))
            } else {
                numberItems.append(ActionSheetTextItem(title: i18n("Ayu.ProfileExtras.NumberOnlyOne", locale), parseMarkdown: false))
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.EnterNumber", locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    askNumber()
                }))
                numberItems.append(ActionSheetButtonItem(title: i18n("Ayu.ProfileExtras.RandomNumber", locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    setNumber(ayuGramRandomAnonymousNumber())
                }))
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: numberItems),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                })])
            ])
            presentControllerImpl?(sheet)
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
        if let slug = nft.slug {
            let isStatus = slug.lowercased() == model.statusSlug?.lowercased()
            items.append(ActionSheetButtonItem(title: i18n(isStatus ? "Ayu.ProfileExtras.RemoveStatus" : "Ayu.ProfileExtras.SetStatus", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                model.statusSlug = isStatus ? nil : slug
                changed()
            }))
        }
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
            model.dropStatusIfMissing()
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
                model.discard()
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
    popToSelfImpl = { [weak controller] in
        guard let controller, let navigationController = controller.navigationController as? NavigationController else {
            return
        }
        let _ = navigationController.popToViewController(controller, animated: true)
    }
    controller.setReorderEntry({ (fromIndex: Int, toIndex: Int, entries: [AyuProfileExtrasEntry]) -> Signal<Bool, NoError> in
        guard fromIndex >= 0, fromIndex < entries.count, case let .nft(_, _, fromNft, _, _, _, _, _) = entries[fromIndex] else {
            return .single(false)
        }
        let target: Int
        if toIndex >= 0, toIndex < entries.count, case let .nft(_, _, index, _, _, _, _, _) = entries[toIndex] {
            target = index
        } else if toIndex >= 0, toIndex < entries.count, entries[toIndex] < entries[fromIndex] {
            target = 0
        } else {
            target = model.nfts.count - 1
        }
        guard fromNft >= 0, fromNft < model.nfts.count, target >= 0, target < model.nfts.count, target != fromNft else {
            return .single(false)
        }
        let item = model.nfts.remove(at: fromNft)
        model.nfts.insert(item, at: target)
        changed()
        return .single(true)
    })
    load()
    return controller
}
