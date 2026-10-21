import Foundation
import UIKit
import AVKit
import QuickLook
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGItemListUI
import SGStrings
import ConvertOpusToAAC

private enum HistorySection: Int32, SGItemListSection { case summary, deletedChats, entries, options, chats, actions }
private enum HistoryAction: Hashable { case clear, selectChats, deletedChats, chatOptions(Int64), media(String, String), author(Int64), chat(Int64, Int32), filter(Int), menu(Int64, Int32, String, Int32, String?, String) }
private typealias HistorySettingsEntry = SGItemListUIEntry<HistorySection, Int, Int, Int, Int, HistoryAction>
private typealias HistoryArguments = SGItemListArguments<Int, Int, Int, Int, HistoryAction>

private enum HistoryEntry: ItemListNodeEntry {
    case setting(HistorySettingsEntry)
    case summary(AyuGramHistorySummary)
    case empty(Int, String, Bool)
    case day(Int, String, Int)
    case record(Int, AyuGramHistoryEntry, EnginePeer?)
    case chat(Int, EnginePeer, Int)
    case deletedChats(Int, String, Int)
    var section: ItemListSectionId {
        switch self {
        case let .setting(value): return value.section
        case .summary: return HistorySection.summary.rawValue
        case .empty, .day, .record: return HistorySection.entries.rawValue
        case .chat: return HistorySection.chats.rawValue
        case .deletedChats: return HistorySection.deletedChats.rawValue
        }
    }
    var stableId: Int {
        switch self {
        case let .setting(value): return value.stableId
        case .summary: return 0
        case let .empty(id, _, _), let .day(id, _, _), let .record(id, _, _), let .chat(id, _, _), let .deletedChats(id, _, _): return id
        }
    }
    static func < (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool { lhs.stableId < rhs.stableId }
    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! HistoryArguments
        switch self {
        case let .setting(value): return value.item(presentationData: presentationData, arguments: arguments)
        case let .summary(summary):
            return AyuGramHistoryHeroItem(data: presentationData, summary: summary, sectionId: section, select: { args.action(.filter($0)) })
        case let .empty(_, text, canAddChats):
            return AyuGramHistoryEmptyItem(data: presentationData, text: text, buttonTitle: canAddChats ? presentationData.strings.ChatListFolder_AddChats : nil, sectionId: section, action: { args.action(.selectChats) })
        case let .day(_, text, count):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, accessoryText: ItemListSectionHeaderAccessoryText(value: "\(count)", color: .generic), sectionId: section)
        case let .record(_, record, peer):
            return AyuGramHistoryCardItem(context: args.context, data: presentationData, record: record, peer: peer, sectionId: section, openAuthor: { if let id = record.authorId { args.action(.author(id)) } }, openChat: { args.action(.chat(record.peerId, record.messageId)) }, openMedia: { if let name = record.photoFileName { args.action(.media(name, record.mediaKind ?? "photo")) } }, openMenu: { args.action(.menu(record.peerId, record.messageId, record.event, record.timestamp, record.photoFileName, record.mediaKind ?? "photo")) })
        case let .chat(_, peer, count):
            return ItemListDisclosureItem(presentationData: presentationData, context: args.context, iconPeer: peer, title: peer.debugDisplayTitle, label: count > 0 ? "\(count)" : "", sectionId: section, style: .blocks, action: { args.action(.chatOptions(peer.id.toInt64())) })
        case let .deletedChats(_, title, count):
            return ItemListDisclosureItem(presentationData: presentationData, icon: UIImage(systemName: "trash.circle.fill")?.withTintColor(presentationData.theme.list.itemDestructiveColor, renderingMode: .alwaysOriginal), title: title, label: "\(count)", sectionId: section, style: .blocks, action: { args.action(.deletedChats) })
        }
    }
}

private func historyDayTitle(_ timestamp: Int32, locale: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: locale)
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    formatter.doesRelativeDateFormatting = true
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

