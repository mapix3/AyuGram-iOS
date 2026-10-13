import UIKit
import Foundation
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

private enum AyuSection: Int32, SGItemListSection { case privacy, history, client }
private enum AyuToggle: Hashable { case ghost, read, online, typing, recording, uploading, stories, history, premium }
private enum AyuSlider: Hashable { case pins }
private enum AyuUnused: Hashable { case unused, customization }
private typealias AyuEntry = SGItemListUIEntry<AyuSection, AyuToggle, AyuSlider, AyuUnused, AyuUnused, AyuUnused>

public func ayuGramSettingsController(context: AccountContext) -> ViewController {
    var openHistory: (() -> Void)?
    var openAppearance: (() -> Void)?
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let arguments = SGItemListArguments<AyuToggle, AyuSlider, AyuUnused, AyuUnused, AyuUnused>(context: context, setBoolValue: { key, enabled in
        if key == .premium {
            AyuGramSettings.shared.updateClient { $0.localPremium = enabled }
        } else {
            AyuGramSettings.shared.update { settings in
                switch key {
                case .ghost: settings.ghostMode = enabled
                case .read: settings.antiRead = enabled
                case .online: settings.antiOnline = enabled
                case .typing: settings.antiTyping = enabled
                case .recording: settings.antiRecording = enabled
                case .uploading: settings.antiUploading = enabled
                case .stories: settings.storyPrivacy = enabled
                case .history: settings.messageHistory = enabled
                case .premium: break
                }
            }
        }
        changed.set(0)
    }, updateSliderValue: { _, value in
        AyuGramSettings.shared.updateClient { $0.maxPinnedChats = value }
        changed.set(0)
    }, openDisclosureLink: { link in
        if link == .customization { openAppearance?() } else { openHistory?() }
    })
    let signal = combineLatest(context.sharedContext.presentationData, changed.get())
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, SGItemListArguments<AyuToggle, AyuSlider, AyuUnused, AyuUnused, AyuUnused>)) in
        let settings = AyuGramSettings.shared.snapshot
        let client = AyuGramSettings.shared.client
        let locale = data.strings.baseLanguageCode
        let entries: [AyuEntry] = [
            .header(id: 0, section: .privacy, text: data.strings.Settings_PrivacySettings, badge: nil),
            .toggle(id: 1, section: .privacy, settingName: .ghost, value: settings.ghostMode, text: i18n("Ayu.Ghost", locale), enabled: true),
            .toggle(id: 2, section: .privacy, settingName: .read, value: settings.suppressRead, text: i18n("Ayu.HideRead", locale), enabled: !settings.ghostMode),
            .toggle(id: 3, section: .privacy, settingName: .online, value: settings.suppressOnline, text: i18n("Ayu.HideOnline", locale), enabled: !settings.ghostMode),
            .toggle(id: 4, section: .privacy, settingName: .typing, value: settings.suppressTyping, text: i18n("Ayu.HideTyping", locale), enabled: !settings.ghostMode),
            .toggle(id: 5, section: .privacy, settingName: .recording, value: settings.suppressRecording, text: i18n("Ayu.HideRecording", locale), enabled: !settings.ghostMode),
            .toggle(id: 6, section: .privacy, settingName: .uploading, value: settings.suppressUploading, text: i18n("Ayu.HideUploading", locale), enabled: !settings.ghostMode),
            .toggle(id: 7, section: .privacy, settingName: .stories, value: settings.suppressStoryViews, text: i18n("Ayu.HideStories", locale), enabled: !settings.ghostMode),
            .header(id: 10, section: .history, text: i18n("Ayu.History", locale), badge: nil),
            .toggle(id: 11, section: .history, settingName: .history, value: settings.messageHistory, text: i18n("Ayu.SaveDeleted", locale), enabled: true),
            .disclosure(id: 12, section: .history, link: .unused, text: i18n("Ayu.History", locale)),
            .header(id: 15, section: .client, text: "AyuGram", badge: nil),
            .toggle(id: 16, section: .client, settingName: .premium, value: client.localPremium, text: i18n("Ayu.LocalPremium", locale), enabled: true),
            .header(id: 18, section: .client, text: i18n("Ayu.Pins", locale), badge: nil),
            .countSlider(id: 19, section: .client, settingName: .pins, value: client.pinnedChatLimit),
            .notice(id: 20, section: .client, text: i18n("Ayu.LocalOnly", locale)),
            .disclosure(id: 21, section: .client, link: .customization, text: data.strings.Appearance_Title)
        ]
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text("AyuGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    openHistory = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(ayuGramHistoryController(context: context))
    }
    openAppearance = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(ayuGramAppearanceController(context: context))
    }
    return controller
}
