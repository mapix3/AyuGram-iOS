import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import PromptUI
import UndoUI
import SGStrings

private final class AyuGramPluginsArguments {
    let market: () -> Void
    let toggle: (String, Bool) -> Void
    let open: (AyuGramPluginInfo) -> Void
    let installFile: () -> Void
    let installURL: () -> Void

    init(market: @escaping () -> Void, toggle: @escaping (String, Bool) -> Void, open: @escaping (AyuGramPluginInfo) -> Void, installFile: @escaping () -> Void, installURL: @escaping () -> Void) {
        self.market = market
        self.toggle = toggle
        self.open = open
        self.installFile = installFile
        self.installURL = installURL
    }
}

private enum AyuGramPluginsEntry: ItemListNodeEntry {
    case market(Int, String, String)
    case marketInfo(Int, String)
    case header(Int, String)
    case plugin(Int, AyuGramPluginInfo)
    case empty(Int, String)
    case installFile(Int, String)
    case installURL(Int, String)
    case footer(Int, String)

    var section: ItemListSectionId {
        switch self {
        case .market, .marketInfo:
            return 0
        case .header, .plugin, .empty:
            return 1
        case .installFile, .installURL, .footer:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case let .market(id, _, _), let .marketInfo(id, _), let .header(id, _), let .plugin(id, _), let .empty(id, _), let .installFile(id, _), let .installURL(id, _), let .footer(id, _):
            return id
        }
    }

    static func < (lhs: AyuGramPluginsEntry, rhs: AyuGramPluginsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func == (lhs: AyuGramPluginsEntry, rhs: AyuGramPluginsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.market(lId, lText, lLabel), .market(rId, rText, rLabel)):
            return lId == rId && lText == rText && lLabel == rLabel
        case let (.marketInfo(lId, lText), .marketInfo(rId, rText)):
            return lId == rId && lText == rText
        case let (.header(lId, lText), .header(rId, rText)):
            return lId == rId && lText == rText
        case let (.plugin(lId, lInfo), .plugin(rId, rInfo)):
            return lId == rId && lInfo == rInfo
        case let (.empty(lId, lText), .empty(rId, rText)):
            return lId == rId && lText == rText
        case let (.installFile(lId, lText), .installFile(rId, rText)):
            return lId == rId && lText == rText
        case let (.installURL(lId, lText), .installURL(rId, rText)):
            return lId == rId && lText == rText
        case let (.footer(lId, lText), .footer(rId, rText)):
            return lId == rId && lText == rText
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! AyuGramPluginsArguments
        switch self {
        case let .market(_, text, label):
            return ItemListDisclosureItem(presentationData: presentationData, icon: UIImage(systemName: "bag.fill")?.withTintColor(presentationData.theme.list.itemAccentColor, renderingMode: .alwaysOriginal), title: text, label: label, sectionId: self.section, style: .blocks, action: {
                args.market()
            })
        case let .marketInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .plugin(_, info):
            let detail = ([info.version] + (info.author.isEmpty ? [] : [info.author])).joined(separator: " · ")
            return ItemListSwitchItem(presentationData: presentationData, title: info.name, text: detail, value: info.enabled, maximumNumberOfLines: 1, sectionId: self.section, style: .blocks, updated: { value in
                args.toggle(info.id, value)
            }, action: {
                args.open(info)
            })
        case let .empty(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .installFile(_, text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.installFile()
            })
        case let .installURL(_, text):
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.installURL()
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

final class AyuGramPluginPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let picked: (URL) -> Void
    var keepAlive: AyuGramPluginPickerDelegate?

    init(picked: @escaping (URL) -> Void) {
        self.picked = picked
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            self.picked(url)
        }
        self.keepAlive = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.keepAlive = nil
    }
}

private func ayuGramPluginPermissionTitle(_ permission: String, locale: String) -> String {
    return i18n("Ayu.Plugins.Perm." + permission, locale)
}

public func ayuGramPresentPluginInstall(context: AccountContext, package: AyuGramPluginPackage, notice: String? = nil, present: @escaping (ViewController) -> Void, completion: (() -> Void)? = nil) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    var lines: [String] = []
    lines.append(package.info.name + " " + package.info.version + (package.info.author.isEmpty ? "" : " · " + package.info.author))
    if !package.info.description.isEmpty {
        lines.append(package.info.description)
    }
    if package.info.permissions.isEmpty {
        lines.append("\n" + i18n("Ayu.Plugins.NoPermissions", locale))
    } else {
        lines.append("\n" + i18n("Ayu.Plugins.Requests", locale))
        for permission in package.info.permissions {
            lines.append("• " + ayuGramPluginPermissionTitle(permission, locale: locale))
        }
    }
    if !package.info.domains.isEmpty {
        lines.append("\n" + i18n("Ayu.Plugins.Domains", locale) + " " + package.info.domains.joined(separator: ", "))
    }
    if let notice, !notice.isEmpty {
        lines.append("\n" + notice)
    }
    lines.append("\n" + i18n("Ayu.Plugins.Warning", locale))
    let exists = AyuGramPluginManager.shared.plugins.contains(where: { $0.id == package.info.id })
    present(textAlertController(context: context, title: i18n(exists ? "Ayu.Plugins.UpdateTitle" : "Ayu.Plugins.InstallTitle", locale), text: lines.joined(separator: "\n"), actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .defaultAction, title: i18n(exists ? "Ayu.Plugins.Update" : "Ayu.Plugins.Install", locale), action: {
            AyuGramPluginManager.shared.install(package)
            completion?()
        })
    ]))
}