public func ayuGramHistoryController(context: AccountContext, messageId: MessageId? = nil) -> ViewController {
    let records = Promise<[AyuGramHistoryEntry]>()
    let policy = Promise<(AyuGramHistoryPolicy, [EnginePeer])>()
    let filter = ValuePromise<Int>(0, ignoreRepeated: true)
    if let messageId {
        records.set(context.engine.ayuGramMessageVersions(messageId: messageId))
    } else {
        records.set(context.engine.ayuGramMessageHistory())
    }
    policy.set(context.engine.ayuGramHistoryPolicy())
    var actionImpl: ((HistoryAction) -> Void)?
    let arguments = HistoryArguments(context: context, setBoolValue: { _, enabled in
        let _ = (context.engine.ayuGramHistoryPolicy() |> take(1)).startStandalone(next: { current, _ in
            var updated = current
            updated.savePhotos = enabled
            policy.set(context.engine.ayuGramSetHistoryPolicy(updated) |> mapToSignal { context.engine.ayuGramHistoryPolicy() })
        })
    }, action: { actionImpl?($0) })
    // Authors' (or, without an author, the chats') current peers for real avatars.
    let peers = records.get()
    |> mapToSignal { records -> Signal<[Int64: EnginePeer], NoError> in
        let ids = Set(records.map { $0.authorId ?? $0.peerId })
        return context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId($0)) }))
        |> map { result -> [Int64: EnginePeer] in
            var peers: [Int64: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    peers[id.toInt64()] = peer
                }
            }
            return peers
        }
    }
    let deletedChats: Signal<Int, NoError> = messageId == nil ? (context.engine.ayuGramDeletedChats() |> map { $0.count }) : .single(0)
    let signal = combineLatest(context.sharedContext.presentationData, records.get(), policy.get(), filter.get(), peers, deletedChats)
    |> deliverOnMainQueue
    |> map { presentationData, records, policyData, filterValue, peersById, deletedChatCount -> (ItemListControllerState, (ItemListNodeState, HistoryArguments)) in
        let locale = presentationData.strings.baseLanguageCode
        let records = records.filter { messageId == nil || ($0.peerId == messageId?.peerId.toInt64() && $0.messageId == messageId?.id) }
        let (current, peers) = policyData
        var entries: [HistoryEntry] = []
        let visible: [AyuGramHistoryEntry]
        if messageId == nil {
            let deleted = records.filter { $0.event != "edited" }.count
            entries.append(.summary(AyuGramHistorySummary(total: records.count, deleted: deleted, edited: records.count - deleted, filter: filterValue)))
            if deletedChatCount > 0 {
                entries.append(.deletedChats(2, i18n("Ayu.DeletedChats", locale), deletedChatCount))
            }
            visible = records.filter { filterValue == 0 || (filterValue == 1) == ($0.event != "edited") }
        } else {
            visible = records
        }
        if visible.isEmpty {
            let noChats = messageId == nil && current.selectedChats.isEmpty
            entries.append(.empty(1, i18n(noChats ? "Ayu.HistoryNoChats" : "Ayu.HistoryEmptyInfo", locale), noChats))
        }
        // Records arrive newest first; group them under one header per calendar day.
        let calendar = Calendar.current
        var index = 0
        while index < visible.count {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(visible[index].timestamp)))
            var next = index
            while next < visible.count && calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(visible[next].timestamp))) == day { next += 1 }
            entries.append(.day(10 + index * 2, historyDayTitle(visible[index].timestamp, locale: locale), next - index))
            for position in index ..< next {
                entries.append(.record(10 + position * 2 + 1, visible[position], peersById[visible[position].authorId ?? visible[position].peerId]))
            }
            index = next
        }
        if messageId == nil {
            let counts = Dictionary(grouping: records, by: { $0.peerId }).mapValues { $0.count }
            let settings: [HistorySettingsEntry] = [
                .header(id: 100000, section: .options, text: presentationData.strings.Settings_Title, badge: nil),
                .toggle(id: 100001, section: .options, settingName: 0, value: current.savePhotos, text: i18n("Ayu.SaveMedia", locale), enabled: true),
                .notice(id: 100002, section: .options, text: i18n("Ayu.HistoryInfo", locale)),
                .header(id: 100003, section: .chats, text: presentationData.strings.ChatListFolder_IncludeChatsTitle, badge: nil),
                .action(id: 100004, section: .chats, actionType: .selectChats, text: presentationData.strings.ChatListFolder_AddChats, kind: .generic)
            ]
            entries.append(contentsOf: settings.map(HistoryEntry.setting))
            for (position, peer) in peers.enumerated() {
                entries.append(.chat(100010 + position, peer, counts[peer.id.toInt64()] ?? 0))
            }
            if peers.isEmpty {
                entries.append(.setting(.notice(id: 199999, section: .chats, text: i18n("Ayu.HistoryNoChats", locale))))
            }
            if !records.isEmpty {
                entries.append(.setting(.action(id: 200000, section: .actions, actionType: .clear, text: i18n("Ayu.ClearHistory", locale), kind: .destructive)))
            }
        }
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Ayu.History", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    actionImpl = { [weak controller] action in
        guard let controller else { return }
        let data = context.sharedContext.currentPresentationData.with { $0 }
        switch action {
        case .selectChats:
            let _ = (context.engine.ayuGramHistoryPolicy() |> take(1) |> deliverOnMainQueue).startStandalone(next: { current, _ in
                // selectedChats alone preselects; passing the peers again toggles each chat a second time and duplicates its token.
                let selection = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(.init(title: data.strings.ChatListFolder_IncludeChatsTitle, searchPlaceholder: data.strings.ChatListFilter_AddChatsSearchPlaceholder, selectedChats: Set(current.selectedChats.map(PeerId.init)), additionalCategories: nil, chatListFilters: nil)), filters: [], alwaysEnabled: true))
                selection.navigationPresentation = .modal
                let _ = (selection.result |> take(1) |> deliverOnMainQueue).startStandalone(next: { [weak selection] result in
                    guard case let .result(ids, _) = result else { selection?.dismiss(); return }
                    var updated = current
                    updated.selectedChats = ids.compactMap { if case let .peer(id) = $0 { return id.toInt64() }; return nil }
                    policy.set(context.engine.ayuGramSetHistoryPolicy(updated) |> mapToSignal { context.engine.ayuGramHistoryPolicy() })
                    selection?.dismiss()
                })
                (controller.navigationController as? NavigationController)?.pushViewController(selection)
            })
        case let .chatOptions(id):
            let sheet = ActionSheetController(presentationData: data)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [
                    ActionSheetButtonItem(title: i18n("Ayu.HistoryOpenChat", data.strings.baseLanguageCode), color: .accent, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        context.sharedContext.navigateToChat(accountId: context.account.id, peerId: PeerId(id), messageId: nil)
                    }),
                    ActionSheetButtonItem(title: i18n("Ayu.HistoryStopSaving", data.strings.baseLanguageCode), color: .destructive, action: { [weak sheet] in
                        sheet?.dismissAnimated()
                        let _ = (context.engine.ayuGramHistoryPolicy() |> take(1)).startStandalone(next: { current, _ in
                            var updated = current
                            updated.selectedChats.removeAll { $0 == id }
                            policy.set(context.engine.ayuGramSetHistoryPolicy(updated) |> mapToSignal { context.engine.ayuGramHistoryPolicy() })
                        })
                    })
                ]),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            controller.present(sheet, in: .window(.root))
        case .deletedChats:
            (controller.navigationController as? NavigationController)?.pushViewController(ayuGramDeletedChatsController(context: context))
        case let .filter(value):
            filter.set(value)
        case let .menu(peerId, messageId, event, timestamp, fileName, kind):
            let locale = data.strings.baseLanguageCode
            let sheet = ActionSheetController(presentationData: data)
            var items: [ActionSheetItem] = []
            // Voice and round messages are stored as Opus, which most apps cannot open; export them as M4A.
            if (kind == "voice" || kind == "round"), let fileName, let url = context.engine.ayuGramArchivedPhotoURL(fileName), FileManager.default.fileExists(atPath: url.path) {
                items.append(ActionSheetButtonItem(title: i18n("Ayu.HistorySaveAudio", locale), color: .accent, action: { [weak sheet, weak controller] in
                    sheet?.dismissAnimated()
                    let temp: () -> String = { NSTemporaryDirectory() + "ayu-voice-\(Int64.random(in: 0 ... Int64.max)).m4a" }
                    let _ = (convertOpusToAAC(sourcePath: url.path, allocateTempFile: temp) |> deliverOnMainQueue).startStandalone(next: { outputPath in
                        guard let controller else { return }
                        let shareURL: URL
                        if let outputPath {
                            shareURL = URL(fileURLWithPath: outputPath)
                        } else {
                            shareURL = url
                        }
                        let activity = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
                        activity.popoverPresentationController?.sourceView = controller.view
                        controller.present(activity, animated: true)
                    })
                }))
            }
            items.append(ActionSheetButtonItem(title: i18n("Ayu.HistoryDeleteEntry", locale), color: .destructive, action: { [weak sheet] in
                sheet?.dismissAnimated()
                records.set(context.engine.ayuGramDeleteHistoryEntry(peerId: peerId, messageId: messageId, event: event, timestamp: timestamp) |> mapToSignal { context.engine.ayuGramMessageHistory() })
            }))
            sheet.setItemGroups([
                ActionSheetItemGroup(items: items),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            controller.present(sheet, in: .window(.root))
        case let .author(id):
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId(id))) |> deliverOnMainQueue).startStandalone(next: { peer in
                if let peer, let profile = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
                    (controller.navigationController as? NavigationController)?.pushViewController(profile)
                }
            })
        case let .chat(peer, id):
            context.sharedContext.navigateToChat(accountId: context.account.id, peerId: PeerId(peer), messageId: MessageId(peerId: PeerId(peer), namespace: Namespaces.Message.Cloud, id: id))
        case let .media(name, kind):
            guard let url = context.engine.ayuGramArchivedPhotoURL(name), FileManager.default.fileExists(atPath: url.path) else { return }
            if kind == "video" || kind == "round" || (kind == "gif" && url.pathExtension.lowercased() != "gif") {
                let video = AVPlayerViewController()
                video.player = AVPlayer(url: url)
                controller.present(video, animated: true) { video.player?.play() }
                return
            }
            guard let image = ayuGramArchivedImage(url, maximumPixels: min(4096, Int(max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale))) else {
                controller.present(UINavigationController(rootViewController: AyuArchiveDocumentController(url: url, strings: data.strings)), animated: true)
                return
            }
            let photo = AyuArchivePhotoController(image: image, url: url, strings: data.strings)
            controller.present(UINavigationController(rootViewController: photo), animated: true)
        case .clear:
            let sheet = ActionSheetController(presentationData: data)
            sheet.setItemGroups([
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: i18n("Ayu.ClearHistory", data.strings.baseLanguageCode), color: .destructive, action: { [weak sheet] in
                    sheet?.dismissAnimated()
                    records.set(context.engine.ayuGramClearMessageHistory() |> mapToSignal { context.engine.ayuGramMessageHistory() })
                })]),
                ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
            ])
            controller.present(sheet, in: .window(.root))
        }
    }
    return controller
}

private final class AyuArchivePhotoController: UIViewController {
    private let image: UIImage
    private let url: URL
    private let strings: PresentationStrings
    init(image: UIImage, url: URL, strings: PresentationStrings) {
        self.image = image
        self.url = url
        self.strings = strings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        NSLayoutConstraint.activate([imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor), imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor), imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)])
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: strings.Common_Close, style: .plain, target: self, action: #selector(closePhoto))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(sharePhoto))
    }
    @objc private func closePhoto() { dismiss(animated: true) }
    @objc private func sharePhoto() {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(activity, animated: true)
    }
}

private final class AyuArchiveDocumentController: QLPreviewController, QLPreviewControllerDataSource {
    private let url: URL
    private let strings: PresentationStrings
    init(url: URL, strings: PresentationStrings) {
        self.url = url
        self.strings = strings
        super.init(nibName: nil, bundle: nil)
        self.dataSource = self
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: strings.Common_Close, style: .plain, target: self, action: #selector(closePreview))
    }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    @objc private func closePreview() { dismiss(animated: true) }
}
