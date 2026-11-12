import Foundation
import UIKit
import PhotosUI
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import SGItemListUI
import SGSimpleSettings
import SGStrings

private enum AyuAppearanceSection: Int32, SGItemListSection { case preview, media, visibility, dim, blur, rows, newYear, effects, amount, reset }
private enum AyuAppearanceToggle: Hashable { case enabled, motion, newYear, newYearAuto, particles, particlesInChats, seasonal, drift, fireworks, parallax }
private enum AyuAppearanceSlider: Hashable { case dim, blur, rows, amount }
private enum AyuAppearanceAction: Hashable { case photo, video, wallpaper, reset, particleKind, selectKind(Int32), previewKind(Int32) }
private enum AyuAppearanceUnused: Hashable { case unused }
private typealias AyuAppearanceSettingEntry = SGItemListUIEntry<AyuAppearanceSection, AyuAppearanceToggle, AyuAppearanceSlider, AyuAppearanceUnused, AyuAppearanceAction, AyuAppearanceAction>
private enum AyuAppearanceEntry: ItemListNodeEntry {
    case preview(AyuGramAppearanceScope, AyuGramAppearanceSettings)
    case setting(AyuAppearanceSettingEntry)
    case kindOption(Int, Int32, String, Bool)
    var section: ItemListSectionId {
        switch self { case .preview: return AyuAppearanceSection.preview.rawValue; case let .setting(value): return value.section; case .kindOption: return AyuAppearanceSection.effects.rawValue }
    }
    var stableId: Int {
        switch self { case .preview: return 0; case let .setting(value): return value.stableId + 1; case let .kindOption(id, _, _, _): return id }
    }
    static func < (lhs: AyuAppearanceEntry, rhs: AyuAppearanceEntry) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .preview(scope, settings): return AyuGramAppearancePreviewItem(data: presentationData, scope: scope, settings: settings, sectionId: section)
        case let .setting(value): return value.item(presentationData: presentationData, arguments: arguments)
        case let .kindOption(_, kind, title, selected):
            let args = arguments as! SGItemListArguments<AyuAppearanceToggle, AyuAppearanceSlider, AyuAppearanceUnused, AyuAppearanceAction, AyuAppearanceAction>
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: (selected ? "✓  " : "      ") + title, kind: selected ? .generic : .neutral, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.action(.selectKind(kind))
            }, longTapAction: {
                args.action(.previewKind(kind))
            })
        }
    }
}

