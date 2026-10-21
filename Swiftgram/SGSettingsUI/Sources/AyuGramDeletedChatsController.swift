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

    init(context: AccountContext, open: @escaping (AyuGramDeletedChat, EnginePeer?) -> Void) {
        self.context = context
        self.open = open
    }
}

private enum DeletedChatsEntry: ItemListNodeEntry {
    case chat(Int, AyuGramDeletedChat, EnginePeer?, Int, String)
    case info(Int, String)

    var section: ItemListSectionId { 0 }
    var stableId: Int {
        switch self {
        case let .chat(id, _, _, _, _), let .info(id, _): return id
        }
    }
    static func < (lhs: DeletedChatsEntry, rhs: DeletedChatsEntry) -> Bool { lhs.stableId < rhs.stableId }
    static func == (lhs: DeletedChatsEntry, rhs: DeletedChatsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.chat(lId, lChat, lPeer, lCount, lDate), .chat(rId, rChat, rPeer, rCount, rDate)):
            return lId == rId && lChat == rChat && lPeer == rPeer && lCount == rCount && lDate == rDate
        case let (.info(lId, lText), .info(rId, rText)):
            return lId == rId && lText == rText
        default:
            return false
        }
    }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! DeletedChatsArguments
        switch self {
        case let .chat(_, chat, peer, count, date):
            let title = peer?.debugDisplayTitle ?? chat.title
            return ItemListDisclosureItem(presentationData: presentationData, context: args.context, iconPeer: peer, title: title.isEmpty ? "\(chat.peerId)" : title, label: "\(count)", additionalDetailLabel: date, sectionId: self.section, style: .blocks, action: { args.open(chat, peer) })
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Chats whose whole history was deleted, with what Save Deleted Messages kept of them:
/// open a chat to read it, save it as an archive, or remove it from the list.
func ayuGramDeletedChatsController(context: AccountContext) -> ViewController {
    var openImpl: ((AyuGramDeletedChat, EnginePeer?) -> Void)?
    let arguments = DeletedChatsArguments(context: context, open: { chat, peer in openImpl?(chat, peer) })
    let signal = combineLatest(context.sharedContext.presentationData, context.engine.ayuGramDeletedChats())
    |> deliverOnMainQueue
    |> map { presentationData, chats -> (ItemListControllerState, (ItemListNodeState, DeletedChatsArguments)) in
        let locale = presentationData.strings.baseLanguageCode
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        var entries: [DeletedChatsEntry] = []
        for (index, item) in chats.enumerated() {
            entries.append(.chat(index, item.chat, item.peer, item.count, formatter.string(from: Date(timeIntervalSince1970: TimeInterval(item.chat.deletedAt)))))
        }
        entries.append(.info(100000, i18n("Ayu.DeletedChatsInfo", locale)))
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Ayu.DeletedChats", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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
        items.append(ActionSheetButtonItem(title: i18n("Ayu.DeletedChatRemove", locale), color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            let _ = context.engine.ayuGramForgetDeletedChat(peerId: peerId, deleteMessages: false).startStandalone()
        }))
        items.append(ActionSheetButtonItem(title: i18n("Ayu.DeletedChatDelete", locale), color: .destructive, action: { [weak sheet] in
            sheet?.dismissAnimated()
            let _ = context.engine.ayuGramForgetDeletedChat(peerId: peerId, deleteMessages: true).startStandalone()
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        controller.present(sheet, in: .window(.root))
    }
    return controller
}
