import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGItemListUI
import SGSimpleSettings
import SGStrings

private enum AyuVideoSection: Int32 {
    case round, roundExperimental, video
}

private enum AyuVideoToggle: Equatable {
    case roundFromGallery, roundHEVC, roundLargeAs640, bestQuality, highBitrate
}

private enum AyuVideoPicker: Equatable {
    case roundQuality, roundFrameRate, roundBitrate
}

private final class AyuVideoArguments {
    let toggle: (AyuVideoToggle, Bool) -> Void
    let pick: (AyuVideoPicker) -> Void

    init(toggle: @escaping (AyuVideoToggle, Bool) -> Void, pick: @escaping (AyuVideoPicker) -> Void) {
        self.toggle = toggle
        self.pick = pick
    }
}

private enum AyuVideoEntry: ItemListNodeEntry {
    case header(id: Int, section: AyuVideoSection, text: String)
    case toggle(id: Int, section: AyuVideoSection, key: AyuVideoToggle, symbol: String, color: UIColor, title: String, subtitle: String?, value: Bool)
    case picker(id: Int, section: AyuVideoSection, key: AyuVideoPicker, symbol: String, color: UIColor, title: String, label: String)
    case footer(id: Int, section: AyuVideoSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .footer(_, section, _):
            return section.rawValue
        case let .toggle(_, section, _, _, _, _, _, _):
            return section.rawValue
        case let .picker(_, section, _, _, _, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _), let .footer(id, _, _):
            return id
        case let .toggle(id, _, _, _, _, _, _, _):
            return id
        case let .picker(id, _, _, _, _, _, _):
            return id
        }
    }

    static func ==(lhs: AyuVideoEntry, rhs: AyuVideoEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lid, _, ltext), .header(rid, _, rtext)), let (.footer(lid, _, ltext), .footer(rid, _, rtext)):
            return lid == rid && ltext == rtext
        case let (.toggle(lid, _, _, _, _, ltitle, lsubtitle, lvalue), .toggle(rid, _, _, _, _, rtitle, rsubtitle, rvalue)):
            return lid == rid && ltitle == rtitle && lsubtitle == rsubtitle && lvalue == rvalue
        case let (.picker(lid, _, _, _, _, ltitle, llabel), .picker(rid, _, _, _, _, rtitle, rlabel)):
            return lid == rid && ltitle == rtitle && llabel == rlabel
        default:
            return false
        }
    }

    static func <(lhs: AyuVideoEntry, rhs: AyuVideoEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuVideoArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, _, key, symbol, color, title, subtitle, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: color), title: title, text: subtitle, value: value, enabled: true, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .picker(_, _, key, symbol, color, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: color), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.pick(key)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func ayuVideoQualityTitle(_ index: Int32, locale: String) -> String {
    switch index {
    case 1:
        return i18n("Ayu.Video.RoundMax", locale)
    case 2:
        return i18n("Ayu.Video.Round720", locale)
    case 3:
        return i18n("Ayu.Video.Round1080", locale)
    default:
        return i18n("Ayu.Video.RoundStandard", locale)
    }
}

private func ayuVideoBitrateTitle(_ value: Int32, locale: String) -> String {
    if value <= 0 {
        return i18n("Ayu.Video.RoundBitrateAuto", locale)
    }
    return "\(value) " + i18n("Ayu.Video.RoundBitrateUnit", locale)
}

private func ayuVideoFrameRateTitle(_ value: Int32) -> String {
    return "\(value) fps"
}

