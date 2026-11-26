import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import PromptUI
import UndoUI
import SGItemListUI
import SGSimpleSettings
import SGStrings

private enum AyuScreenSection: Int32 {
    case hero, ghost, hide, behavior, content, chats, history, transfer, video, client, update, security, support, assistant, donate
}

private enum AyuScreenToggle: Equatable {
    case ghost, read, online, typing, recording, uploading, stories
    case offlineAfterSending, readOnSend, quickToggle
    case ignoreProtection, screenshots
    case history, premium
    case scheduleInGhost, disableAds, disableLinkWarning, disableGreeting, dimDeleted, repeatMessage, confirmStickers, confirmGifs, confirmRead
    case anonymousStats, assistantBubble, disableLiquidGlass, chatCopilot, styleLearning
}

private enum AyuScreenLink: Equatable {
    case history, appearance, update, checkUpdates, channel, developer, importChat, silentSending, sessionLog, buildInfo, reportScam, searchEngine, assistant, aiProvider, aiKey, aiModel, donate, aiLanguage, aiPersona, aiStyle, larpStars, larpTon, plugins, supporter, video, profileExtras, deepLinks
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
    let open: (AyuScreenLink) -> Void

    init(toggle: @escaping (AyuScreenToggle, Bool) -> Void, open: @escaping (AyuScreenLink) -> Void) {
        self.toggle = toggle
        self.open = open
    }
}

