import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import OverlayStatusController
import SGSimpleSettings
import SGStrings
import AyuGramProfileExtras

private enum AyuNftSearchSection: Int32 {
    case search, results
}

private enum AyuNftSearchEntry: ItemListNodeEntry {
    case input(id: Int, section: AyuNftSearchSection, text: String, placeholder: String, isNumber: Bool)
    case action(id: Int, section: AyuNftSearchSection, title: String, payload: String)
    case header(id: Int, section: AyuNftSearchSection, text: String)
    case footer(id: Int, section: AyuNftSearchSection, text: String)
    case status(id: Int, section: AyuNftSearchSection, text: String)
    case row(id: Int, section: AyuNftSearchSection, index: Int, title: String, label: String)
    case more(id: Int, section: AyuNftSearchSection, title: String)

    var section: ItemListSectionId {
        switch self {
        case let .input(_, section, _, _, _), let .action(_, section, _, _), let .header(_, section, _), let .footer(_, section, _), let .status(_, section, _), let .row(_, section, _, _, _), let .more(_, section, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .input(id, _, _, _, _), let .action(id, _, _, _), let .header(id, _, _), let .footer(id, _, _), let .status(id, _, _), let .row(id, _, _, _, _), let .more(id, _, _):
            return id
        }
    }

    static func <(lhs: AyuNftSearchEntry, rhs: AyuNftSearchEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuNftSearchArguments
        switch self {
        case let .input(_, _, text, placeholder, isNumber):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: text, placeholder: placeholder, type: isNumber ? .number : .regular(capitalization: false, autocorrection: false), returnKeyType: .search, clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.updateQuery(value)
            }, action: {
                arguments.submit()
            })
        case let .action(_, _, title, payload):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon("arrow.right.circle.fill", color: AyuGramRowColor.blue), title: title, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openPayload(payload)
            })
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .status(_, _, text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, enabled: false, label: "", sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .row(_, _, index, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon("gift.fill", color: AyuGramRowColor.purple), title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openRow(index)
            })
        case let .more(_, _, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.loadMore()
            })
        }
    }
}

private final class AyuNftSearchArguments {
    let updateQuery: (String) -> Void
    let submit: () -> Void
    let openPayload: (String) -> Void
    let openRow: (Int) -> Void
    let loadMore: () -> Void

    init(updateQuery: @escaping (String) -> Void, submit: @escaping () -> Void, openPayload: @escaping (String) -> Void, openRow: @escaping (Int) -> Void, loadMore: @escaping () -> Void) {
        self.updateQuery = updateQuery
        self.submit = submit
        self.openPayload = openPayload
        self.openRow = openRow
        self.loadMore = loadMore
    }
}

private func ayuNftSearchKey(_ value: String) -> String {
    return String(String.UnicodeScalarView(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
}

private func ayuNftCollectible(_ gift: StarGift.Gift) -> Bool {
    guard let title = gift.title, !title.isEmpty else {
        return false
    }
    return gift.upgradeVariantsCount != nil || (gift.availability?.resale ?? 0) > 0
}

private func ayuNftModelName(_ gift: StarGift.UniqueGift) -> String {
    for attribute in gift.attributes {
        if case let .model(name, _, _, _) = attribute {
            return name
        }
    }
    return ""
}

private func ayuNftFetchSlug(context: AccountContext, slug: String, present: @escaping (ViewController) -> Void, completion: @escaping (StarGift.UniqueGift) -> Void) -> Disposable {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let locale = data.strings.baseLanguageCode
    let progress = OverlayStatusController(theme: data.theme, type: .loading(cancelled: nil))
    present(progress)
    return (AyuGramFakeNftResolver.shared.fetch(engine: context.engine, slug: slug)
    |> deliverOnMainQueue).start(next: { gift in
        progress.dismiss()
        completion(gift)
    }, error: { error in
        progress.dismiss()
        let text: String
        switch error {
        case .alreadyBurned:
            text = i18n("Ayu.ProfileExtras.Error.NftBurned", locale)
        case .invalidSlug:
            text = i18n("Ayu.ProfileExtras.Error.NftNotFound", locale)
        case .generic:
            text = i18n("Ayu.ProfileExtras.Error.Network", locale)
        }
        present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]))
    })
}

