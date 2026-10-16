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

/// Installer apps that take an IPA link, tried in order. Their schemes are listed in
/// LSApplicationQueriesSchemes, so only installers present on the device are opened.
private let ayuGramInstallers: [(scheme: String, link: (String) -> String)] = [
    ("sidestore", { "sidestore://install?url=" + $0 }),
    ("altstore", { "altstore://install?url=" + $0 }),
    ("feather", { "feather://install/" + $0 }),
    ("esign", { "esign://install?url=" + $0 }),
    ("scarlet", { "scarlet://install=" + $0 })
]

/// TrollStore marks the apps it installs with a `_TrollStore` file next to the bundle.
/// Its link uses the system Magnifier's scheme, which opens Magnifier without TrollStore,
/// so it is only used for a TrollStore install.
private var ayuGramInstalledByTrollStore: Bool {
    return FileManager.default.fileExists(atPath: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("_TrollStore").path)
}

/// LiveContainer runs its apps from its own Documents/Applications folder and sets LC_HOME_PATH.
private var ayuGramRunsInLiveContainer: Bool {
    let path = Bundle.main.bundlePath
    return ProcessInfo.processInfo.environment["LC_HOME_PATH"] != nil || path.contains("/Documents/Applications/") || path.contains("/LiveContainer/")
}

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

/// Hands the IPA of this variant to the installer AyuGram came from, or else the first
/// installer found on the device; without one, the build's GitHub release page opens.
/// Without a direct IPA link the update channel opens instead.
func ayuGramInstallUpdate(context: AccountContext, info: AyuGramUpdateInfo) {
    guard let ipa = info.ipa[ayuGramHasAppearanceEntry ? "custom" : "standard"], let ipaURL = URL(string: ipa) else {
        ayuGramOpenLink(context: context, url: info.url)
        return
    }
    let encoded = ipa.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ipa
    // LiveContainer installs nothing while one of its apps runs ("Please restart LiveContainer
    // to install apps"), so from inside it the install link is copied for after a restart.
    if ayuGramRunsInLiveContainer {
        let link = "livecontainer://install?url=" + encoded
        UIPasteboard.general.string = link
        let data = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.mainWindow?.present(textAlertController(context: context, title: "LiveContainer", text: i18n("Ayu.LiveContainerUpdate", data.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), on: .root)
        return
    }
    var candidates: [URL] = []
    if ayuGramInstalledByTrollStore, let url = URL(string: "apple-magnifier://install?url=" + encoded) {
        candidates.append(url)
    }
    let isInstalled: (String) -> Bool = { scheme in
        return URL(string: scheme + "://").map { UIApplication.shared.canOpenURL($0) } == true
    }
    for installer in ayuGramInstallers where isInstalled(installer.scheme) {
        if let url = URL(string: installer.link(encoded)) {
            candidates.append(url)
        }
    }
    // SideStore built into LiveContainer has no URL scheme of its own; LiveContainer launches
    // it with the install link.
    if isInstalled("livecontainer") {
        let sideStoreLink = Data(("sidestore://install?url=" + encoded).utf8).base64EncodedString()
        let query = sideStoreLink.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? sideStoreLink
        if let url = URL(string: "livecontainer://livecontainer-launch?bundle-name=builtinSideStore&open-url=" + query) {
            candidates.append(url)
        }
    }
    // .../releases/download/build-N/AyuGram-x.ipa -> .../releases/tag/build-N
    var page = ipaURL.deletingLastPathComponent().absoluteString.replacingOccurrences(of: "/releases/download/", with: "/releases/tag/")
    if page.hasSuffix("/") {
        page.removeLast()
    }
    let release = URL(string: page) ?? ipaURL
    ayuGramOpenInstaller(ArraySlice(candidates), fallback: release)
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
