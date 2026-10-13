import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGItemListUI
import SGSimpleSettings
import SGStrings

private enum AyuScreenSection: Int32 {
    case hero, ghost, hide, behavior, content, history, client, update, support
}

private enum AyuScreenToggle: Equatable {
    case ghost, read, online, typing, recording, uploading, stories
    case offlineAfterSending, readOnSend, quickToggle
    case ignoreProtection, screenshots
    case history, premium
}

private enum AyuScreenLink: Equatable {
    case history, appearance, update, checkUpdates, channel, developer
}

private enum AyuScreenTint: Equatable {
    case purple, indigo, blue, teal, green, orange, red, pink, gray

    var color: UIColor {
        switch self {
        case .purple: return AyuGramRowColor.purple
        case .indigo: return AyuGramRowColor.indigo
        case .blue: return AyuGramRowColor.blue
        case .teal: return AyuGramRowColor.teal
        case .green: return AyuGramRowColor.green
        case .orange: return AyuGramRowColor.orange
        case .red: return AyuGramRowColor.red
        case .pink: return AyuGramRowColor.pink
        case .gray: return AyuGramRowColor.gray
        }
    }
}

private final class AyuScreenArguments {
    let toggle: (AyuScreenToggle, Bool) -> Void
    let updatePins: (Int32) -> Void
    let open: (AyuScreenLink) -> Void

    init(toggle: @escaping (AyuScreenToggle, Bool) -> Void, updatePins: @escaping (Int32) -> Void, open: @escaping (AyuScreenLink) -> Void) {
        self.toggle = toggle
        self.updatePins = updatePins
        self.open = open
    }
}

private enum AyuScreenEntry: ItemListNodeEntry {
    case hero(id: Int, title: String, status: String, detail: String, active: Bool)
    case header(id: Int, section: AyuScreenSection, text: String)
    case toggle(id: Int, section: AyuScreenSection, key: AyuScreenToggle, symbol: String, tint: AyuScreenTint, title: String, subtitle: String?, value: Bool, enabled: Bool)
    case link(id: Int, section: AyuScreenSection, link: AyuScreenLink, symbol: String, tint: AyuScreenTint, title: String)
    case pins(id: Int, section: AyuScreenSection, value: Int32)
    case footer(id: Int, section: AyuScreenSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case .hero:
            return AyuScreenSection.hero.rawValue
        case let .header(_, section, _), let .footer(_, section, _), let .pins(_, section, _):
            return section.rawValue
        case let .toggle(_, section, _, _, _, _, _, _, _):
            return section.rawValue
        case let .link(_, section, _, _, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .hero(id, _, _, _, _), let .header(id, _, _), let .footer(id, _, _), let .pins(id, _, _):
            return id
        case let .toggle(id, _, _, _, _, _, _, _, _):
            return id
        case let .link(id, _, _, _, _, _):
            return id
        }
    }