public func ayuGramAppearanceController(context: AccountContext, scope: AyuGramAppearanceScope = .chatList) -> ViewController {
    let mediaPicker = AyuGramAppearanceMediaPicker(context: context, scope: scope)
    var openWallpaper: (() -> Void)?
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramAppearance.didChange, object: nil, queue: .main) { _ in subscriber.putNext(0) }
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
    let kindsExpanded = ValuePromise<Bool>(false, ignoreRepeated: true)
    var kindsExpandedValue = false
    let _ = kindsExpanded.get().startStandalone(next: { value in
        kindsExpandedValue = value
    })
    let arguments = SGItemListArguments<AyuAppearanceToggle, AyuAppearanceSlider, AyuAppearanceUnused, AyuAppearanceAction, AyuAppearanceAction>(context: context, setBoolValue: { key, value in
        switch key {
        case .newYear:
            AyuGramAppearance.shared.update { settings in
                settings.newYear = value
                if value {
                    settings.particleKind = 1
                    settings.seasonal = false
                }
            }
            return
        case .newYearAuto:
            AyuGramAppearance.shared.update { $0.newYearAuto = value }
            return
        case .particles:
            AyuGramAppearance.shared.update { $0.particles = value }
            return
        case .particlesInChats:
            AyuGramAppearance.shared.update { $0.particlesInChats = value }
            return
        case .seasonal:
            AyuGramAppearance.shared.update { $0.seasonal = value }
            return
        case .drift:
            AyuGramAppearance.shared.update { $0.drift = value }
            return
        case .fireworks:
            AyuGramAppearance.shared.update { $0.fireworks = value }
            return
        case .parallax:
            AyuGramAppearance.shared.update { $0.parallax = value }
            return
        case .enabled, .motion:
            break
        }
        AyuGramAppearance.shared.updateForScope(scope) { settings in
            switch key {
            case .enabled:
                if scope == .chatList { settings.chatList = value } else { settings.conversations = value }
            case .motion: settings.animateVideo = value
            case .newYear, .newYearAuto, .particles, .particlesInChats, .seasonal, .drift, .fireworks, .parallax:
                break
            }
        }
    }, updateSliderValue: { key, value in
        if case .amount = key {
            AyuGramAppearance.shared.update { $0.particleAmount = Float(value) / 100 }
            return
        }
        AyuGramAppearance.shared.updateForScope(scope) { settings in
            switch key {
            case .dim: settings.dim = Float(value) / 100
            case .blur: settings.blur = Float(value) / 100
            case .rows: settings.rowOpacity = Float(value) / 100
            case .amount: break
            }
        }
    }, openDisclosureLink: { _ in openWallpaper?() }, action: { action in
        switch action {
        case .photo: mediaPicker.choose(video: false)
        case .video: mediaPicker.choose(video: true)
        case .wallpaper: openWallpaper?()
        case .reset: AyuGramAppearance.shared.reset(scope: scope)
        case .particleKind:
            kindsExpanded.set(!kindsExpandedValue)
        case let .selectKind(kind):
            AyuGramAppearance.shared.update { settings in
                if kind < 0 {
                    settings.seasonal = true
                } else {
                    settings.seasonal = false
                    settings.particleKind = kind
                }
            }
            kindsExpanded.set(false)
        case let .previewKind(kind):
            AyuGramEffectsView.shared?.preview(kind: kind < 0 ? AyuGramAppearanceSettings.seasonalParticleKind() : kind)
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, changes, kindsExpanded.get())
    |> deliverOnMainQueue
    |> map { data, _, expanded -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<AyuAppearanceToggle, AyuAppearanceSlider, AyuAppearanceUnused, AyuAppearanceAction, AyuAppearanceAction>)) in
        let settings = AyuGramAppearance.shared.effectiveSettings(for: scope)
        let locale = data.strings.baseLanguageCode
        var kindOptions: [AyuAppearanceEntry] = []
        var settingsEntries: [AyuAppearanceSettingEntry] = [
            .header(id: 0, section: .media, text: i18n(scope == .chatList ? "Ayu.ChatListBackground" : "Ayu.ConversationBackground", locale), badge: nil),
            .action(id: 1, section: .media, actionType: .photo, text: data.strings.Common_ChoosePhoto, kind: .generic),
            .action(id: 2, section: .media, actionType: .video, text: i18n("Ayu.ChooseVideo", locale), kind: .generic),
            .toggle(id: 3, section: .visibility, settingName: .enabled, value: scope == .chatList ? settings.chatList : settings.conversations, text: i18n("Ayu.ShowBackground", locale), enabled: true),
            .toggle(id: 4, section: .visibility, settingName: .motion, value: settings.animateVideo, text: data.strings.WallpaperPreview_Motion, enabled: settings.isVideo),
            .header(id: 5, section: .dim, text: i18n("Ayu.BackgroundDimming", locale), badge: nil),
            .rangedPercentageSlider(id: 6, section: .dim, settingName: .dim, value: Int32((settings.dim * 100).rounded()), minimum: 20, maximum: 90),
            .header(id: 7, section: .blur, text: data.strings.WallpaperPreview_Blurred, badge: nil),
            .rangedPercentageSlider(id: 8, section: .blur, settingName: .blur, value: Int32((settings.blur * 100).rounded()), minimum: 0, maximum: 100)
        ]
        if scope == .chatList {
            settingsEntries += [
                .header(id: 9, section: .rows, text: i18n("Ayu.RowOpacity", locale), badge: nil),
                .rangedPercentageSlider(id: 10, section: .rows, settingName: .rows, value: Int32((settings.rowOpacity * 100).rounded()), minimum: 35, maximum: 100)
            ]
            let stored = AyuGramAppearance.shared.settings
            let effects = stored.effects
            let kindKeys = ["Ayu.ParticlesSnow", "Ayu.ParticlesFlakes", "Ayu.ParticlesSakura", "Ayu.ParticlesStars", "Ayu.ParticlesLeaves", "Ayu.ParticlesRain"]
            let selectedKind: Int32 = stored.seasonal == true ? -1 : min(Int32(kindKeys.count - 1), max(0, stored.particleKind ?? 1))
            let kindName = selectedKind < 0 ? i18n("Ayu.ParticlesSeasonal", locale) : i18n(kindKeys[Int(selectedKind)], locale)
            settingsEntries += [
                .header(id: 11, section: .newYear, text: i18n("Ayu.NewYearHeader", locale), badge: nil),
                .toggle(id: 12, section: .newYear, settingName: .newYear, value: stored.newYear == true, text: i18n("Ayu.NewYearMode", locale), enabled: true),
                .toggle(id: 13, section: .newYear, settingName: .newYearAuto, value: stored.newYearAuto == true, text: i18n("Ayu.NewYearAuto", locale), enabled: true),
                .notice(id: 14, section: .newYear, text: i18n("Ayu.NewYearInfo", locale)),
                .header(id: 15, section: .effects, text: i18n("Ayu.EffectsHeader", locale), badge: nil),
                .toggle(id: 16, section: .effects, settingName: .particles, value: effects.particles, text: i18n("Ayu.Particles", locale), enabled: !effects.newYear),
                .action(id: 17, section: .effects, actionType: .particleKind, text: i18n("Ayu.ParticlesKind", locale) + ": " + kindName + (expanded ? "  ▴" : "  ▾"), kind: .generic),
                .toggle(id: 40, section: .effects, settingName: .drift, value: effects.drift, text: i18n("Ayu.SnowDrift", locale), enabled: !effects.newYear),
                .toggle(id: 41, section: .effects, settingName: .fireworks, value: effects.fireworks, text: i18n("Ayu.Fireworks", locale), enabled: !effects.newYear),
                .toggle(id: 42, section: .effects, settingName: .parallax, value: stored.parallax == true, text: i18n("Ayu.Parallax", locale), enabled: true),
                .notice(id: 43, section: .effects, text: i18n("Ayu.EffectsInfo", locale)),
                .header(id: 44, section: .amount, text: i18n("Ayu.ParticlesAmount", locale), badge: nil),
                .rangedPercentageSlider(id: 45, section: .amount, settingName: .amount, value: Int32((effects.amount * 100).rounded()), minimum: 10, maximum: 100),
                .disclosure(id: 50, section: .reset, link: .wallpaper, text: i18n("Ayu.ConversationBackground", locale))
            ]
            if expanded {
                let options: [(Int32, String)] = [(1, "Ayu.ParticlesFlakes"), (0, "Ayu.ParticlesSnow"), (2, "Ayu.ParticlesSakura"), (3, "Ayu.ParticlesStars"), (4, "Ayu.ParticlesLeaves"), (5, "Ayu.ParticlesRain"), (-1, "Ayu.ParticlesSeasonal")]
                for (index, option) in options.enumerated() {
                    kindOptions.append(.kindOption(19 + index, option.0, i18n(option.1, locale), option.0 == selectedKind))
                }
                settingsEntries.append(.notice(id: 26, section: .effects, text: i18n("Ayu.ParticlesHoldHint", locale)))
            }
        }
        settingsEntries.append(.action(id: 51, section: .reset, actionType: .reset, text: data.strings.AutoDownloadSettings_Reset, kind: .destructive))
        let entries: [AyuAppearanceEntry] = ([.preview(scope, settings)] + settingsEntries.map(AyuAppearanceEntry.setting) + kindOptions).sorted(by: { $0.stableId < $1.stableId })
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(scope == .chatList ? data.strings.Appearance_Title : data.strings.Wallpaper_Title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    mediaPicker.controller = controller
    openWallpaper = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(ayuGramAppearanceController(context: context, scope: .conversation))
    }
    return controller
}

