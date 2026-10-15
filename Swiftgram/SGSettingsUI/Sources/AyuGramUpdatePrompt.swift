import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import SGSimpleSettings
import SGStrings

/// Opens a link inside Telegram when it can (t.me), otherwise in the browser.
func ayuGramOpenLink(context: AccountContext, url: String) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController
    context.sharedContext.openExternalUrl(context: context, urlContext: .generic, url: url, forceExternal: false, presentationData: data, navigationController: navigationController, dismissInput: {})
}

/// Opens the developer's profile; falls back to its t.me link if the profile is not cached yet.
func ayuGramOpenDeveloper(context: AccountContext) {
    let peerId = EnginePeer.Id(AyuGramUpdates.developerId)
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue).startStandalone(next: { peer in
        if let peer, let profile = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            (context.sharedContext.mainWindow?.viewController as? NavigationController)?.pushViewController(profile)
        } else {
            ayuGramOpenLink(context: context, url: "https://t.me/@id\(AyuGramUpdates.developerId)")
        }
    })
}

/// Installer apps tried in order; each receives the IPA link and installs it. The first
/// one present on the device opens; without any, the IPA link opens in the browser.
private let ayuGramInstallers: [(String) -> String] = [
    { "apple-magnifier://install?url=" + $0 },
    { "sidestore://install?url=" + $0 },
    { "altstore://install?url=" + $0 },
    { "feather://install/" + $0 },
    { "esign://install?url=" + $0 },
    { "scarlet://install=" + $0 }
]

private func ayuGramOpenInstaller(_ candidates: ArraySlice<URL>, fallback: URL) {
    guard let url = candidates.first else {
        UIApplication.shared.open(fallback, options: [:], completionHandler: nil)
        return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
        if !opened {
            ayuGramOpenInstaller(candidates.dropFirst(), fallback: fallback)
        }
    }
}

/// Hands the IPA of this variant to an installer app; without a direct IPA link the
/// update channel opens instead.
func ayuGramInstallUpdate(context: AccountContext, info: AyuGramUpdateInfo) {
    guard let ipa = info.ipa[ayuGramHasAppearanceEntry ? "custom" : "standard"], let ipaURL = URL(string: ipa) else {
        ayuGramOpenLink(context: context, url: info.url)
        return
    }
    let encoded = ipa.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ipa
    ayuGramOpenInstaller(ArraySlice(ayuGramInstallers.compactMap { URL(string: $0(encoded)) }), fallback: ipaURL)
}

func ayuGramUpdateAlert(context: AccountContext, info: AyuGramUpdateInfo) -> ViewController {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    return textAlertController(context: context, title: i18n("Ayu.UpdateQuestion", locale), text: i18n("Ayu.UpdateQuestionInfo", locale, info.version), actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_No, action: {
            AyuGramUpdates.shared.ignore(info)
        }),
        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Yes, action: {
            ayuGramInstallUpdate(context: context, info: info)
        })
    ])
}

/// Called once the main interface is ready: checks for a newer build, which the chat
/// list then announces; tapping the notice opens the update dialog.
public func ayuGramPresentUpdateIfNeeded(context: AccountContext) {
    AyuGramUpdates.presentUpdate = { [weak context] in
        guard let context, let info = AyuGramUpdates.shared.availableUpdate else {
            return
        }
        context.sharedContext.mainWindow?.present(ayuGramUpdateAlert(context: context, info: info), on: .root)
    }
    AyuGramUpdates.shared.check { _ in }
}