    static func <(lhs: AyuScreenEntry, rhs: AyuScreenEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuScreenArguments
        switch self {
        case let .hero(_, title, status, detail, active):
            return AyuGramSettingsHeroItem(data: presentationData, title: title, status: status, detail: detail, isActive: active, sectionId: self.section)
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, _, key, symbol, tint, title, subtitle, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: tint.color), title: title, text: subtitle, value: value, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .link(_, _, link, symbol, tint, title):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: tint.color), title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.open(link)
            })
        case let .pins(_, _, value):
            return AyuPinnedCountSliderItem(theme: presentationData.theme, strings: presentationData.strings, value: value, sectionId: self.section, updated: { value in
                arguments.updatePins(value)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func ayuScreenEntries(data: PresentationData, privacy: AyuGramPrivacySettings, extra: AyuGramExtraSettings, client: AyuGramClientSettings, hasAppearance: Bool, update: AyuGramUpdateInfo?) -> [AyuScreenEntry] {
    let locale = data.strings.baseLanguageCode
    func s(_ key: String) -> String {
        return i18n(key, locale)
    }
    let hidden = [privacy.suppressRead, privacy.suppressOnline, privacy.suppressTyping, privacy.suppressRecording, privacy.suppressUploading, privacy.suppressStoryViews]
    let hiddenCount = hidden.filter { $0 }.count
    let ghost = privacy.ghostMode
    var entries: [AyuScreenEntry] = []

    entries.append(.hero(id: 0, title: "AyuGram", status: s(ghost ? "Ayu.HeroGhostOn" : "Ayu.HeroGhostOff"), detail: i18n("Ayu.HeroHidden", locale, "\(hiddenCount)", "\(hidden.count)"), active: ghost || hiddenCount > 0))
    if let update {
        entries.append(.link(id: 5, section: .update, link: .update, symbol: "arrow.down.circle.fill", tint: .green, title: s("Ayu.UpdateAvailable") + " · " + update.version))
    }

    entries.append(.header(id: 10, section: .ghost, text: s("Ayu.Ghost")))
    entries.append(.toggle(id: 11, section: .ghost, key: .ghost, symbol: "eye.slash.fill", tint: .purple, title: s("Ayu.Ghost"), subtitle: s("Ayu.GhostSubtitle"), value: ghost, enabled: true))
    entries.append(.footer(id: 12, section: .ghost, text: s("Ayu.GhostFooter")))

    entries.append(.header(id: 20, section: .hide, text: s("Ayu.HideSection")))
    entries.append(.toggle(id: 21, section: .hide, key: .read, symbol: "checkmark.circle.fill", tint: .blue, title: s("Ayu.HideRead"), subtitle: nil, value: privacy.suppressRead, enabled: !ghost))
    entries.append(.toggle(id: 22, section: .hide, key: .online, symbol: "wifi.slash", tint: .green, title: s("Ayu.HideOnline"), subtitle: nil, value: privacy.suppressOnline, enabled: !ghost))
    entries.append(.toggle(id: 23, section: .hide, key: .typing, symbol: "keyboard", tint: .teal, title: s("Ayu.HideTyping"), subtitle: nil, value: privacy.suppressTyping, enabled: !ghost))
    entries.append(.toggle(id: 24, section: .hide, key: .recording, symbol: "mic.slash.fill", tint: .red, title: s("Ayu.HideRecording"), subtitle: nil, value: privacy.suppressRecording, enabled: !ghost))
    entries.append(.toggle(id: 25, section: .hide, key: .uploading, symbol: "icloud.and.arrow.up.fill", tint: .indigo, title: s("Ayu.HideUploading"), subtitle: nil, value: privacy.suppressUploading, enabled: !ghost))
    entries.append(.toggle(id: 26, section: .hide, key: .stories, symbol: "camera.circle.fill", tint: .pink, title: s("Ayu.HideStories"), subtitle: nil, value: privacy.suppressStoryViews, enabled: !ghost))

    entries.append(.header(id: 30, section: .behavior, text: s("Ayu.BehaviorSection")))
    entries.append(.toggle(id: 31, section: .behavior, key: .offlineAfterSending, symbol: "moon.fill", tint: .indigo, title: s("Ayu.OfflineAfterSending"), subtitle: s("Ayu.OfflineAfterSendingInfo"), value: extra.offlineAfterSending, enabled: true))
    entries.append(.toggle(id: 32, section: .behavior, key: .readOnSend, symbol: "arrowshape.turn.up.left.fill", tint: .blue, title: s("Ayu.ReadOnSend"), subtitle: s("Ayu.ReadOnSendInfo"), value: extra.readOnSend, enabled: true))
    entries.append(.toggle(id: 33, section: .behavior, key: .quickToggle, symbol: "hand.tap.fill", tint: .orange, title: s("Ayu.QuickToggle"), subtitle: nil, value: extra.ghostQuickToggle, enabled: true))
    entries.append(.footer(id: 34, section: .behavior, text: s("Ayu.QuickToggleInfo")))

    entries.append(.header(id: 40, section: .content, text: s("Ayu.ContentSection")))
    entries.append(.toggle(id: 41, section: .content, key: .ignoreProtection, symbol: "lock.open.fill", tint: .orange, title: s("Ayu.IgnoreProtection"), subtitle: s("Ayu.IgnoreProtectionInfo"), value: extra.ignoreCopyProtection, enabled: true))
    entries.append(.toggle(id: 42, section: .content, key: .screenshots, symbol: "camera.fill", tint: .gray, title: s("Ayu.AllowScreenshots"), subtitle: s("Ayu.AllowScreenshotsInfo"), value: extra.allowScreenshots, enabled: true))
    entries.append(.footer(id: 43, section: .content, text: s("Ayu.ContentFooter")))

    entries.append(.header(id: 50, section: .history, text: s("Ayu.History")))
    entries.append(.toggle(id: 51, section: .history, key: .history, symbol: "trash.fill", tint: .red, title: s("Ayu.SaveDeleted"), subtitle: s("Ayu.SaveDeletedInfo"), value: privacy.messageHistory, enabled: true))
    entries.append(.link(id: 52, section: .history, link: .history, symbol: "clock.fill", tint: .teal, title: s("Ayu.OpenHistory")))
    entries.append(.footer(id: 53, section: .history, text: s("Ayu.HistoryInfo")))

    entries.append(.header(id: 60, section: .client, text: s("Ayu.ClientSection")))
    entries.append(.toggle(id: 61, section: .client, key: .premium, symbol: "star.fill", tint: .purple, title: s("Ayu.LocalPremium"), subtitle: s("Ayu.LocalPremiumInfo"), value: client.localPremium, enabled: true))
    if hasAppearance {
        entries.append(.link(id: 62, section: .client, link: .appearance, symbol: "paintbrush.fill", tint: .pink, title: data.strings.Appearance_Title))
    }
    entries.append(.header(id: 63, section: .client, text: s("Ayu.Pins")))
    entries.append(.pins(id: 64, section: .client, value: client.pinnedChatLimit))
    entries.append(.footer(id: 65, section: .client, text: s("Ayu.LocalOnly")))

    entries.append(.header(id: 70, section: .support, text: s("Ayu.SupportSection")))
    entries.append(.link(id: 71, section: .support, link: .channel, symbol: "paperplane.fill", tint: .blue, title: s("Ayu.SupportChannel")))
    entries.append(.link(id: 72, section: .support, link: .developer, symbol: "person.crop.circle.fill", tint: .purple, title: s("Ayu.SupportDeveloper")))
    entries.append(.link(id: 73, section: .support, link: .checkUpdates, symbol: "arrow.triangle.2.circlepath", tint: .gray, title: s("Ayu.CheckUpdates")))
    return entries
}

/// Redesigned AyuGram settings: summary card, grouped Ghost Mode controls,
/// behaviour, content protection, history and client options with icons.
public func ayuGramSettingsScreen(context: AccountContext) -> ViewController {
    var pushController: ((ViewController) -> Void)?
    var presentController: ((ViewController) -> Void)?
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        let updateObserver = NotificationCenter.default.addObserver(forName: AyuGramUpdates.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
            NotificationCenter.default.removeObserver(updateObserver)
        }
    }
    let arguments = AyuScreenArguments(toggle: { key, value in
        let settings = AyuGramSettings.shared
        switch key {
        case .ghost: settings.update { $0.ghostMode = value }
        case .read: settings.update { $0.antiRead = value }
        case .online: settings.update { $0.antiOnline = value }
        case .typing: settings.update { $0.antiTyping = value }
        case .recording: settings.update { $0.antiRecording = value }
        case .uploading: settings.update { $0.antiUploading = value }
        case .stories: settings.update { $0.storyPrivacy = value }
        case .history: settings.update { $0.messageHistory = value }
        case .offlineAfterSending: settings.updateExtra { $0.offlineAfterSending = value }
        case .readOnSend: settings.updateExtra { $0.readOnSend = value }
        case .quickToggle: settings.updateExtra { $0.ghostQuickToggle = value }
        case .ignoreProtection: settings.updateExtra { $0.ignoreCopyProtection = value }
        case .screenshots: settings.updateExtra { $0.allowScreenshots = value }
        case .premium: settings.updateClient { $0.localPremium = value }
        }
    }, updatePins: { value in
        AyuGramSettings.shared.updateClient { $0.maxPinnedChats = value }
    }, open: { link in
        switch link {
        case .history:
            pushController?(ayuGramHistoryController(context: context))
        case .appearance:
            if let controller = ayuGramAppearanceEntryController(context: context) {
                pushController?(controller)
            }
        case .update:
            if let info = AyuGramUpdates.shared.availableUpdate {
                presentController?(ayuGramUpdateAlert(context: context, info: info))
            }
        case .checkUpdates:
            AyuGramUpdates.shared.check { info in
                if let info {
                    presentController?(ayuGramUpdateAlert(context: context, info: info))
                } else {
                    let data = context.sharedContext.currentPresentationData.with { $0 }
                    presentController?(textAlertController(context: context, title: nil, text: i18n("Ayu.UpToDate", data.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
                }
            }
        case .channel:
            ayuGramOpenLink(context: context, url: AyuGramUpdates.channelURL)
        case .developer:
            ayuGramOpenDeveloper(context: context)
        }
    })
    let hasAppearance = ayuGramHasAppearanceEntry
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, AyuScreenArguments)) in
        let settings = AyuGramSettings.shared
        let entries = ayuScreenEntries(data: data, privacy: settings.snapshot, extra: settings.extra, client: settings.client, hasAppearance: hasAppearance, update: AyuGramUpdates.shared.availableUpdate)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, animateChanges: true)
        return (state, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    pushController = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    presentController = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    return controller
}
