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

func ayuGramUpdateAlert(context: AccountContext, info: AyuGramUpdateInfo) -> ViewController {
    let locale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    return textAlertController(context: context, title: i18n("Ayu.UpdateAvailable", locale), text: i18n("Ayu.UpdateAvailableInfo", locale, info.version), actions: [
        TextAlertAction(type: .genericAction, title: i18n("Ayu.UpdateIgnore", locale), action: {
            AyuGramUpdates.shared.ignore(info)
        }),
        TextAlertAction(type: .defaultAction, title: i18n("Ayu.UpdateOpen", locale), action: {
            ayuGramOpenLink(context: context, url: info.url)
        })
    ])
}

/// Called once the main interface is ready: shows the update alert for a newer build
/// unless the user already chose Ignore for it.
public func ayuGramPresentUpdateIfNeeded(context: AccountContext) {
    AyuGramUpdates.shared.check { info in
        guard let info, !AyuGramUpdates.shared.isIgnored(info) else { return }
        context.sharedContext.mainWindow?.present(ayuGramUpdateAlert(context: context, info: info), on: .root)
    }
}