private final class AyuNftSearchHolder {
    let disposables = DisposableSet()
    let resaleContext: ResaleGiftsContext?

    init(resaleContext: ResaleGiftsContext?) {
        self.resaleContext = resaleContext
    }

    deinit {
        self.disposables.dispose()
    }
}

func ayuGramNftSearchController(context: AccountContext, onPick: @escaping (StarGift.UniqueGift) -> Void) -> ViewController {
    let holder = AyuNftSearchHolder(resaleContext: nil)
    var query = ""
    var catalog: [StarGift.Gift]?
    var shown: [StarGift.Gift] = []
    let updates = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    let changed: () -> Void = {
        revision += 1
        updates.set(revision)
    }
    var presentImpl: ((ViewController) -> Void)?
    var pushImpl: ((ViewController) -> Void)?

    holder.disposables.add(context.engine.payments.keepStarGiftsUpdated().start())
    holder.disposables.add((context.engine.payments.cachedStarGifts()
    |> deliverOnMainQueue).start(next: { gifts in
        guard let gifts else {
            return
        }
        var seen = Set<String>()
        var result: [StarGift.Gift] = []
        for gift in gifts {
            guard case let .generic(value) = gift, ayuNftCollectible(value), let title = value.title else {
                continue
            }
            let key = ayuNftSearchKey(title)
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            result.append(value)
        }
        catalog = result
        changed()
    }))

    func openSlug(_ slug: String) {
        holder.disposables.add(ayuNftFetchSlug(context: context, slug: slug, present: { controller in
            presentImpl?(controller)
        }, completion: { gift in
            onPick(gift)
        }))
    }

    let arguments = AyuNftSearchArguments(updateQuery: { value in
        query = value
        changed()
    }, submit: {
        if let slug = AyuGramProfileNft.parseSlug(query) {
            openSlug(slug)
        }
    }, openPayload: { payload in
        openSlug(payload)
    }, openRow: { index in
        guard index >= 0, index < shown.count else {
            return
        }
        pushImpl?(ayuGramNftCollectionController(context: context, gift: shown[index], onPick: onPick))
    }, loadMore: {
    })

    let signal = combineLatest(context.sharedContext.presentationData, updates.get())
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, AyuNftSearchArguments)) in
        let locale = data.strings.baseLanguageCode
        var entries: [AyuNftSearchEntry] = []
        entries.append(.input(id: 0, section: .search, text: query, placeholder: i18n("Ayu.NftSearch.Placeholder", locale), isNumber: false))
        if let slug = AyuGramProfileNft.parseSlug(query) {
            entries.append(.action(id: 1, section: .search, title: i18n("Ayu.NftSearch.OpenSlug", locale, slug), payload: slug))
        }
        entries.append(.footer(id: 2, section: .search, text: i18n("Ayu.NftSearch.Info", locale)))
        entries.append(.header(id: 10, section: .results, text: i18n("Ayu.NftSearch.Collections", locale)))
        if let catalog {
            let key = ayuNftSearchKey(query)
            let filtered = key.isEmpty || AyuGramProfileNft.parseSlug(query) != nil ? catalog : catalog.filter { ayuNftSearchKey($0.title ?? "").contains(key) }
            shown = Array(filtered.prefix(80))
            if shown.isEmpty {
                entries.append(.status(id: 11, section: .results, text: i18n("Ayu.NftSearch.Empty", locale)))
            }
            for (index, gift) in shown.enumerated() {
                let resale = gift.availability?.resale ?? 0
                entries.append(.row(id: 100 + index, section: .results, index: index, title: gift.title ?? "", label: resale > 0 ? i18n("Ayu.NftSearch.OnSale", locale, "\(resale)") : ""))
            }
        } else {
            shown = []
            entries.append(.status(id: 11, section: .results, text: i18n("Ayu.ProfileExtras.Loading", locale)))
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(i18n("Ayu.NftSearch.Title", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { _ in
        let _ = holder
    }
    presentImpl = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    pushImpl = { [weak controller] next in
        (controller?.navigationController as? NavigationController)?.pushViewController(next)
    }
    return controller
}

private func ayuGramNftCollectionController(context: AccountContext, gift: StarGift.Gift, onPick: @escaping (StarGift.UniqueGift) -> Void) -> ViewController {
    let resaleContext = ResaleGiftsContext(account: context.account, giftId: gift.id, forCrafting: false)
    resaleContext.updateSorting(.number)
    let holder = AyuNftSearchHolder(resaleContext: resaleContext)
    var number = ""
    var items: [StarGift.UniqueGift] = []
    var loading = true
    var canLoadMore = false
    let updates = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    let changed: () -> Void = {
        revision += 1
        updates.set(revision)
    }
    var presentImpl: ((ViewController) -> Void)?
    let title = gift.title ?? ""

    holder.disposables.add((resaleContext.state
    |> deliverOnMainQueue).start(next: { state in
        items = state.gifts.compactMap { value -> StarGift.UniqueGift? in
            if case let .unique(uniqueGift) = value {
                return uniqueGift
            }
            return nil
        }
        switch state.dataState {
        case .loading:
            loading = true
            canLoadMore = false
        case let .ready(canLoadMoreValue, _):
            loading = false
            canLoadMore = canLoadMoreValue
        }
        changed()
    }))

    func slugBase() -> String {
        if let first = items.first, let base = first.slug.split(separator: "-").first, !base.isEmpty {
            return String(base)
        }
        return String(String.UnicodeScalarView(title.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }))
    }

    func parsedNumber() -> Int? {
        let digits = number.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        guard let value = Int(digits), value > 0, value < 10_000_000 else {
            return nil
        }
        return value
    }

    func findNumber() {
        guard let value = parsedNumber() else {
            return
        }
        let slug = slugBase() + "-" + String(value)
        guard AyuGramProfileNft.isValidSlug(slug) else {
            return
        }
        holder.disposables.add(ayuNftFetchSlug(context: context, slug: slug, present: { controller in
            presentImpl?(controller)
        }, completion: { gift in
            onPick(gift)
        }))
    }

    let arguments = AyuNftSearchArguments(updateQuery: { value in
        number = value
        changed()
    }, submit: {
        findNumber()
    }, openPayload: { _ in
        findNumber()
    }, openRow: { index in
        guard index >= 0, index < items.count else {
            return
        }
        onPick(items[index])
    }, loadMore: {
        resaleContext.loadMore()
    })

    let signal = combineLatest(context.sharedContext.presentationData, updates.get())
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, AyuNftSearchArguments)) in
        let locale = data.strings.baseLanguageCode
        var entries: [AyuNftSearchEntry] = []
        entries.append(.input(id: 0, section: .search, text: number, placeholder: i18n("Ayu.NftSearch.NumberPlaceholder", locale), isNumber: true))
        if let value = parsedNumber() {
            entries.append(.action(id: 1, section: .search, title: i18n("Ayu.NftSearch.FindNumber", locale, title + " #\(value)"), payload: ""))
        }
        entries.append(.footer(id: 2, section: .search, text: i18n("Ayu.NftSearch.NumberInfo", locale)))
        entries.append(.header(id: 10, section: .results, text: i18n("Ayu.NftSearch.ForSale", locale)))
        if items.isEmpty {
            entries.append(.status(id: 11, section: .results, text: loading ? i18n("Ayu.ProfileExtras.Loading", locale) : i18n("Ayu.NftSearch.Empty", locale)))
        }
        for (index, item) in items.prefix(300).enumerated() {
            entries.append(.row(id: 100 + index, section: .results, index: index, title: "\(item.title) #\(item.number)", label: ayuNftModelName(item)))
        }
        if canLoadMore && !items.isEmpty && items.count < 300 {
            entries.append(.more(id: 1000, section: .results, title: i18n("Ayu.NftSearch.LoadMore", locale)))
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, animateChanges: false)
        return (state, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.didDisappear = { _ in
        let _ = holder
    }
    presentImpl = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    return controller
}
