import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import SGStrings

private final class AyuGramDeletedChatContents: ChatCustomContentsProtocol {
    let kind: ChatCustomContentsKind = .hashTagSearch(publicPosts: false)

    private let viewPromise = Promise<(EngineRawMessageHistoryView, EngineViewUpdateType)>()
    private var messages: [EngineMessage] = []
    private var query: String = ""
    private var disposable: Disposable?

    var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in }

    var historyView: Signal<(EngineRawMessageHistoryView, EngineViewUpdateType), NoError> {
        return self.viewPromise.get()
    }

    var messageLimit: Int? {
        return nil
    }

    init(context: AccountContext, peerId: EnginePeer.Id) {
        self.disposable = (context.engine.ayuGramDeletedChatMessages(peerId: peerId)
        |> deliverOnMainQueue).start(next: { [weak self] messages in
            guard let self else {
                return
            }
            self.messages = messages
            self.push()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    private func push() {
        let needle = self.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [EngineMessage]
        if needle.isEmpty {
            filtered = self.messages
        } else {
            filtered = self.messages.filter { message in
                if message.text.lowercased().contains(needle) {
                    return true
                }
                if let author = message.author, author.debugDisplayTitle.lowercased().contains(needle) {
                    return true
                }
                return false
            }
        }
        let entries = filtered.map { message in
            return EngineRawMessageHistoryEntry(message: message._asMessage(), isRead: true, location: nil, monthLocation: nil, attributes: EngineRawMutableMessageHistoryEntryAttributes(authorIsContact: false))
        }
        let view = EngineRawMessageHistoryView(tag: nil, namespaces: .just(Set([Namespaces.Message.Cloud])), entries: entries, holeEarlier: false, holeLater: false, isLoading: false)
        self.viewPromise.set(.single((view, .Initial)))
    }

    func enqueueMessages(messages: [EnqueueMessage]) {
    }

    func deleteMessages(ids: [EngineMessage.Id]) {
    }

    func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
    }

    func quickReplyUpdateShortcut(value: String) {
    }

    func businessLinkUpdate(message: String, entities: [MessageTextEntity], title: String?) {
    }

    func loadMore() {
    }

    func hashtagSearchUpdate(query: String) {
        if self.query == query {
            return
        }
        self.query = query
        self.push()
    }
}

private final class AyuGramDeletedChatNode: ASDisplayNode, UITextFieldDelegate {
    private let chatController: ChatController
    private let stripNode: ASDisplayNode
    private let fieldBackgroundNode: ASDisplayNode
    private let field: UITextField
    private let queryUpdated: (String) -> Void
    private var placeholder: String

    init(chatController: ChatController, presentationData: PresentationData, placeholder: String, queryUpdated: @escaping (String) -> Void) {
        self.chatController = chatController
        self.queryUpdated = queryUpdated
        self.placeholder = placeholder
        self.stripNode = ASDisplayNode()
        self.fieldBackgroundNode = ASDisplayNode()
        self.fieldBackgroundNode.cornerRadius = 18.0
        self.fieldBackgroundNode.clipsToBounds = true
        self.field = UITextField()

        super.init()

        self.addSubnode(self.chatController.displayNode)
        self.chatController.displayNode.clipsToBounds = true
        self.addSubnode(self.stripNode)
        self.addSubnode(self.fieldBackgroundNode)
        self.updatePresentationData(presentationData)
    }

    override func didLoad() {
        super.didLoad()

        self.field.font = UIFont.systemFont(ofSize: 16.0)
        self.field.returnKeyType = .search
        self.field.autocorrectionType = .no
        self.field.autocapitalizationType = .none
        self.field.clearButtonMode = .whileEditing
        self.field.delegate = self
        self.field.addTarget(self, action: #selector(self.textChanged), for: .editingChanged)
        self.view.addSubview(self.field)
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        let theme = presentationData.theme
        self.backgroundColor = theme.list.blocksBackgroundColor
        self.stripNode.backgroundColor = theme.list.blocksBackgroundColor
        self.fieldBackgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
        self.field.textColor = theme.list.itemPrimaryTextColor
        self.field.tintColor = theme.list.itemAccentColor
        self.field.keyboardAppearance = theme.rootController.keyboardColor.keyboardAppearance
        self.field.attributedPlaceholder = NSAttributedString(string: self.placeholder, attributes: [.foregroundColor: theme.list.itemPlaceholderTextColor, .font: UIFont.systemFont(ofSize: 16.0)])
    }

    @objc private func textChanged() {
        self.queryUpdated(self.field.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let stripHeight: CGFloat = 52.0
        let sideInset: CGFloat = 16.0 + layout.safeInsets.left
        let stripFrame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: layout.size.width, height: navigationHeight + stripHeight))
        transition.updateFrame(node: self.stripNode, frame: stripFrame)
        let fieldBackgroundFrame = CGRect(origin: CGPoint(x: sideInset, y: navigationHeight + 8.0), size: CGSize(width: max(0.0, layout.size.width - sideInset - 16.0 - layout.safeInsets.right), height: 36.0))
        transition.updateFrame(node: self.fieldBackgroundNode, frame: fieldBackgroundFrame)
        self.field.frame = fieldBackgroundFrame.insetBy(dx: 12.0, dy: 0.0)

        let chatFrame = CGRect(origin: CGPoint(x: 0.0, y: stripFrame.maxY), size: CGSize(width: layout.size.width, height: max(0.0, layout.size.height - stripFrame.maxY)))
        transition.updateFrame(node: self.chatController.displayNode, frame: chatFrame)
        let insets = UIEdgeInsets(top: 0.0, left: layout.safeInsets.left, bottom: layout.intrinsicInsets.bottom, right: layout.safeInsets.right)
        self.chatController.containerLayoutUpdated(ContainerViewLayout(size: chatFrame.size, metrics: layout.metrics, deviceMetrics: layout.deviceMetrics, intrinsicInsets: insets, safeInsets: UIEdgeInsets(top: 4.0, left: layout.safeInsets.left, bottom: layout.intrinsicInsets.bottom, right: layout.safeInsets.right), reservedCorners: layout.reservedCorners, division: layout.division, additionalInsets: layout.additionalInsets, statusBarHeight: nil, inputHeight: layout.inputHeight, inputHeightIsInteractivellyChanging: false, inVoiceOver: false, presentedInFormSheet: false), transition: transition)
    }
}

final class AyuGramDeletedChatViewController: ViewController {
    private let context: AccountContext
    private let contents: AyuGramDeletedChatContents
    private let chatController: ChatController
    private let more: ((ViewController) -> Void)?
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    private var node: AyuGramDeletedChatNode {
        return self.displayNode as! AyuGramDeletedChatNode
    }

    init(context: AccountContext, peerId: EnginePeer.Id, title: String, more: ((ViewController) -> Void)?) {
        self.context = context
        self.more = more
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationData = presentationData
        let contents = AyuGramDeletedChatContents(context: context, peerId: peerId)
        self.contents = contents
        self.chatController = context.sharedContext.makeChatController(context: context, chatLocation: .customChatContents, subject: .customChatContents(contents: contents), botStart: nil, mode: .standard(.embedded(invertDirection: false)), params: nil)

        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: presentationData))

        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
        self.title = title
        self.navigationItem.backBarButtonItem = UIBarButtonItem(title: presentationData.strings.Common_Back, style: .plain, target: nil, action: nil)
        if more != nil {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "•••", style: .plain, target: self, action: #selector(self.morePressed))
        }

        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else {
                return
            }
            let previousTheme = self.presentationData.theme
            self.presentationData = presentationData
            if previousTheme !== presentationData.theme {
                self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
                self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
                if self.isNodeLoaded {
                    self.node.updatePresentationData(presentationData)
                }
            }
        })
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    @objc private func morePressed() {
        self.view.endEditing(true)
        self.more?(self)
    }

    override func loadDisplayNode() {
        let contents = self.contents
        self.displayNode = AyuGramDeletedChatNode(chatController: self.chatController, presentationData: self.presentationData, placeholder: i18n("Ayu.DeletedSearchText", self.presentationData.strings.baseLanguageCode), queryUpdated: { query in
            contents.hashtagSearchUpdate(query: query)
        })
        self.chatController.parentController = self
        self.chatController.customNavigationController = self.navigationController as? NavigationController
        self.chatController.willMove(toParent: self)
        self.addChild(self.chatController)
        self.chatController.didMove(toParent: self)
        self.displayNodeDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.chatController.customNavigationController = self.navigationController as? NavigationController
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.node.containerLayoutUpdated(layout, navigationHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}

func ayuGramDeletedChatViewer(context: AccountContext, peerId: EnginePeer.Id, title: String, more: ((ViewController) -> Void)? = nil) -> ViewController {
    return AyuGramDeletedChatViewController(context: context, peerId: peerId, title: title, more: more)
}
