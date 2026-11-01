import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import PromptUI
import SGSimpleSettings
import SGStrings

var ayuGramVariant: String {
    return ayuGramHasAppearanceEntry ? "custom" : "standard"
}

private var ayuGramBlockPresented = false
private var ayuGramSecurityObserver: NSObjectProtocol?

func ayuGramStartSecurity(context: AccountContext) {
    AyuGramUpdates.manifestObserver = { data in
        AyuGramSecurity.shared.applyManifest(data)
    }
    if let observer = ayuGramSecurityObserver {
        NotificationCenter.default.removeObserver(observer)
    }
    ayuGramSecurityObserver = NotificationCenter.default.addObserver(forName: AyuGramSecurity.didChange, object: nil, queue: .main, using: { [weak context] _ in
        guard let context else {
            return
        }
        ayuGramPresentBlockIfNeeded(context: context)
    })
    AyuGramSecurity.shared.start(variant: ayuGramVariant, statsEnabled: {
        return AyuGramSettings.shared.extra.anonymousStats
    })
    ayuGramPresentBlockIfNeeded(context: context)
}

func ayuGramBuildStatusTitle(_ status: AyuGramBuildStatus, locale: String) -> String {
    switch status {
    case .official:
        return i18n("Ayu.BuildOfficial", locale)
    case .modified:
        return i18n("Ayu.BuildModified", locale)
    case .checking:
        return i18n("Ayu.BuildChecking", locale)
    case .unknown:
        return i18n("Ayu.BuildUnknown", locale)
    }
}

private func ayuGramSourceTitle(_ source: AyuGramInstallSource, locale: String) -> String {
    switch source {
    case .sideload:
        return i18n("Ayu.SourceSideload", locale)
    case .enterprise:
        return i18n("Ayu.SourceEnterprise", locale)
    case .testflight:
        return "TestFlight"
    case .appstore:
        return "App Store"
    case .unknown:
        return i18n("Ayu.BuildUnknown", locale)
    }
}

func ayuGramBuildInfoAlert(context: AccountContext) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let security = AyuGramSecurity.shared
    let summary: String
    switch security.status {
    case .official:
        summary = i18n("Ayu.BuildInfoOfficial", locale)
    case .modified:
        summary = i18n("Ayu.BuildInfoModified", locale)
    case .checking, .unknown:
        summary = i18n("Ayu.BuildInfoUnknown", locale)
    }
    var certificate = security.signing.certificate
    if certificate.isEmpty {
        certificate = security.signing.teamName
    }
    if certificate.isEmpty {
        certificate = "-"
    }
    let team = security.signing.teamId.isEmpty ? "-" : security.signing.teamId
    let details = i18n("Ayu.BuildDetails", locale, "\(security.build)", ayuGramSourceTitle(security.signing.source, locale: locale), certificate, team)
    return textAlertController(context: context, title: ayuGramBuildStatusTitle(security.status, locale: locale), text: summary + "\n\n" + details, actions: [
        TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})
    ])
}

func ayuGramScamReportPrompt(context: AccountContext, completion: @escaping () -> Void) -> ViewController {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    var finished = false
    let finish: () -> Void = {
        if !finished {
            finished = true
            completion()
        }
    }
    return promptController(context: context, text: i18n("Ayu.ReportScamInfo", locale), value: "", placeholder: "@username", characterLimit: 600, apply: { value in
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finish()
            return
        }
        finished = true
        AyuGramSecurity.shared.report(text: value, variant: ayuGramVariant, completion: { ok in
            let result = textAlertController(context: context, title: nil, text: i18n(ok ? "Ayu.ReportScamSent" : "Ayu.ReportScamFailed", locale), actions: [
                TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {
                    completion()
                })
            ], dismissOnOutsideTap: false)
            context.sharedContext.mainWindow?.present(result, on: .root)
        })
    }, dismissed: {
        finish()
    })
}

func ayuGramPresentBlockIfNeeded(context: AccountContext) {
    guard AyuGramSecurity.shared.isBlocked, !ayuGramBlockPresented else {
        return
    }
    ayuGramBlockPresented = true
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let reshow: () -> Void = { [weak context] in
        guard let context else {
            return
        }
        Queue.mainQueue().after(0.8, {
            ayuGramBlockPresented = false
            ayuGramPresentBlockIfNeeded(context: context)
        })
    }
    let text = AyuGramSecurity.shared.blockMessage ?? i18n("Ayu.ScamText", locale)
    let alert = textAlertController(context: context, title: i18n("Ayu.ScamTitle", locale), text: text, actions: [
        TextAlertAction(type: .defaultAction, title: i18n("Ayu.ScamChannel", locale), action: {
            ayuGramOpenLink(context: context, url: AyuGramUpdates.channelURL)
            reshow()
        }),
        TextAlertAction(type: .genericAction, title: i18n("Ayu.ReportScam", locale), action: {
            context.sharedContext.mainWindow?.present(ayuGramScamReportPrompt(context: context, completion: reshow), on: .root)
        })
    ], actionLayout: .vertical, dismissOnOutsideTap: false)
    context.sharedContext.mainWindow?.present(alert, on: .root)
}