public func ayuGramInstallPlugin(context: AccountContext, fileURL: URL, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let locale = presentationData.strings.baseLanguageCode
    do {
        let package = try ayuGramReadPluginPackage(at: fileURL)
        guard let data = try? Data(contentsOf: fileURL), data.count <= 2 * 1024 * 1024 else {
            ayuGramPresentPluginInstall(context: context, package: package, present: present)
            return
        }
        AyuGramMarketClient.shared.scan(data: data, name: fileURL.lastPathComponent, completion: { scan in
            ayuGramPresentPluginInstall(context: context, package: package, notice: scan.map { ayuGramMarketScanText($0, locale: locale) }, present: present)
        })
    } catch {
        present(textAlertController(context: context, title: nil, text: i18n("Ayu.Plugins.BadFile", locale), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }
}

public func ayuGramIsPluginFileName(_ name: String) -> Bool {
    let lower = name.lowercased()
    return lower.hasSuffix(".js") || lower.hasSuffix(".plugin") || lower.hasSuffix(".wgplugin")
}

public func ayuGramInstallPluginFromMessage(context: AccountContext, message: Message, present: @escaping (ViewController) -> Void) {
    guard let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
        return
    }
    let name = file.fileName ?? "plugin.js"
    let _ = (context.account.postbox.mediaBox.resourceData(file.resource, option: .complete(waitUntilFetchStatus: false))
    |> filter { $0.complete }
    |> take(1)
    |> deliverOnMainQueue).startStandalone(next: { data in
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
        try? FileManager.default.removeItem(at: target)
        guard (try? FileManager.default.copyItem(at: URL(fileURLWithPath: data.path), to: target)) != nil else {
            return
        }
        ayuGramInstallPlugin(context: context, fileURL: target, present: present)
    })
    let _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .file, reference: .media(media: .message(message: MessageReference(message), media: file), resource: file.resource)).startStandalone()
}

