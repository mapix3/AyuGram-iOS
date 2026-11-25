import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import SGSimpleSettings
import SGStrings
import AyuGramProfileExtras

func ayuGramAnonymousNumber(fromUrl url: String) -> String? {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercased = trimmed.lowercased()
    if lowercased.hasPrefix("tel:") {
        let value = String(trimmed.dropFirst(4)).removingPercentEncoding ?? String(trimmed.dropFirst(4))
        let number = value.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? value
        return AyuGramProfileEntry.normalizeNumber(number)
    }
    var candidate = lowercased
    for prefix in ["https://", "http://"] {
        if candidate.hasPrefix(prefix) {
            candidate = String(candidate.dropFirst(prefix.count))
            break
        }
    }
    if candidate.hasPrefix("www.") {
        candidate = String(candidate.dropFirst(4))
    }
    if candidate.hasPrefix("tg://resolve?") {
        guard let components = URLComponents(string: trimmed), let phone = components.queryItems?.first(where: { $0.name == "phone" })?.value else {
            return nil
        }
        return AyuGramProfileEntry.normalizeNumber(phone)
    }
    for host in ["t.me/", "telegram.me/", "telegram.dog/"] {
        if candidate.hasPrefix(host) {
            let path = String(candidate.dropFirst(host.count))
            let component = path.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" }).first.map(String.init) ?? path
            let decoded = component.removingPercentEncoding ?? component
            guard decoded.hasPrefix("+") || decoded.hasPrefix(" ") else {
                return nil
            }
            return AyuGramProfileEntry.normalizeNumber(decoded.trimmingCharacters(in: .whitespaces))
        }
    }
    return nil
}

func ayuGramOpenAnonymousNumber(context: AccountContext, number: String, presentationData: PresentationData, navigationController: NavigationController?, fallback: @escaping () -> Void) {
    let digits = String(number.dropFirst())
    let _ = (combineLatest(
        ayuGramFakeNumberHolderPeer(engine: context.engine, query: number) |> take(1),
        context.engine.peers.resolvePeerByPhone(phone: digits) |> take(1) |> timeout(6.0, queue: Queue.mainQueue(), alternate: .single(nil))
    )
    |> deliverOnMainQueue).startStandalone(next: { fakeHolder, realPeer in
        guard let fakeHolder else {
            fallback()
            return
        }
        let locale = presentationData.strings.baseLanguageCode
        let openProfile: (EnginePeer) -> Void = { peer in
            if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
                navigationController?.pushViewController(controller)
            }
        }
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        items.append(ActionSheetTextItem(title: AyuGramProfileEntry.formatNumber(number), font: .large, parseMarkdown: false))
        if let realPeer, realPeer.id != fakeHolder.id {
            items.append(ActionSheetButtonItem(title: realPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                openProfile(realPeer)
            }))
            items.append(ActionSheetTextItem(title: i18n("Ayu.FakeNumber.RealResult", locale), parseMarkdown: false))
        } else {
            items.append(ActionSheetTextItem(title: i18n("Ayu.FakeNumber.NoRealResult", locale), parseMarkdown: false))
        }
        items.append(ActionSheetButtonItem(title: fakeHolder.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder), color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            openProfile(fakeHolder)
        }))
        items.append(ActionSheetTextItem(title: "⚠️ " + i18n("Ayu.FakeNumber.Plaque", locale) + " · " + i18n("Ayu.FakeNumber.SearchInfo", locale), parseMarkdown: false))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
            })])
        ])
        context.sharedContext.presentGlobalController(sheet, nil)
    })
}