private final class AyuGramAppearanceMediaPicker: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let context: AccountContext
    private let scope: AyuGramAppearanceScope
    weak var controller: UIViewController?
    private var pickingVideo = false
    init(context: AccountContext, scope: AyuGramAppearanceScope) {
        self.context = context
        self.scope = scope
        super.init()
    }
    private var strings: PresentationStrings { context.sharedContext.currentPresentationData.with { $0 }.strings }
    func choose(video: Bool) {
        pickingVideo = video
        if #available(iOS 14.0, *) {
            chooseModern(video: video)
        } else {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.mediaTypes = [video ? "public.movie" : "public.image"]
            picker.delegate = self
            controller?.present(picker, animated: true)
        }
    }
    @available(iOS 14.0, *)
    private func chooseModern(video: Bool) {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = video ? .videos : .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        controller?.present(picker, animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        do {
            if let url = info[pickingVideo ? .mediaURL : .imageURL] as? URL {
                try AyuGramAppearance.shared.importMedia(url, isVideo: pickingVideo, scope: scope)
            } else if !pickingVideo, let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try data.write(to: temporary, options: .atomic)
                try AyuGramAppearance.shared.importMedia(temporary, isVideo: false, scope: scope)
            } else {
                throw CocoaError(.fileReadCorruptFile)
            }
        } catch {
            showImportError()
        }
    }
    private func showImportError() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = UIAlertController(title: nil, message: i18n("Ayu.MediaImportError", self.strings.baseLanguageCode), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: self.strings.Common_OK, style: .default))
            self.controller?.present(alert, animated: true)
        }
    }
}

@available(iOS 14.0, *)
extension AyuGramAppearanceMediaPicker: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let video = pickingVideo
        let scope = self.scope
        provider.loadFileRepresentation(forTypeIdentifier: video ? "public.movie" : "public.image") { [weak self] url, error in
            do {
                guard error == nil, let url else { throw CocoaError(.fileReadCorruptFile) }
                try AyuGramAppearance.shared.importMedia(url, isVideo: video, scope: scope)
            } catch {
                self?.showImportError()
            }
        }
    }
}
