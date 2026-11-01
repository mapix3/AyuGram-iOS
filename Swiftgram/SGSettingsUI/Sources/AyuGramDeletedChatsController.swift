import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGStrings

private final class DeletedChatsArguments {
    let context: AccountContext
    let open: (AyuGramDeletedChat, EnginePeer?) -> Void
    let search: (String) -> Void

    init(context: AccountContext, open: @escaping (AyuGramDeletedChat, EnginePeer?) -> Void, search: @escaping (String) -> Void) {
        self.context = context
        self.open = open
        self.search = search
    }
}

private enum DeletedChatsEntry: ItemListNodeEntry {
    case search(Int, String, String)
    case header(Int, Int32, String)
    case chat(Int, Int32, AyuGramDeletedChat, EnginePeer?, Int, String)
    case info(Int, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .search:
            return 0
        case let .header(_, section, _), let .chat(_, section, _, _, _, _), let .info(_, section, _):
            return section
        }
    }
    var stableId: Int {
        switch self {
        case let .search(id, _, _), let .header(id, _, _), let .chat(id, _, _, _, _, _), let .info(id, _, _): return id
        }
    }
    static func < (lhs: DeletedChatsEntry, rhs: DeletedChatsEntry) -> Bool { lhs.stableId < rhs.stableId }
    static func == (lhs: DeletedChatsEntry, rhs: DeletedChatsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.search(lId, lText, lPlaceholder), .search(rId, rText, rPlaceholder)):
            return lId == rId && lText == rText && lPlaceholder == rPlaceholder
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.chat(lId, lSection, lChat, lPeer, lCount, lDate), .chat(rId, rSection, rChat, rPeer, rCount, rDate)):
            return lId == rId && lSection == rSection && lChat == rChat && lPeer == rPeer && lCount == rCount && lDate == rDate
        case let (.info(lId, lSection, lText), .info(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        default:
            return false
        }
    }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! DeletedChatsArguments
        switch self {
        case let .search(_, text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), returnKeyType: .search, clearType: .always, sectionId: self.section, textUpdated: { value in
                args.search(value)
            }, action: {}, dismissKeyboardOnEnter: true)
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .chat(_, _, chat, peer, count, detail):
            let title = peer?.debugDisplayTitle ?? chat.title
            return ItemListDisclosureItem(presentationData: presentationData, context: args.context, iconPeer: peer, title: title.isEmpty ? "\(chat.peerId)" : title, label: "\(count)", additionalDetailLabel: detail, sectionId: self.section, style: .blocks, action: { args.open(chat, peer) })
        case let .info(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private enum DeletedChatsKind: Int32 {
    case user = 1
    case group = 2
    case channel = 3
}

private func ayuGramDeletedChatKind(peerId: Int64, peer: EnginePeer?) -> DeletedChatsKind {
    if let peer {
        switch peer {
        case .user, .secretChat:
            return .user
        case .legacyGroup:
            return .group
        case let .channel(channel):
            if case .broadcast = channel.info {
                return .channel
            }
            return .group
        }
    }
    let id = EnginePeer.Id(peerId)
    if id.namespace == Namespaces.Peer.CloudUser {
        return .user
    }
    if id.namespace == Namespaces.Peer.CloudGroup {
        return .group
    }
    return .channel
}

private typealias DeletedChatsItem = (chat: AyuGramDeletedChat, peer: EnginePeer?, count: Int, texts: [(text: String, key: String)])

/// Chats whose whole history was deleted, with what Save Deleted Messages kept of them:
/// open a chat to read it, save it as an archive, or remove it from the list. The list of
/// kept messages is grouped into private chats, groups and channels and can be searched
/// by chat name, username, author or text.
func ayuGramDeletedChatsController(context: AccountContext, onlyPeers: Set<Int64>? = nil, keptMessages: Bool = false) -> ViewController {
    var openImpl: ((AyuGramDeletedChat, EnginePeer?) -> Void)?
    let query = ValuePromise<String>("", ignoreRepeated: true)
    let arguments = DeletedChatsArguments(context: context, open: { chat, peer in openImpl?(chat, peer) }, search: { value in query.set(value) })
    let reload = ValuePromise<Int>(0, ignoreRepeated: false)
    let source: Signal<[DeletedChatsItem], NoError>
    if keptMessages {
        source = reload.get()
        |> mapToSignal { _ -> Signal<[DeletedChatsItem], NoError> in
            return context.engine.ayuGramKeptDeletedChats()
            |> map { items -> [DeletedChatsItem] in
                return items.map { item -> DeletedChatsItem in
                    return (chat: AyuGramDeletedChat(peerId: item.peerId.toInt64(), title: item.peer?.debugDisplayTitle ?? "", deletedAt: item.deletedAt), peer: item.peer, count: item.count, texts: item.texts)
                }
            }
        }
    } else {
        source = context.engine.ayuGramDeletedChats()
        |> map { chats -> [DeletedChatsItem] in
            return chats.filter { onlyPeers?.contains($0.chat.peerId) ?? true }.map { item -> DeletedChatsItem in
                return (chat: item.chat, peer: item.peer, count: item.count, texts: [])
            }
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, source, query.get())
    |> deliverOnMainQueue
    |> map { presentationData, chats, query -> (ItemListControllerState, (ItemListNodeState, DeletedChatsArguments)) in
        let locale = presentationData.strings.baseLanguageCode
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: "")
        var entries: [DeletedChatsEntry] = []
        if keptMessages {
            entries.append(.search(0, query, i18n("Ayu.DeletedSearch", locale)))
        }
        var grouped: [DeletedChatsKind: [(DeletedChatsItem, String)]] = [:]
        for item in chats {
            var detail = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.chat.deletedAt)))
            if !needle.isEmpty {
                let title = (item.peer?.debugDisplayTitle ?? item.chat.title).lowercased()
                let username = (item.peer?.addressName ?? "").lowercased()
                if !title.contains(needle) && !username.contains(needle) {
                    guard let match = item.texts.first(where: { $0.key.contains(needle) }) else {
                        continue
                    }
                    detail = match.text
                }
            }
            grouped[ayuGramDeletedChatKind(peerId: item.chat.peerId, peer: item.peer), default: []].append((item, detail))
        }
        let headers: [DeletedChatsKind: String] = [.user: "Ayu.DeletedSectionUsers", .group: "Ayu.DeletedSectionGroups", .channel: "Ayu.DeletedSectionChannels"]
        for kind in [DeletedChatsKind.user, .group, .channel] {
            guard let items = grouped[kind], !items.isEmpty else { continue }
            let base = Int(kind.rawValue) * 100000
            if keptMessages {
                entries.append(.header(base, kind.rawValue, i18n(headers[kind] ?? "", locale)))
            }
            for (index, element) in items.enumerated() {
                entries.append(.chat(base + 1 + index, kind.rawValue, element.0.chat, element.0.peer, element.0.count, element.1))
            }
        }
        if keptMessages {
            if !needle.isEmpty && grouped.isEmpty {
                entries.append(.info(900000, 4, i18n("Ayu.DeletedSearchEmpty", locale)))
            } else {
                entries.append(.info(900000, 4, i18n(chats.isEmpty ? "Ayu.ViewDeletedEmpty" : "Ayu.ViewDeletedInfo", locale)))
            }
        } else {
            entries.append(.info(900000, 4, i18n("Ayu.DeletedChatsInfo", locale)))
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n(keptMessages ? "Ayu.ViewDeleted" : "Ayu.DeletedChats", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    openImpl = { [weak controller] chat, peer in
        guard let controller else { return }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let locale = data.strings.baseLanguageCode
        let peerId = EnginePeer.Id(chat.peerId)
        let sheet = ActionSheetController(presentationData: data)
        var items: [ActionSheetItem] = []
        if peer != nil {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.HistoryOpenChat", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                context.sharedContext.navigateToChat(accountId: context.account.id, peerId: peerId, messageId: nil)
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n("Ayu.ViewDeleted", locale), color: .accent, action: { [weak sheet, weak controller] in
            sheet?.dismissAnimated()
            (controller?.navigationController as? NavigationController)?.pushViewController(ayuGramHistoryController(context: context, deletedIn: peerId))
        }))
        items.append(ActionSheetButtonItem(title: i18n("Ayu.DeletedChatSave", locale), color: .accent, action: { [weak sheet, weak controller] in
            sheet?.dismissAnimated()
            let _ = (context.engine.ayuGramDeletedChatMessages(peerId: peerId) |> deliverOnMainQueue).startStandalone(next: { messages in
                guard let controller else { return }
                let title = peer?.debugDisplayTitle ?? chat.title
                ayuGramExportChatArchive(context: context, peerId: peerId, title: title, messages: messages, present: { [weak controller] next in
                    controller?.present(next, in: .window(.root))
                })
            })
        }))
        if !keptMessages {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.DeletedChatRemove", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                let _ = context.engine.ayuGramForgetDeletedChat(peerId: peerId, deleteMessages: false).startStandalone()
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n("Ayu.DeletedChatDelete", locale), color: .destructive, action: { [weak sheet] in
            sheet?.dismissAnimated()
            let _ = (context.engine.ayuGramForgetDeletedChat(peerId: peerId, deleteMessages: true) |> deliverOnMainQueue).startStandalone(completed: {
                reload.set(0)
            })
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        controller.present(sheet, in: .window(.root))
    }
    return controller
}
