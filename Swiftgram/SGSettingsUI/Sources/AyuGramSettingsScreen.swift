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
    case hero, ghost, hide, behavior, content, chats, history, transfer, client, update, notifications, support
}

private enum AyuScreenToggle: Equatable {
    case ghost, read, online, typing, recording, uploading, stories
    case offlineAfterSending, readOnSend, quickToggle
    case ignoreProtection, screenshots
    case history, premium
    case scheduleInGhost, disableAds, disableLinkWarning, disableGreeting, dimDeleted, repeatMessage, confirmStickers, confirmGifs
}

private enum AyuScreenLink: Equatable {
    case history, appearance, update, checkUpdates, channel, developer, bark, importChat, silentSending
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
    case link(id: Int, section: AyuScreenSection, link: AyuScreenLink, symbol: String, tint: AyuScreenTint, title: String, label: String)
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
        case let .link(_, section, _, _, _, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .hero(id, _, _, _, _), let .header(id, _, _), let .footer(id, _, _), let .pins(id, _, _):
            return id
        case let .toggle(id, _, _, _, _, _, _, _, _):
            return id
        case let .link(id, _, _, _, _, _, _):
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
        case let .link(_, _, link, symbol, tint, title, label):
            let icon = (link == .channel ? ayuGramRowImage("AyuUpdatesChannel") : nil) ?? ayuGramRowIcon(symbol, color: tint.color)
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: label, sectionId: self.section, style: .blocks, action: {
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
        entries.append(.link(id: 50, section: .update, link: .update, symbol: "arrow.down.circle.fill", tint: .green, title: s("Ayu.UpdateAvailable") + " · " + update.version, label: ""))
    }

    entries.append(.header(id: 100, section: .ghost, text: s("Ayu.Ghost")))
    entries.append(.toggle(id: 110, section: .ghost, key: .ghost, symbol: "eye.slash.fill", tint: .purple, title: s("Ayu.Ghost"), subtitle: s("Ayu.GhostSubtitle"), value: ghost, enabled: true))
    entries.append(.footer(id: 120, section: .ghost, text: s("Ayu.GhostFooter")))

    entries.append(.header(id: 200, section: .hide, text: s("Ayu.HideSection")))
    entries.append(.toggle(id: 210, section: .hide, key: .read, symbol: "checkmark.circle.fill", tint: .blue, title: s("Ayu.HideRead"), subtitle: nil, value: privacy.suppressRead, enabled: !ghost))
    entries.append(.toggle(id: 220, section: .hide, key: .online, symbol: "wifi.slash", tint: .green, title: s("Ayu.HideOnline"), subtitle: nil, value: privacy.suppressOnline, enabled: !ghost))
    entries.append(.toggle(id: 230, section: .hide, key: .typing, symbol: "keyboard", tint: .teal, title: s("Ayu.HideTyping"), subtitle: nil, value: privacy.suppressTyping, enabled: !ghost))
    entries.append(.toggle(id: 240, section: .hide, key: .recording, symbol: "mic.slash.fill", tint: .red, title: s("Ayu.HideRecording"), subtitle: nil, value: privacy.suppressRecording, enabled: !ghost))
    entries.append(.toggle(id: 250, section: .hide, key: .uploading, symbol: "icloud.and.arrow.up.fill", tint: .indigo, title: s("Ayu.HideUploading"), subtitle: nil, value: privacy.suppressUploading, enabled: !ghost))
    entries.append(.toggle(id: 260, section: .hide, key: .stories, symbol: "camera.circle.fill", tint: .pink, title: s("Ayu.HideStories"), subtitle: nil, value: privacy.suppressStoryViews, enabled: !ghost))

    entries.append(.header(id: 300, section: .behavior, text: s("Ayu.BehaviorSection")))
    entries.append(.toggle(id: 310, section: .behavior, key: .offlineAfterSending, symbol: "moon.fill", tint: .indigo, title: s("Ayu.OfflineAfterSending"), subtitle: s("Ayu.OfflineAfterSendingInfo"), value: extra.offlineAfterSending, enabled: true))
    entries.append(.toggle(id: 320, section: .behavior, key: .readOnSend, symbol: "arrowshape.turn.up.left.fill", tint: .blue, title: s("Ayu.ReadOnSend"), subtitle: s("Ayu.ReadOnSendInfo"), value: extra.readOnSend, enabled: true))
    entries.append(.toggle(id: 330, section: .behavior, key: .quickToggle, symbol: "hand.tap.fill", tint: .orange, title: s("Ayu.QuickToggle"), subtitle: nil, value: extra.ghostQuickToggle, enabled: true))
    entries.append(.footer(id: 340, section: .behavior, text: s("Ayu.QuickToggleInfo")))
    let silentLabels = ["Ayu.SilentNever", "Ayu.SilentInGhost", "Ayu.SilentAlways"]
    entries.append(.link(id: 350, section: .behavior, link: .silentSending, symbol: "bell.slash.fill", tint: .gray, title: s("Ayu.SilentSending"), label: s(silentLabels[Int(max(0, min(2, extra.silentSending)))])))
    entries.append(.toggle(id: 360, section: .behavior, key: .scheduleInGhost, symbol: "clock.badge.checkmark.fill", tint: .teal, title: s("Ayu.ScheduleInGhost"), subtitle: s("Ayu.ScheduleInGhostInfo"), value: extra.scheduleInGhost, enabled: true))

    entries.append(.header(id: 400, section: .content, text: s("Ayu.ContentSection")))
    entries.append(.toggle(id: 410, section: .content, key: .ignoreProtection, symbol: "lock.open.fill", tint: .orange, title: s("Ayu.IgnoreProtection"), subtitle: s("Ayu.IgnoreProtectionInfo"), value: extra.ignoreCopyProtection, enabled: true))
    entries.append(.toggle(id: 420, section: .content, key: .screenshots, symbol: "camera.fill", tint: .gray, title: s("Ayu.AllowScreenshots"), subtitle: s("Ayu.AllowScreenshotsInfo"), value: extra.allowScreenshots, enabled: true))
    entries.append(.footer(id: 430, section: .content, text: s("Ayu.ContentFooter")))

    entries.append(.header(id: 431, section: .chats, text: s("Ayu.ChatsSection")))
    entries.append(.toggle(id: 432, section: .chats, key: .disableAds, symbol: "megaphone.fill", tint: .orange, title: s("Ayu.DisableAds"), subtitle: nil, value: extra.disableAds, enabled: true))
    entries.append(.toggle(id: 433, section: .chats, key: .disableLinkWarning, symbol: "link", tint: .blue, title: s("Ayu.DisableLinkWarning"), subtitle: nil, value: extra.disableLinkWarning, enabled: true))
    entries.append(.toggle(id: 434, section: .chats, key: .disableGreeting, symbol: "hand.wave.fill", tint: .green, title: s("Ayu.DisableGreeting"), subtitle: nil, value: extra.disableGreetingSticker, enabled: true))
    entries.append(.toggle(id: 435, section: .chats, key: .dimDeleted, symbol: "circle.lefthalf.filled", tint: .red, title: s("Ayu.DimDeleted"), subtitle: nil, value: extra.dimDeletedMessages, enabled: true))
    entries.append(.toggle(id: 436, section: .chats, key: .repeatMessage, symbol: "arrow.2.squarepath", tint: .indigo, title: s("Ayu.RepeatMessage"), subtitle: nil, value: extra.repeatMessage, enabled: true))
    entries.append(.toggle(id: 437, section: .chats, key: .confirmStickers, symbol: "face.smiling.inverse", tint: .pink, title: s("Ayu.ConfirmStickers"), subtitle: nil, value: extra.confirmStickers, enabled: true))
    entries.append(.toggle(id: 438, section: .chats, key: .confirmGifs, symbol: "play.rectangle.fill", tint: .purple, title: s("Ayu.ConfirmGifs"), subtitle: nil, value: extra.confirmGifs, enabled: true))
    entries.append(.footer(id: 439, section: .chats, text: s("Ayu.LocalOnly")))

    entries.append(.header(id: 500, section: .history, text: s("Ayu.History")))
    entries.append(.toggle(id: 510, section: .history, key: .history, symbol: "trash.fill", tint: .red, title: s("Ayu.SaveDeleted"), subtitle: s("Ayu.SaveDeletedInfo"), value: privacy.messageHistory, enabled: true))
    entries.append(.link(id: 520, section: .history, link: .history, symbol: "clock.fill", tint: .teal, title: s("Ayu.OpenHistory"), label: ""))
    entries.append(.footer(id: 530, section: .history, text: s("Ayu.HistoryInfo")))

    entries.append(.header(id: 550, section: .transfer, text: s("Ayu.ChatTransferSection")))
    entries.append(.link(id: 560, section: .transfer, link: .importChat, symbol: "square.and.arrow.down.fill", tint: .green, title: s("Ayu.ImportChat"), label: ""))
    entries.append(.footer(id: 570, section: .transfer, text: s("Ayu.ImportChatFooter")))

    entries.append(.header(id: 600, section: .client, text: s("Ayu.ClientSection")))
    entries.append(.toggle(id: 610, section: .client, key: .premium, symbol: "star.fill", tint: .purple, title: s("Ayu.LocalPremium"), subtitle: s("Ayu.LocalPremiumInfo"), value: client.localPremium, enabled: true))
    if hasAppearance {
        entries.append(.link(id: 620, section: .client, link: .appearance, symbol: "paintbrush.fill", tint: .pink, title: data.strings.Appearance_Title, label: ""))
    }
    entries.append(.header(id: 630, section: .client, text: s("Ayu.Pins")))
    entries.append(.pins(id: 640, section: .client, value: client.pinnedChatLimit))
    entries.append(.footer(id: 650, section: .client, text: s("Ayu.LocalOnly")))

    let barkOn = !(AyuGramPushRelay.barkKey ?? "").isEmpty
    entries.append(.header(id: 660, section: .notifications, text: s("Ayu.NotificationsSection")))
    entries.append(.link(id: 670, section: .notifications, link: .bark, symbol: "bell.badge.fill", tint: .red, title: s(barkOn ? "Ayu.BarkConnected" : "Ayu.BarkSetUp"), label: ""))
    entries.append(.footer(id: 680, section: .notifications, text: s("Ayu.BarkFooter")))

    entries.append(.header(id: 700, section: .support, text: s("Ayu.SupportSection")))
    entries.append(.link(id: 710, section: .support, link: .channel, symbol: "paperplane.fill", tint: .blue, title: s("Ayu.SupportChannel"), label: ""))
    entries.append(.link(id: 720, section: .support, link: .developer, symbol: "person.crop.circle.fill", tint: .purple, title: s("Ayu.SupportDeveloper"), label: ""))
    entries.append(.link(id: 730, section: .support, link: .checkUpdates, symbol: "arrow.triangle.2.circlepath", tint: .gray, title: s("Ayu.CheckUpdates"), label: ""))
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
        case .scheduleInGhost: settings.updateExtra { $0.scheduleInGhost = value }
        case .disableAds: settings.updateExtra { $0.disableAds = value }
        case .disableLinkWarning: settings.updateExtra { $0.disableLinkWarning = value }
        case .disableGreeting: settings.updateExtra { $0.disableGreetingSticker = value }
        case .dimDeleted: settings.updateExtra { $0.dimDeletedMessages = value }
        case .repeatMessage: settings.updateExtra { $0.repeatMessage = value }
        case .confirmStickers: settings.updateExtra { $0.confirmStickers = value }
        case .confirmGifs: settings.updateExtra { $0.confirmGifs = value }
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
        case .bark:
            ayuGramSetUpBark(context: context, present: { controller in
                presentController?(controller)
            })
        case .importChat:
            ayuGramImportChat(context: context)
        case .silentSending:
            let data = context.sharedContext.currentPresentationData.with { $0 }
            let locale = data.strings.baseLanguageCode
            let sheet = ActionSheetController(presentationData: data)
            let current = AyuGramSettings.shared.extra.silentSending
            var items: [ActionSheetItem] = []
            for (index, key) in ["Ayu.SilentNever", "Ayu.SilentInGhost", "Ayu.SilentAlways"].enumerated() {
                let value = Int32(index)
                items.append(ActionSheetButtonItem(title: (value == current ? "✓ " : "") + i18n(key, locale), color: .accent, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    AyuGramSettings.shared.updateExtra { $0.silentSending = value }
                }))
            }
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            presentController?(sheet)
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