private enum AyuScreenEntry: ItemListNodeEntry {
    case hero(id: Int, title: String, status: String, detail: String, active: Bool)
    case header(id: Int, section: AyuScreenSection, text: String)
    case toggle(id: Int, section: AyuScreenSection, key: AyuScreenToggle, symbol: String, tint: AyuScreenTint, title: String, subtitle: String?, value: Bool, enabled: Bool)
    case link(id: Int, section: AyuScreenSection, link: AyuScreenLink, symbol: String, tint: AyuScreenTint, title: String, label: String)
    case footer(id: Int, section: AyuScreenSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case .hero:
            return AyuScreenSection.hero.rawValue
        case let .header(_, section, _), let .footer(_, section, _):
            return section.rawValue
        case let .toggle(_, section, _, _, _, _, _, _, _):
            return section.rawValue
        case let .link(_, section, _, _, _, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .hero(id, _, _, _, _), let .header(id, _, _), let .footer(id, _, _):
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
    entries.append(.toggle(id: 370, section: .behavior, key: .confirmRead, symbol: "checkmark.bubble.fill", tint: .blue, title: s("Ayu.ConfirmReadReceipt"), subtitle: nil, value: extra.confirmReadReceipt, enabled: true))

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

    let ai = AyuGramAssistantConfig.current
    entries.append(.header(id: 440, section: .assistant, text: s("Ayu.AISection")))
    entries.append(.link(id: 441, section: .assistant, link: .searchEngine, symbol: "magnifyingglass", tint: .blue, title: s("Ayu.SearchEngine"), label: AyuGramSearchEngine.current.title))
    entries.append(.link(id: 442, section: .assistant, link: .assistant, symbol: "sparkles", tint: .purple, title: s("Ayu.Assistant"), label: ""))
    entries.append(.toggle(id: 447, section: .assistant, key: .assistantBubble, symbol: "bubble.left.and.bubble.right.fill", tint: .pink, title: s("Ayu.AIBubble"), subtitle: nil, value: extra.assistantBubble, enabled: true))
    entries.append(.toggle(id: 449, section: .assistant, key: .chatCopilot, symbol: "cloud.fill", tint: .blue, title: s("Ayu.CopilotToggle"), subtitle: nil, value: extra.chatCopilot, enabled: true))
    entries.append(.link(id: 443, section: .assistant, link: .aiProvider, symbol: "server.rack", tint: .teal, title: s("Ayu.AIProvider"), label: ai.provider.title))
    entries.append(.link(id: 444, section: .assistant, link: .aiKey, symbol: "key.fill", tint: .orange, title: s("Ayu.AIKey"), label: ai.key.isEmpty ? s("Ayu.AIKeyNone") : "••••"))
    entries.append(.link(id: 445, section: .assistant, link: .aiModel, symbol: "cpu", tint: .indigo, title: s("Ayu.AIModel"), label: ai.model))
    entries.append(.link(id: 446, section: .assistant, link: .aiLanguage, symbol: "globe", tint: .green, title: s("Ayu.AILanguage"), label: AyuGramAssistantPreferences.language.isEmpty ? s("Ayu.AILanguageAuto") : AyuGramAssistantPreferences.language))
    entries.append(.link(id: 450, section: .assistant, link: .aiPersona, symbol: "person.fill", tint: .purple, title: s("Ayu.AIPersona"), label: AyuGramAssistantPreferences.persona.isEmpty ? "" : "✓"))
    entries.append(.toggle(id: 451, section: .assistant, key: .styleLearning, symbol: "text.bubble.fill", tint: .orange, title: s("Ayu.AIStyleLearn"), subtitle: s("Ayu.AIStyleLearnInfo"), value: AyuGramStyleLearning.enabled, enabled: true))
    entries.append(.link(id: 452, section: .assistant, link: .aiStyle, symbol: "signature", tint: .pink, title: s("Ayu.AIStyle"), label: AyuGramStyleLearning.notes.isEmpty ? "\(AyuGramStyleLearning.samples.count)" : "✓"))
    entries.append(.footer(id: 448, section: .assistant, text: s("Ayu.AIFooter")))

    entries.append(.header(id: 500, section: .history, text: s("Ayu.History")))
    entries.append(.link(id: 520, section: .history, link: .history, symbol: "clock.fill", tint: .teal, title: s("Ayu.OpenHistory"), label: ""))
    entries.append(.footer(id: 530, section: .history, text: s("Ayu.HistoryInfo")))

    entries.append(.header(id: 550, section: .transfer, text: s("Ayu.ChatTransferSection")))
    entries.append(.link(id: 560, section: .transfer, link: .importChat, symbol: "square.and.arrow.down.fill", tint: .green, title: s("Ayu.ImportChat"), label: ""))
    entries.append(.footer(id: 570, section: .transfer, text: s("Ayu.ImportChatFooter")))

    entries.append(.header(id: 580, section: .video, text: s("Ayu.Video.Section")))
    entries.append(.link(id: 585, section: .video, link: .video, symbol: "video.fill", tint: .orange, title: s("Ayu.Video.Title"), label: ""))
    entries.append(.footer(id: 590, section: .video, text: s("Ayu.Video.SectionFooter")))

    entries.append(.header(id: 600, section: .client, text: s("Ayu.ClientSection")))
    entries.append(.link(id: 605, section: .client, link: .supporter, symbol: "heart.circle.fill", tint: .red, title: s("Ayu.SupporterBadge"), label: ""))
    entries.append(.toggle(id: 610, section: .client, key: .premium, symbol: "star.fill", tint: .purple, title: s("Ayu.LocalPremium"), subtitle: s("Ayu.LocalPremiumInfo"), value: client.localPremium, enabled: true))
    entries.append(.link(id: 612, section: .client, link: .larpStars, symbol: "star.circle.fill", tint: .orange, title: s("Ayu.LarpStars"), label: AyuGramLarpBalance.stars.map { "\($0)" } ?? s("Ayu.LarpOff")))
    entries.append(.link(id: 614, section: .client, link: .larpTon, symbol: "diamond.fill", tint: .blue, title: s("Ayu.LarpTon"), label: AyuGramLarpBalance.tonNano.map { AyuGramLarpBalance.formatTon($0) } ?? s("Ayu.LarpOff")))
    entries.append(.link(id: 616, section: .client, link: .plugins, symbol: "puzzlepiece.extension.fill", tint: .green, title: s("Ayu.Plugins.Title"), label: AyuGramPluginManager.shared.plugins.isEmpty ? "" : "\(AyuGramPluginManager.shared.plugins.filter { $0.enabled }.count)"))
    entries.append(.link(id: 617, section: .client, link: .profileExtras, symbol: "person.crop.circle.badge.plus", tint: .blue, title: s("Ayu.ProfileExtras.Title"), label: ""))
    if hasAppearance {
        entries.append(.link(id: 620, section: .client, link: .appearance, symbol: "paintbrush.fill", tint: .pink, title: data.strings.Appearance_Title, label: ""))
        entries.append(.toggle(id: 630, section: .client, key: .disableLiquidGlass, symbol: "drop.fill", tint: .teal, title: s("Ayu.DisableLiquidGlass"), subtitle: s("Ayu.DisableLiquidGlassInfo") + (extra.disableLiquidGlass != AyuLegacyUI.isEnabled ? "\n" + s("Ayu.RestartPending") : ""), value: extra.disableLiquidGlass, enabled: true))
    }
    entries.append(.footer(id: 650, section: .client, text: s("Ayu.LocalOnly")))

    let security = AyuGramSecurity.shared
    entries.append(.header(id: 690, section: .security, text: s("Ayu.SecuritySection")))
    entries.append(.link(id: 691, section: .security, link: .buildInfo, symbol: security.status == .official ? "checkmark.shield.fill" : "exclamationmark.shield.fill", tint: security.status == .official ? .green : (security.status == .modified ? .red : .gray), title: s("Ayu.BuildStatus"), label: ayuGramBuildStatusTitle(security.status, locale: data.strings.baseLanguageCode)))
    entries.append(.link(id: 692, section: .security, link: .reportScam, symbol: "exclamationmark.bubble.fill", tint: .orange, title: s("Ayu.ReportScam"), label: ""))
    entries.append(.toggle(id: 693, section: .security, key: .anonymousStats, symbol: "chart.bar.fill", tint: .indigo, title: s("Ayu.AnonymousStats"), subtitle: nil, value: extra.anonymousStats, enabled: true))
    entries.append(.footer(id: 694, section: .security, text: s("Ayu.AnonymousStatsInfo")))

    entries.append(.header(id: 700, section: .support, text: s("Ayu.SupportSection")))
    entries.append(.link(id: 710, section: .support, link: .channel, symbol: "paperplane.fill", tint: .blue, title: s("Ayu.SupportChannel"), label: ""))
    entries.append(.link(id: 720, section: .support, link: .developer, symbol: "person.crop.circle.fill", tint: .purple, title: s("Ayu.SupportDeveloper"), label: ""))
    entries.append(.link(id: 730, section: .support, link: .sessionLog, symbol: "doc.text.fill", tint: .gray, title: s("Ayu.SessionLog"), label: ""))
    entries.append(.link(id: 735, section: .support, link: .deepLinks, symbol: "link.circle.fill", tint: .teal, title: s("Ayu.DeepLink.Title"), label: ""))
    entries.append(.link(id: 740, section: .support, link: .checkUpdates, symbol: "arrow.triangle.2.circlepath", tint: .gray, title: s("Ayu.CheckUpdates"), label: ""))

    entries.append(.header(id: 800, section: .donate, text: s("Ayu.DonateSection")))
    entries.append(.link(id: 810, section: .donate, link: .donate, symbol: "heart.fill", tint: .pink, title: s("Ayu.Donate"), label: ""))
    entries.append(.footer(id: 820, section: .donate, text: s("Ayu.DonateFooter")))
    return entries
}

private func ayuScreenApplyToggle(context: AccountContext, key: AyuScreenToggle, value: Bool, present: @escaping (ViewController) -> Void) {
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
    case .confirmRead: settings.updateExtra { $0.confirmReadReceipt = value }
    case .anonymousStats: settings.updateExtra { $0.anonymousStats = value }
    case .assistantBubble: settings.updateExtra { $0.assistantBubble = value }
    case .chatCopilot: settings.updateExtra { $0.chatCopilot = value }
    case .styleLearning: AyuGramStyleLearning.enabled = value
    case .disableLiquidGlass:
        settings.updateExtra { $0.disableLiquidGlass = value }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let lang = data.strings.baseLanguageCode
        if value != AyuLegacyUI.isEnabled {
            present(textAlertController(context: context, title: i18n("Common.RestartRequired", lang), text: i18n("Ayu.RestartToApply", lang), actions: [
                TextAlertAction(type: .genericAction, title: i18n("Ayu.Later", lang), action: {}),
                TextAlertAction(type: .defaultAction, title: i18n("Common.RestartNow", lang), action: {
                    exit(0)
                })
            ]))
        }
    }
}

private func ayuScreenOpenLink(context: AccountContext, link: AyuScreenLink, push: @escaping (ViewController) -> Void, present: @escaping (ViewController) -> Void) {
    switch link {
    case .deepLinks:
        push(ayuGramDeepLinksController(context: context))
    case .history:
        push(ayuGramHistoryController(context: context))
    case .appearance:
        if let controller = ayuGramAppearanceEntryController(context: context) {
            push(controller)
        }
    case .profileExtras:
        push(ayuGramProfileExtrasController(context: context))
    case .plugins:
        push(ayuGramPluginsController(context: context))
    case .larpStars:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        present(promptController(context: context, text: i18n("Ayu.LarpStarsInfo", data.strings.baseLanguageCode), value: AyuGramLarpBalance.stars.map { "\($0)" } ?? "", placeholder: "1000000", characterLimit: 15, apply: { value in
            if let value {
                AyuGramLarpBalance.stars = AyuGramLarpBalance.parseStars(value)
                NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
            }
        }))
    case .larpTon:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        present(promptController(context: context, text: i18n("Ayu.LarpTonInfo", data.strings.baseLanguageCode), value: AyuGramLarpBalance.tonNano.map { AyuGramLarpBalance.formatTon($0) } ?? "", placeholder: "12.5", characterLimit: 20, apply: { value in
            if let value {
                AyuGramLarpBalance.tonNano = AyuGramLarpBalance.parseTon(value)
                NotificationCenter.default.post(name: AyuGramSettings.didChange, object: nil)
            }
        }))
    case .update:
        if let info = AyuGramUpdates.shared.availableUpdate {
            present(ayuGramUpdateAlert(context: context, info: info))
        }
    case .checkUpdates:
        AyuGramUpdates.shared.check { info in
            if let info {
                present(ayuGramUpdateAlert(context: context, info: info))
            } else {
                let data = context.sharedContext.currentPresentationData.with { $0 }
                present(textAlertController(context: context, title: nil, text: i18n("Ayu.UpToDate", data.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
            }
        }
    case .channel:
        ayuGramOpenLink(context: context, url: AyuGramUpdates.channelURL)
    case .donate:
        push(ayuGramDonateController(context: context))
    case .developer:
        ayuGramOpenDeveloper(context: context)
    case .sessionLog:
        guard let path = AyuGramSessionLog.path, !AyuGramSessionLog.read().isEmpty, let window = context.sharedContext.mainWindow else {
            let data = context.sharedContext.currentPresentationData.with { $0 }
            present(textAlertController(context: context, title: nil, text: i18n("Ayu.SessionLogEmpty", data.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
            return
        }
        let activity = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
        if let view = window.viewController?.view {
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = CGRect(origin: CGPoint(x: view.bounds.midX, y: view.bounds.midY), size: CGSize(width: 1.0, height: 1.0))
        }
        window.presentNative(activity)
    case .buildInfo:
        present(ayuGramBuildInfoAlert(context: context))
    case .reportScam:
        present(ayuGramScamReportPrompt(context: context, completion: {}))
    case .importChat:
        ayuGramImportChat(context: context)
    case .searchEngine:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: data)
        let current = Int(AyuGramSettings.shared.extra.searchEngine)
        var items: [ActionSheetItem] = []
        for (index, engine) in AyuGramSearchEngine.all.enumerated() {
            items.append(ActionSheetButtonItem(title: (index == current ? "✓ " : "") + engine.title, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramSettings.shared.updateExtra { $0.searchEngine = Int32(index) }
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        present(sheet)
    case .assistant:
        push(ayuGramAssistantController(context: context))
    case .aiProvider:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let sheet = ActionSheetController(presentationData: data)
        let current = AyuGramAssistantConfig.providerIndex
        var items: [ActionSheetItem] = []
        for (index, provider) in AyuGramAssistantProvider.all.enumerated() {
            items.append(ActionSheetButtonItem(title: (index == current ? "✓ " : "") + provider.title, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramAssistantConfig.providerIndex = index
            }))
        }
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        present(sheet)
    case .aiKey:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let config = AyuGramAssistantConfig.current
        present(promptController(context: context, text: i18n("Ayu.AIKey", data.strings.baseLanguageCode) + " · " + config.provider.title, value: config.key, placeholder: config.provider.keyHint, characterLimit: 400, apply: { value in
            if let value {
                AyuGramAssistantConfig.setKey(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }))
    case .aiLanguage:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        present(promptController(context: context, text: i18n("Ayu.AILanguageInfo", data.strings.baseLanguageCode), value: AyuGramAssistantPreferences.language, placeholder: "English", characterLimit: 40, apply: { value in
            if let value {
                AyuGramAssistantPreferences.language = value
            }
        }))
    case .aiStyle:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        present(promptController(context: context, text: i18n("Ayu.AIStyleInfo", data.strings.baseLanguageCode), value: AyuGramStyleLearning.notes, placeholder: i18n("Ayu.AIStyleHint", data.strings.baseLanguageCode), characterLimit: 900, apply: { value in
            if let value {
                if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AyuGramStyleLearning.reset()
                } else {
                    AyuGramStyleLearning.notes = value
                }
            }
        }))
    case .aiPersona:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        present(promptController(context: context, text: i18n("Ayu.AIPersonaInfo", data.strings.baseLanguageCode), value: AyuGramAssistantPreferences.persona, placeholder: i18n("Ayu.AIPersonaHint", data.strings.baseLanguageCode), characterLimit: 600, apply: { value in
            if let value {
                AyuGramAssistantPreferences.persona = value
            }
        }))
    case .supporter:
        push(ayuGramSupporterController(context: context))
    case .video:
        push(ayuGramVideoSettingsController(context: context))
    case .aiModel:
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let config = AyuGramAssistantConfig.current
        present(promptController(context: context, text: i18n("Ayu.AIModel", data.strings.baseLanguageCode) + " · " + config.provider.title, value: config.model, placeholder: config.provider.model, characterLimit: 200, apply: { value in
            if let value {
                AyuGramAssistantConfig.setModel(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }))
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
        present(sheet)
    }
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
        let securityObserver = NotificationCenter.default.addObserver(forName: AyuGramSecurity.didChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
            NotificationCenter.default.removeObserver(updateObserver)
            NotificationCenter.default.removeObserver(securityObserver)
        }
    }
    let arguments = AyuScreenArguments(toggle: { key, value in
        ayuScreenApplyToggle(context: context, key: key, value: value, present: { presentController?($0) })
    }, open: { link in
        ayuScreenOpenLink(context: context, link: link, push: { pushController?($0) }, present: { presentController?($0) })
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

private enum AyuDeepTarget {
    case main
    case link(AyuScreenLink)
    case deletedChats
    case swiftgram
    case market
    case submitPlugin
    case links
}

private let ayuDeepTargets: [(String, AyuDeepTarget, String, Bool)] = [
    ("settings", .main, "AyuGram", false),
    ("history", .link(.history), "Ayu.OpenHistory", false),
    ("deletedchats", .deletedChats, "Ayu.DeepLink.DeletedChats", false),
    ("appearancesettings", .link(.appearance), "Ayu.DeepLink.Appearance", true),
    ("profileextras", .link(.profileExtras), "Ayu.ProfileExtras.Title", false),
    ("plugins", .link(.plugins), "Ayu.Plugins.Title", false),
    ("marketplace", .market, "Ayu.Market.Title", false),
    ("submitplugin", .submitPlugin, "Ayu.Market.Form.Title", false),
    ("assistant", .link(.assistant), "Ayu.Assistant", false),
    ("searchengine", .link(.searchEngine), "Ayu.SearchEngine", false),
    ("aiprovider", .link(.aiProvider), "Ayu.AIProvider", false),
    ("aikey", .link(.aiKey), "Ayu.AIKey", false),
    ("aimodel", .link(.aiModel), "Ayu.AIModel", false),
    ("ailanguage", .link(.aiLanguage), "Ayu.AILanguage", false),
    ("aipersona", .link(.aiPersona), "Ayu.AIPersona", false),
    ("aistyle", .link(.aiStyle), "Ayu.AIStyle", false),
    ("silentsending", .link(.silentSending), "Ayu.SilentSending", false),
    ("importchat", .link(.importChat), "Ayu.ImportChat", false),
    ("video", .link(.video), "Ayu.Video.Title", false),
    ("supporter", .link(.supporter), "Ayu.SupporterBadge", false),
    ("larpstars", .link(.larpStars), "Ayu.LarpStars", false),
    ("larpton", .link(.larpTon), "Ayu.LarpTon", false),
    ("buildinfo", .link(.buildInfo), "Ayu.BuildStatus", false),
    ("reportscam", .link(.reportScam), "Ayu.ReportScam", false),
    ("channel", .link(.channel), "Ayu.SupportChannel", false),
    ("developer", .link(.developer), "Ayu.SupportDeveloper", false),
    ("sessionlog", .link(.sessionLog), "Ayu.SessionLog", false),
    ("checkupdates", .link(.checkUpdates), "Ayu.CheckUpdates", false),
    ("donate", .link(.donate), "Ayu.Donate", false),
    ("swiftgram", .swiftgram, "Swiftgram", false),
    ("links", .links, "Ayu.DeepLink.Title", false)
]

private let ayuDeepAliases: [String: String] = [
    "ayugram": "settings", "main": "settings", "appearance": "appearancesettings", "messagehistory": "history",
    "market": "marketplace", "profile": "profileextras", "ai": "assistant", "updates": "checkupdates",
    "log": "sessionlog", "build": "buildinfo", "report": "reportscam", "import": "importchat", "badge": "supporter",
    "stars": "larpstars", "ton": "larpton", "videosettings": "video", "sgsettings": "swiftgram"
]

private let ayuDeepToggles: [(String, AyuScreenToggle, String, Bool)] = [
    ("ghost", .ghost, "Ayu.Ghost", false),
    ("hideread", .read, "Ayu.HideRead", false),
    ("hideonline", .online, "Ayu.HideOnline", false),
    ("hidetyping", .typing, "Ayu.HideTyping", false),
    ("hiderecording", .recording, "Ayu.HideRecording", false),
    ("hideuploading", .uploading, "Ayu.HideUploading", false),
    ("hidestories", .stories, "Ayu.HideStories", false),
    ("savehistory", .history, "Ayu.History", false),
    ("offlineaftersending", .offlineAfterSending, "Ayu.OfflineAfterSending", false),
    ("readonsend", .readOnSend, "Ayu.ReadOnSend", false),
    ("quicktoggle", .quickToggle, "Ayu.QuickToggle", false),
    ("scheduleinghost", .scheduleInGhost, "Ayu.ScheduleInGhost", false),
    ("confirmread", .confirmRead, "Ayu.ConfirmReadReceipt", false),
    ("ignoreprotection", .ignoreProtection, "Ayu.IgnoreProtection", false),
    ("screenshots", .screenshots, "Ayu.AllowScreenshots", false),
    ("disableads", .disableAds, "Ayu.DisableAds", false),
    ("disablelinkwarning", .disableLinkWarning, "Ayu.DisableLinkWarning", false),
    ("disablegreeting", .disableGreeting, "Ayu.DisableGreeting", false),
    ("dimdeleted", .dimDeleted, "Ayu.DimDeleted", false),
    ("repeatmessage", .repeatMessage, "Ayu.RepeatMessage", false),
    ("confirmstickers", .confirmStickers, "Ayu.ConfirmStickers", false),
    ("confirmgifs", .confirmGifs, "Ayu.ConfirmGifs", false),
    ("assistantbubble", .assistantBubble, "Ayu.AIBubble", false),
    ("copilot", .chatCopilot, "Ayu.CopilotToggle", false),
    ("stylelearning", .styleLearning, "Ayu.AIStyleLearn", false),
    ("localpremium", .premium, "Ayu.LocalPremium", false),
    ("anonymousstats", .anonymousStats, "Ayu.AnonymousStats", false),
    ("disableliquidglass", .disableLiquidGlass, "Ayu.DisableLiquidGlass", true)
]

private func ayuDeepTitle(_ key: String, locale: String) -> String {
    return key.hasPrefix("Ayu.") ? i18n(key, locale) : key
}

private func ayuDeepOpenCustomPost(context: AccountContext) {
    AyuGramUpdates.customPost(completion: { url in
        ayuGramOpenLink(context: context, url: url)
    })
}

public func ayuGramHandleDeepLink(context: AccountContext, url: URL, navigationController: NavigationController) -> Bool {
    guard url.scheme?.lowercased() == "ayugram" else {
        return false
    }
    var parts = [(url.host ?? "").lowercased()] + url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
    parts = parts.filter { !$0.isEmpty }
    guard var name = parts.first else {
        return false
    }
    name = ayuDeepAliases[name] ?? name
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    let push: (ViewController) -> Void = { controller in
        navigationController.pushViewController(controller)
    }
    let present: (ViewController) -> Void = { controller in
        context.sharedContext.mainWindow?.present(controller, on: .root)
    }
    if name == "set" || name == "toggle" {
        guard parts.count >= 2, let toggle = ayuDeepToggles.first(where: { $0.0 == parts[1] }) else {
            push(ayuGramSettingsScreen(context: context))
            return true
        }
        if toggle.3 && !ayuGramHasAppearanceEntry {
            ayuDeepOpenCustomPost(context: context)
            return true
        }
        let raw = parts.count >= 3 ? parts[2] : (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "value" })?.value ?? "").lowercased()
        let value: Bool
        if ["on", "1", "true", "yes", "enable"].contains(raw) {
            value = true
        } else if ["off", "0", "false", "no", "disable"].contains(raw) {
            value = false
        } else {
            push(ayuGramSettingsScreen(context: context))
            return true
        }
        let title = ayuDeepTitle(toggle.2, locale: locale)
        present(textAlertController(context: context, title: nil, text: i18n(value ? "Ayu.DeepLink.TurnOn" : "Ayu.DeepLink.TurnOff", locale, title), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {
                ayuScreenApplyToggle(context: context, key: toggle.1, value: value, present: present)
            })
        ]))
        return true
    }
    if let toggle = ayuDeepToggles.first(where: { $0.0 == name }) {
        if toggle.3 && !ayuGramHasAppearanceEntry {
            ayuDeepOpenCustomPost(context: context)
        } else {
            push(ayuGramSettingsScreen(context: context))
        }
        return true
    }
    guard let target = ayuDeepTargets.first(where: { $0.0 == name }) else {
        return false
    }
    if target.3 && !ayuGramHasAppearanceEntry {
        ayuDeepOpenCustomPost(context: context)
        return true
    }
    switch target.1 {
    case .main:
        push(ayuGramSettingsScreen(context: context))
    case let .link(link):
        ayuScreenOpenLink(context: context, link: link, push: push, present: present)
    case .deletedChats:
        push(ayuGramDeletedChatsController(context: context))
    case .swiftgram:
        push(sgSettingsController(context: context))
    case .market:
        let slug = parts.count >= 2 ? parts[1] : (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "slug" })?.value ?? "")
        push(slug.isEmpty ? ayuGramMarketController(context: context) : ayuGramMarketPluginController(context: context, slug: slug))
    case .submitPlugin:
        push(ayuGramMarketSubmitController(context: context, completed: {}))
    case .links:
        push(ayuGramDeepLinksController(context: context))
    }
    return true
}

private final class AyuDeepLinksArguments {
    let copy: (String) -> Void

    init(copy: @escaping (String) -> Void) {
        self.copy = copy
    }
}

private enum AyuDeepLinksEntry: ItemListNodeEntry {
    case header(Int, Int32, String)
    case item(Int, Int32, String, String)
    case footer(Int, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .item(_, section, _, _), let .footer(_, section, _):
            return section
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _), let .item(id, _, _, _), let .footer(id, _, _):
            return id
        }
    }

    static func < (lhs: AyuDeepLinksEntry, rhs: AyuDeepLinksEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! AyuDeepLinksArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .item(_, _, title, link):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: link, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                args.copy(link)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func ayuGramDeepLinksController(context: AccountContext) -> ViewController {
    var presentImpl: ((ViewController) -> Void)?
    let arguments = AyuDeepLinksArguments(copy: { link in
        UIPasteboard.general.string = link
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentImpl?(UndoOverlayController(presentationData: data, content: .copy(text: i18n("Ayu.DeepLink.Copied", data.strings.baseLanguageCode)), elevatedLayout: false, animateInAsReplacement: false, action: { _ in return false }))
    })
    let signal = context.sharedContext.presentationData
    |> map { data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let locale = data.strings.baseLanguageCode
        var entries: [AyuDeepLinksEntry] = []
        entries.append(.header(0, 0, i18n("Ayu.DeepLink.Screens", locale)))
        for (index, target) in ayuDeepTargets.enumerated() {
            entries.append(.item(10 + index, 0, ayuDeepTitle(target.2, locale: locale) + (target.3 ? " · Custom" : ""), "ayugram://" + target.0))
        }
        entries.append(.header(500, 1, i18n("Ayu.DeepLink.Toggles", locale)))
        for (index, toggle) in ayuDeepToggles.enumerated() {
            entries.append(.item(510 + index, 1, ayuDeepTitle(toggle.2, locale: locale) + (toggle.3 ? " · Custom" : ""), "ayugram://set/" + toggle.0 + "/on"))
        }
        entries.append(.footer(900, 1, i18n("Ayu.DeepLink.Footer", locale)))
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(i18n("Ayu.DeepLink.Title", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    return controller
}
