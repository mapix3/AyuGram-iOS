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

private enum AyuAppearanceSection: Int32, SGItemListSection { case preview, media, visibility, dim, blur, rows, reset }
private enum AyuAppearanceToggle: Hashable { case enabled, motion }
private enum AyuAppearanceSlider: Hashable { case dim, blur, rows }
private enum AyuAppearanceAction: Hashable { case photo, video, wallpaper, reset }
private enum AyuAppearanceUnused: Hashable { case unused }
private typealias AyuAppearanceSettingEntry = SGItemListUIEntry<AyuAppearanceSection, AyuAppearanceToggle, AyuAppearanceSlider, AyuAppearanceUnused, AyuAppearanceAction, AyuAppearanceAction>
private enum AyuAppearanceEntry: ItemListNodeEntry {
    case preview(AyuGramAppearanceScope, AyuGramAppearanceSettings)
    case setting(AyuAppearanceSettingEntry)
    var section: ItemListSectionId {
        switch self { case .preview: return AyuAppearanceSection.preview.rawValue; case let .setting(value): return value.section }
    }
    var stableId: Int {
        switch self { case .preview: return 0; case let .setting(value): return value.stableId + 1 }
    }
    static func < (lhs: AyuAppearanceEntry, rhs: AyuAppearanceEntry) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .preview(scope, settings): return AyuGramAppearancePreviewItem(data: presentationData, scope: scope, settings: settings, sectionId: section)
        case let .setting(value): return value.item(presentationData: presentationData, arguments: arguments)
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
    let arguments = SGItemListArguments<AyuAppearanceToggle, AyuAppearanceSlider, AyuAppearanceUnused, AyuAppearanceAction, AyuAppearanceAction>(context: context, setBoolValue: { key, value in
        AyuGramAppearance.shared.updateForScope(scope) { settings in
            switch key {
            case .enabled:
                if scope == .chatList { settings.chatList = value } else { settings.conversations = value }
            case .motion: settings.animateVideo = value
            }
        }
    }, updateSliderValue: { key, value in
        AyuGramAppearance.shared.updateForScope(scope) { settings in
            switch key {
            case .dim: settings.dim = Float(value) / 100
            case .blur: settings.blur = Float(value) / 100
            case .rows: settings.rowOpacity = Float(value) / 100
            }
        }
    }, openDisclosureLink: { _ in openWallpaper?() }, action: { action in
        switch action {
        case .photo: mediaPicker.choose(video: false)
        case .video: mediaPicker.choose(video: true)
        case .wallpaper: openWallpaper?()
        case .reset: AyuGramAppearance.shared.reset(scope: scope)
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<AyuAppearanceToggle, AyuAppearanceSlider, AyuAppearanceUnused, AyuAppearanceAction, AyuAppearanceAction>)) in
        let settings = AyuGramAppearance.shared.effectiveSettings(for: scope)
        let locale = data.strings.baseLanguageCode
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
                .rangedPercentageSlider(id: 10, section: .rows, settingName: .rows, value: Int32((settings.rowOpacity * 100).rounded()), minimum: 35, maximum: 100),
                .disclosure(id: 11, section: .reset, link: .wallpaper, text: i18n("Ayu.ConversationBackground", locale))
            ]
        }
        settingsEntries.append(.action(id: 12, section: .reset, actionType: .reset, text: data.strings.AutoDownloadSettings_Reset, kind: .destructive))
        let entries: [AyuAppearanceEntry] = [.preview(scope, settings)] + settingsEntries.map(AyuAppearanceEntry.setting)
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