private func ayuVideoEntries(data: PresentationData, video: AyuGramVideoSettings) -> [AyuVideoEntry] {
    let locale = data.strings.baseLanguageCode
    func s(_ key: String) -> String {
        return i18n(key, locale)
    }
    var entries: [AyuVideoEntry] = []
    entries.append(.header(id: 10, section: .round, text: s("Ayu.Video.RoundSection")))
    entries.append(.picker(id: 20, section: .round, key: .roundQuality, symbol: "circle.circle.fill", color: AyuGramRowColor.purple, title: s("Ayu.Video.RoundQuality"), label: ayuVideoQualityTitle(video.roundQualityIndex, locale: locale)))
    entries.append(.picker(id: 30, section: .round, key: .roundFrameRate, symbol: "speedometer", color: AyuGramRowColor.orange, title: s("Ayu.Video.RoundFrameRate"), label: ayuVideoFrameRateTitle(Int32(video.roundFps))))
    entries.append(.picker(id: 32, section: .round, key: .roundBitrate, symbol: "gauge", color: AyuGramRowColor.red, title: s("Ayu.Video.RoundBitrate"), label: ayuVideoBitrateTitle(video.roundBitrateOverride == nil ? 0 : video.roundBitrateMbps, locale: locale)))
    entries.append(.toggle(id: 34, section: .round, key: .roundHEVC, symbol: "cpu", color: AyuGramRowColor.indigo, title: s("Ayu.Video.RoundHEVC"), subtitle: s("Ayu.Video.RoundHEVCInfo"), value: video.roundHEVC))
    entries.append(.toggle(id: 40, section: .round, key: .roundFromGallery, symbol: "photo.on.rectangle.angled", color: AyuGramRowColor.blue, title: s("Ayu.Video.RoundFromGallery"), subtitle: s("Ayu.Video.RoundFromGalleryInfo"), value: video.roundFromGallery))
    entries.append(.footer(id: 50, section: .round, text: s("Ayu.Video.RoundFooter")))

    entries.append(.header(id: 60, section: .roundExperimental, text: s("Ayu.Video.RoundExperimentalSection")))
    entries.append(.toggle(id: 70, section: .roundExperimental, key: .roundLargeAs640, symbol: "exclamationmark.triangle.fill", color: AyuGramRowColor.gray, title: s("Ayu.Video.RoundLargeAs640"), subtitle: s("Ayu.Video.RoundLargeAs640Info"), value: video.roundLargeAs640))
    entries.append(.footer(id: 80, section: .roundExperimental, text: s("Ayu.Video.RoundExperimentalFooter")))

    entries.append(.header(id: 100, section: .video, text: s("Ayu.Video.VideoSection")))
    entries.append(.toggle(id: 110, section: .video, key: .bestQuality, symbol: "film.fill", color: AyuGramRowColor.teal, title: s("Ayu.Video.BestQuality"), subtitle: s("Ayu.Video.BestQualityInfo"), value: video.videoBestQuality))
    entries.append(.toggle(id: 120, section: .video, key: .highBitrate, symbol: "waveform.path.ecg", color: AyuGramRowColor.green, title: s("Ayu.Video.HighBitrate"), subtitle: s("Ayu.Video.HighBitrateInfo"), value: video.videoHighBitrate))
    entries.append(.footer(id: 130, section: .video, text: s("Ayu.Video.VideoFooter")))
    return entries
}

public func ayuGramVideoSettingsController(context: AccountContext) -> ViewController {
    var presentController: ((ViewController) -> Void)?
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let arguments = AyuVideoArguments(toggle: { key, value in
        AyuGramSettings.shared.updateVideo { video in
            switch key {
            case .roundFromGallery:
                video.roundFromGallery = value
            case .roundHEVC:
                video.roundHEVC = value
            case .roundLargeAs640:
                video.roundLargeAs640 = value
                if !value {
                    video.roundQuality = video.roundQualityIndex
                }
            case .bestQuality:
                video.videoBestQuality = value
                if value {
                    UserDefaults.standard.set(NSNumber(value: 5), forKey: "TG_preferredVideoPreset_v0")
                }
            case .highBitrate:
                video.videoHighBitrate = value
            }
        }
    }, pick: { key in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        let video = AyuGramSettings.shared.video
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = []
        switch key {
        case .roundQuality:
            for index in 0 ..< Int32(video.roundAvailableQualityCount) {
                items.append(ActionSheetButtonItem(title: (index == video.roundQualityIndex ? "✓ " : "") + ayuVideoQualityTitle(index, locale: locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    AyuGramSettings.shared.updateVideo { $0.roundQuality = index }
                }))
            }
        case .roundFrameRate:
            for value in AyuGramVideoSettings.roundFrameRates {
                items.append(ActionSheetButtonItem(title: (Double(value) == video.roundFps ? "✓ " : "") + ayuVideoFrameRateTitle(value), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    AyuGramSettings.shared.updateVideo { $0.roundFrameRate = value }
                }))
            }
        case .roundBitrate:
            let current: Int32 = video.roundBitrateOverride == nil ? 0 : video.roundBitrateMbps
            for value in AyuGramVideoSettings.roundBitrateChoices {
                items.append(ActionSheetButtonItem(title: (value == current ? "✓ " : "") + ayuVideoBitrateTitle(value, locale: locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    AyuGramSettings.shared.updateVideo { $0.roundBitrateMbps = value }
                }))
            }
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        presentController?(sheet)
    })
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, AyuVideoArguments)) in
        let entries = ayuVideoEntries(data: data, video: AyuGramSettings.shared.video)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(i18n("Ayu.Video.Title", data.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, animateChanges: true)
        return (state, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentController = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    return controller
}