public func ayuGramPluginsController(context: AccountContext) -> ViewController {
    var presentImpl: ((ViewController) -> Void)?
    var openImpl: ((AyuGramPluginInfo) -> Void)?
    var installFileImpl: (() -> Void)?
    var installURLImpl: (() -> Void)?
    var marketImpl: (() -> Void)?
    let arguments = AyuGramPluginsArguments(market: {
        marketImpl?()
    }, toggle: { id, value in
        AyuGramPluginManager.shared.setEnabled(id, value)
    }, open: { info in
        openImpl?(info)
    }, installFile: {
        installFileImpl?()
    }, installURL: {
        installURLImpl?()
    })
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramPluginManager.didChange, object: nil, queue: .main, using: { _ in
            subscriber.putNext(0)
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let locale = presentationData.strings.baseLanguageCode
        var entries: [AyuGramPluginsEntry] = []
        entries.append(.market(-2, i18n("Ayu.Market.Title", locale), ""))
        entries.append(.marketInfo(-1, i18n("Ayu.Market.EntryInfo", locale)))
        entries.append(.header(0, i18n("Ayu.Plugins.Installed", locale)))
        let plugins = AyuGramPluginManager.shared.plugins.sorted(by: { $0.installedAt < $1.installedAt })
        if plugins.isEmpty {
            entries.append(.empty(1, i18n("Ayu.Plugins.Empty", locale)))
        }
        for (index, plugin) in plugins.enumerated() {
            entries.append(.plugin(10 + index, plugin))
        }
        entries.append(.installFile(1000, i18n("Ayu.Plugins.FromFile", locale)))
        entries.append(.installURL(1001, i18n("Ayu.Plugins.FromURL", locale)))
        entries.append(.footer(1002, i18n("Ayu.Plugins.Footer", locale)))
        let state = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("Ayu.Plugins.Title", locale)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentImpl = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    marketImpl = { [weak controller] in
        (controller?.navigationController as? NavigationController)?.pushViewController(ayuGramMarketController(context: context))
    }
    installFileImpl = { [weak controller] in
        guard let controller else {
            return
        }
        var types: [UTType] = [.javaScript, .zip, .plainText]
        if let plugin = UTType(filenameExtension: "plugin") {
            types.append(plugin)
        }
        types.append(.data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        let delegate = AyuGramPluginPickerDelegate(picked: { url in
            ayuGramInstallPlugin(context: context, fileURL: url, present: { next in
                presentImpl?(next)
            })
        })
        delegate.keepAlive = delegate
        picker.delegate = delegate
        controller.view.window?.rootViewController?.present(picker, animated: true)
    }
    installURLImpl = {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let locale = presentationData.strings.baseLanguageCode
        presentImpl?(promptController(context: context, text: i18n("Ayu.Plugins.URLPrompt", locale), value: "", placeholder: "https://…/plugin.js", characterLimit: 1000, apply: { value in
            guard let value, let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https" else {
                return
            }
            URLSession.shared.downloadTask(with: url, completionHandler: { location, response, _ in
                DispatchQueue.main.async {
                    guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                        presentImpl?(textAlertController(context: context, title: nil, text: i18n("Ayu.Plugins.BadFile", locale), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
                        return
                    }
                    let name = url.lastPathComponent.isEmpty ? "plugin.js" : url.lastPathComponent
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + (ayuGramIsPluginFileName(name) ? name : name + ".js"))
                    try? FileManager.default.moveItem(at: location, to: target)
                    ayuGramInstallPlugin(context: context, fileURL: target, present: { next in
                        presentImpl?(next)
                    })
                }
            }).resume()
        }))
    }
    openImpl = { info in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let locale = presentationData.strings.baseLanguageCode
        let sheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        var description: [String] = [info.name + " " + info.version]
        if !info.description.isEmpty {
            description.append(info.description)
        }
        if !info.permissions.isEmpty {
            description.append(info.permissions.map { ayuGramPluginPermissionTitle($0, locale: locale) }.joined(separator: ", "))
        }
        items.append(ActionSheetTextItem(title: description.joined(separator: "\n")))
        items.append(ActionSheetButtonItem(title: i18n("Ayu.Plugins.Log", locale), color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            let log = AyuGramPluginManager.shared.log(info.id)
            let text = log.isEmpty ? i18n("Ayu.Plugins.LogEmpty", locale) : log.suffix(40).joined(separator: "\n")
            presentImpl?(textAlertController(context: context, title: info.name, text: text, actions: [
                TextAlertAction(type: .genericAction, title: i18n("Ayu.AICopy", locale), action: {
                    UIPasteboard.general.string = log.joined(separator: "\n")
                }),
                TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
            ]))
        }))
        if info.enabled {
            items.append(ActionSheetButtonItem(title: i18n("Ayu.Plugins.Reload", locale), color: .accent, action: { [weak sheet] in
                sheet?.dismissAnimated()
                AyuGramPluginManager.shared.reload(info.id)
            }))
        }
        items.append(ActionSheetButtonItem(title: i18n("Ayu.Plugins.Delete", locale), color: .destructive, action: { [weak sheet] in
            sheet?.dismissAnimated()
            AyuGramPluginManager.shared.remove(info.id)
        }))
        sheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
        ])
        presentImpl?(sheet)
    }
    return controller
}
