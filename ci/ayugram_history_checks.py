import re
import subprocess
from pathlib import Path


def declaration(text, start):
    first = text.index(start)
    opening = text.index('{', first)
    depth = 1
    end = opening + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[first:end] + '\n'


def attribute_retention_test_code(source: Path):
    table = (source / 'submodules/Postbox/Sources/MessageHistoryTable.swift').read_text()
    function = declaration(table, '    private func justUpdate(')
    start = function.index('            var updatedAttributes = message.attributes')
    end = function.index('            self.seedConfiguration.mergeMessageAttributes', start)
    retained_attributes = function[start:end]
    return '''
protocol MessageAttribute: AnyObject {
    var retainedOnServerRefresh: Bool { get }
    func ayuRestoredOnServerRefresh() -> MessageAttribute
}
extension MessageAttribute {
    func ayuRestoredOnServerRefresh() -> MessageAttribute { self }
}
final class RetainedAttribute: MessageAttribute {
    let value: Int
    let deleted: Bool
    var retainedOnServerRefresh: Bool { true }
    init(_ value: Int, deleted: Bool = false) { self.value = value; self.deleted = deleted }
    func ayuRestoredOnServerRefresh() -> MessageAttribute { self.deleted ? RetainedAttribute(self.value) : self }
}
final class ServerAttribute: MessageAttribute {
    var retainedOnServerRefresh: Bool { false }
}
struct AttributeRefreshMessage { let attributes: [MessageAttribute] }
enum MessageHistoryTable {
    static func renderMessageAttributes(_ attributes: [MessageAttribute]) -> [MessageAttribute] { attributes }
}
func refreshAttributes(previousMessage: [MessageAttribute], incoming: [MessageAttribute], ayuRestored: Bool = false) -> [MessageAttribute] {
    let message = AttributeRefreshMessage(attributes: incoming)
    let type: Int8 = 0
''' + retained_attributes + '''
    precondition(type == 0)
    return updatedAttributes
}
let previousMarker = RetainedAttribute(1)
let serverAttribute = ServerAttribute()
let retained = refreshAttributes(previousMessage: [previousMarker, serverAttribute], incoming: [])
expect(retained.count == 1 && retained[0] === previousMarker, "Refresh preserves local history without stale server attributes")
let replacementMarker = RetainedAttribute(2)
let refreshed = refreshAttributes(previousMessage: [previousMarker], incoming: [serverAttribute, replacementMarker])
expect(refreshed.count == 2 && refreshed[1] === replacementMarker, "Refresh keeps the incoming marker without a duplicate")
expect(refreshAttributes(previousMessage: [], incoming: [serverAttribute]).count == 1, "Refresh preserves normal server attributes")
let deletedMarker = RetainedAttribute(3, deleted: true)
let kept = refreshAttributes(previousMessage: [deletedMarker], incoming: [])
expect(kept.count == 1 && kept[0] === deletedMarker, "Refresh of a deleted message keeps its deleted marker")
let restored = refreshAttributes(previousMessage: [deletedMarker], incoming: [], ayuRestored: true)
expect(restored.count == 1 && (restored[0] as? RetainedAttribute).map { $0.value == 3 && !$0.deleted } == true, "A server copy of a message kept as deleted drops the deleted marker")
print("Attribute retention passed with a local Int8 named type")
'''


def owner_badge_test_code(source: Path):
    bubble = (source / 'submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift').read_text(encoding='utf-8')
    apply = declaration(bubble, '    private static func applyLayout(')
    signature = apply[:apply.index(') -> Void {')]
    parameter = re.search(r'^\s+(ayuOwner: Bool),\s*$', signature, re.M)
    layout = bubble[:bubble.index('    private static func applyLayout(')]
    invocation = layout[layout.index('return ChatMessageBubbleItemNode.applyLayout('):]
    argument = re.search(r'^\s+(ayuOwner: ayuOwner),\s*$', invocation, re.M)
    if parameter is None or argument is None:
        raise ValueError('Owner badge must pass its author flag from layout calculation to applyLayout')
    reset = '        strongSelf.ayuOwnerBadge.isHidden = true'
    if reset not in apply or apply.index(reset) > apply.index('if let nameNode ='):
        raise ValueError('Owner badge must be hidden before a reused bubble applies its author name')
    start = apply.index('            strongSelf.ayuOwnerBadge.isHidden = !ayuOwner')
    end = apply.index('            if boostCount > 0 {', start)
    badge = apply[start:end]
    return '''
import UIKit
final class CompatibilityBubbleNode {
    let ayuOwnerBadge = UIImageView()
    let clippingNode = CompatibilityClippingNode()
    var credibilityIconView: UIView?
}
final class CompatibilityClippingNode { let view = UIView() }
struct CompatibilityAnimator {
    func updateFrame(layer: CALayer, frame: CGRect, completion: (() -> Void)?) { layer.frame = frame }
}
struct CompatibilityAnimation { let animator = CompatibilityAnimator() }
enum OwnerBadgeCompatibility {
    static func applyLayout(''' + parameter.group(1) + ''', strongSelf: CompatibilityBubbleNode, nameNode: UIView?, animation: CompatibilityAnimation) {
''' + reset + '''
        if let nameNode = nameNode {
''' + badge + '''
        }
    }
    static func layout(ayuOwner: Bool, node: CompatibilityBubbleNode, nameNode: UIView?) {
        Self.applyLayout(''' + argument.group(1) + ''', strongSelf: node, nameNode: nameNode, animation: CompatibilityAnimation())
    }
}
'''


def check_notified_messages(source: Path):
    service = (source / 'Telegram/NotificationService/Sources/NotificationService.swift').read_text()
    deletion = service.split('case let .deleteMessage(ids):', 1)[1].split('case let .readReactions(', 1)[0]
    assert '_internal_ayuGramDeleteNotifiedMessages(' in deletion and '_internal_deleteMessages(' not in deletion, 'MESSAGE_DELETED pushes keep deleted messages'
    assert '_internal_ayuGramRememberNotifiedMessage(' in service, 'Notified messages are remembered before the poll'
    simple = (source / 'Swiftgram/SGSimpleSettings/Sources/SimpleSettings.swift').read_text()
    assert 'AyuGramSettings(shared: UserDefaults(suiteName: APP_GROUP_IDENTIFIER))' in simple, 'The notification service sees Save Deleted Messages'
    utils = (source / 'submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift').read_text()
    assert 'ayuGramRestoreNotifiedMessages(transaction: transaction, globalIds: ids)' in utils
    assert 'ayuGramRestoreNotifiedMessages(transaction: transaction, ids: ids)' in utils


def check_update_installers(source: Path):
    prompt = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramUpdatePrompt.swift').read_text()
    # Without TrollStore the Magnifier scheme opens the system Magnifier.
    assert prompt.count('apple-magnifier://') == 1 and 'if ayuGramInstalledByTrollStore, let url = URL(string: "apple-magnifier://' in prompt
    assert '/releases/tag/' in prompt, 'Without an installer the release page opens'
    for plist in ['Telegram-iOS/Info.plist', 'Telegram-iOS/InfoBazel.plist', 'BUILD']:
        text = (source / 'Telegram' / plist).read_text()
        for scheme in re.findall(r'\("([a-z]+)", \{ "\1://', prompt):
            assert '<string>%s</string>' % scheme in text, (plist, scheme)


def check_deleted_chats(source: Path):
    core = source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages'
    retained = (core / 'AyuGramRetainedMessages.swift').read_text()
    remote = retained.split('func ayuGramDeleteRemoteMessages(', 1)[1].split('\n}\n', 1)[0]
    assert 'ayuGramFlagDeletedChats(transaction: transaction, retained:' in remote, 'A deleted whole chat is flagged'
    history = (core / 'AyuGramMessageHistory.swift').read_text()
    assert history.count('ayuGramDeletedChatPeers(transaction: transaction)') >= 2, 'Pruning and clearing keep deleted chats'
    controller = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramHistoryController.swift').read_text()
    assert 'ayuGramDeletedChatsController(context: context)' in controller and 'ayuGramDeletedChats()' in controller
    protection = (core / 'AyuGramContentProtection.swift').read_text()
    assert 'source.flags.contains(.AyuLocallyDeleted) || (ignoresProtection && ayuIsSourceCopyProtected(' in protection, 'Deleted messages are forwarded as new messages'


def check_push_relay(source: Path):
    relay = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramPushRelay.swift').read_text()
    worker = (source / 'push-relay/worker.js').read_text()
    # The app and the relay agree on the endpoint layout: d (32) | public key (65) | auth (16) | Bark key.
    assert 'keys.count == 113' in relay and 'subdata(in: 32 ..< 97)' in relay and 'subdata(in: 97 ..< 113)' in relay
    assert 'blob.slice(113)' in worker and 'blob.slice(32, 97)' in worker
    assert re.search(r'baseURL = "https://[^"]+"', relay), 'The relay address is set'
    assert 'AyuGramPushRelay.renew(context: context)' in (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramUpdatePrompt.swift').read_text()
    for plist in ['Telegram-iOS/Info.plist', 'Telegram-iOS/InfoBazel.plist', 'BUILD']:
        text = (source / 'Telegram' / plist).read_text()
        assert '<string>ayugram</string>' in text, 'Bark opens AyuGram'
        assert '<string>bark</string>' in text, 'AyuGram can tell whether Bark is installed'
    assert 'apps.apple.com/app/id1403753865' in relay, 'Without Bark its App Store page opens'
    assert 'ayuGramOfferBarkIfNeeded(context: context)' in (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramUpdatePrompt.swift').read_text()
    subprocess.run(['node', 'push-relay/test.mjs'], cwd=source, check=True)


def check_deferred_reads(source: Path):
    core = source / 'submodules/TelegramCore/Sources'
    earliest = (core / 'TelegramEngine/Messages/EarliestUnseenPersonalMentionMessage.swift').read_text()
    # Clearing a stale counter must never mark every mention in the chat read on the server.
    assert 'addSynchronizeMarkAllUnseenPersonalMessagesOperation' not in earliest
    assert earliest.count('ayuEarliestUnseenWithRefetch(account: account') == 2 and 'case .refetch' in earliest
    actions = (core / 'State/ManagedConsumePersonalMessagesActions.swift').read_text()
    assert 'ayuDeferReactionRead(transaction: transaction, id: id)' in actions and 'ayuDeferMentionRead(transaction: transaction, id: id)' in actions
    receipts = (core / 'TelegramEngine/Messages/AyuGramManualReceipts.swift').read_text()
    after = receipts.split('func _internal_ayuAfterSending(', 1)[1].split('\n}\n', 1)[0]
    assert after.count('flushDeferredReads |> then(') == 2, 'Reads are reported after every sent message, with or without read-on-send'
    deferred = (core / 'TelegramEngine/Messages/AyuGramDeferredReads.swift').read_text()
    assert 'ayuMentionReadIsPrivate(media: message.media, attributes: message.attributes)' in deferred, 'Voice and round mentions stay unplayed for the sender'


def check_edit_versions(source: Path):
    retained = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramRetainedMessages.swift').read_text()
    record = retained.split('func ayuGramRecordEdit(', 1)[1].split('\n}\n', 1)[0]
    assert 'AyuGramSettings.shared.snapshot.messageHistory && ayuGramIsHistoryCandidate(' in record, 'Edits keep their first version in every chat'
    history = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramHistoryController.swift').read_text()
    assert 'context.engine.ayuGramMessageVersions(messageId: messageId)' in history, 'A message opens its own versions'


def check_history(source: Path):
    check_notified_messages(source)
    check_edit_versions(source)
    check_update_installers(source)
    check_deferred_reads(source)
    check_push_relay(source)
    check_deleted_chats(source)
    output = source / 'build-input/ayu-history-checks'
    output.mkdir(parents=True, exist_ok=True)
    core = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramMessageHistory.swift').read_text()
    flags = (source / 'submodules/Postbox/Sources/Message.swift').read_text()
    code = 'import Foundation\n'
    for token in ['public struct AyuGramHistoryEntry:', 'private struct AyuGramHistory:', 'private func archiveDirectory(', 'private func archiveFile(', 'private func pruneHistory(']:
        code += declaration(core, token)
    for token in ['public struct MessageFlags:', 'public struct StoreMessageFlags:']:
        code += declaration(flags, token)
    code += '''
struct PeerId: Hashable { let value: Int64; init(_ value: Int64) { self.value = value } }
struct MessageId: Hashable { let peerId: PeerId; let namespace: Int32; let id: Int32 }
enum Namespaces { enum Message { static let Cloud: Int32 = 0 } }
struct MediaBox { let basePath: String }
struct HistoryAttribute { let deletedAt: Int32? }
struct TestMessage { let ayuHistory: HistoryAttribute? }
final class Transaction {
    var messages: [MessageId: TestMessage] = [:]
    var removed: Set<MessageId> = []
    func getMessage(_ id: MessageId) -> TestMessage? { messages[id] }
    func deleteMessages(_ ids: [MessageId], forEachMedia: (Int) -> Void) { removed.formUnion(ids); ids.forEach { messages.removeValue(forKey: $0) } }
}
func ayuGramClearLocalEditMarker(transaction: Transaction, ids: Set<MessageId>) {}
var deletedChatPeers: Set<Int64> = []
func ayuGramDeletedChatPeers(transaction: Transaction) -> Set<Int64> { deletedChatPeers }
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    precondition(condition(), description)
}
let now = Int32(Date().timeIntervalSince1970)
let oldJSON = Data(#"{"peerId":1,"messageId":4,"peerTitle":"chat","author":"user","text":"before","event":"edited","timestamp":1}"#.utf8)
let old = try JSONDecoder().decode(AyuGramHistoryEntry.self, from: oldJSON)
expect(old.authorId == nil && old.updatedText == nil && old.mediaKind == nil, "Older archives must decode without migration")
var incoming = MessageFlags([.Incoming, .CountedAsIncoming])
expect(incoming.ayuCountsAsIncoming, "Normal incoming message contributes to unread")
incoming.insert(.AyuLocallyDeleted)
expect(!incoming.ayuCountsAsIncoming && incoming.contains(.Incoming), "Deleted message preserves direction without unread")
let stored = StoreMessageFlags(incoming)
expect(stored.contains(.AyuLocallyDeleted) && !stored.ayuCountsAsIncoming, "Store flags preserve deletion")
expect(MessageFlags(stored).contains(.AyuLocallyDeleted), "Round-trip flags preserve deletion")
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let box = MediaBox(basePath: root.path)
try FileManager.default.createDirectory(at: archiveDirectory(box), withIntermediateDirectories: true)
expect(archiveFile(box, name: "../escape") == nil && archiveFile(box, name: "/escape") == nil, "Archive paths cannot escape")
let transaction = Transaction()
var entries: [AyuGramHistoryEntry] = []
for index in 1 ... 205 {
    let entry = AyuGramHistoryEntry(peerId: 1, messageId: Int32(index), peerTitle: "chat", author: "user", text: "text", event: "deleted", timestamp: now, photoFileName: nil, photoResourceId: nil)
    entries.append(entry)
    transaction.messages[MessageId(peerId: PeerId(1), namespace: 0, id: Int32(index))] = TestMessage(ayuHistory: HistoryAttribute(deletedAt: now))
}
private var history = AyuGramHistory(entries: entries)
pruneHistory(&history, transaction: transaction, mediaBox: box)
expect(history.entries.count == 200 && transaction.removed.isEmpty, "Record cap keeps the kept messages in their chats")
let expired = AyuGramHistoryEntry(peerId: 1, messageId: 999, peerTitle: "chat", author: "user", text: "old", event: "deleted", timestamp: now - 31 * 86400, photoFileName: "old.jpg", photoResourceId: nil)
transaction.messages[MessageId(peerId: PeerId(1), namespace: 0, id: 999)] = TestMessage(ayuHistory: HistoryAttribute(deletedAt: now))
try Data([1, 2, 3]).write(to: archiveFile(box, name: "old.jpg")!)
history.entries.append(expired)
pruneHistory(&history, transaction: transaction, mediaBox: box)
expect(transaction.removed.contains(MessageId(peerId: PeerId(1), namespace: 0, id: 999)), "Retention removes expired tombstones")
expect(!FileManager.default.fileExists(atPath: archiveFile(box, name: "old.jpg")!.path), "Retention removes archived media")
let deletedChatRecord = AyuGramHistoryEntry(peerId: 2, messageId: 7, peerTitle: "gone", author: "user", text: "old", event: "deleted", timestamp: now - 31 * 86400, photoFileName: nil, photoResourceId: nil)
transaction.messages[MessageId(peerId: PeerId(2), namespace: 0, id: 7)] = TestMessage(ayuHistory: HistoryAttribute(deletedAt: now))
deletedChatPeers = [2]
history.entries.append(deletedChatRecord)
pruneHistory(&history, transaction: transaction, mediaBox: box)
expect(!transaction.removed.contains(MessageId(peerId: PeerId(2), namespace: 0, id: 7)), "Deleted chats keep their messages past 30 days")
print("History migration, direction/unread flags, path containment, record cap, expiry and deleted chats passed")
'''
    code += attribute_retention_test_code(source)
    tests = output / 'HistoryTests.swift'
    tests.write_text(code)
    binary = output / 'history-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', tests, '-o', binary], check=True)
    subprocess.run([binary], check=True)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    badge = source / 'submodules/Display/Source/AyuGramAppBadge.swift'
    icon_settings = source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramIconSettings.swift'
    badge_inputs = [badge]
    if icon_settings.exists():
        sdk_badge = output / 'BadgeCompatibility.swift'
        sdk_badge.write_text(badge.read_text().replace('import SGSimpleSettings\n', ''))
        badge_inputs = [icon_settings, sdk_badge]
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios13.0', '-sdk', sdk, '-typecheck', *badge_inputs], check=True)
    print('Badge artwork typechecked against the native iOS 13 SDK')
    owner_badge = output / 'OwnerBadgeCompatibility.swift'
    owner_badge.write_text(owner_badge_test_code(source))
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios13.0', '-sdk', sdk, '-typecheck', owner_badge], check=True)
    print('Bubble owner flag reaches applyLayout; badge rendering typechecked with real UIKit')
    card = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramHistoryCardItem.swift').read_text()
    controller = (source / 'Swiftgram/SGSettingsUI/Sources/AyuGramHistoryController.swift').read_text()
    keys = sorted(set(re.findall(r'\bstrings\.([A-Za-z0-9_]+)', card + controller)))
    native = 'import Foundation\nimport UIKit\nimport AVKit\nimport QuickLook\nimport ImageIO\n'
    native += declaration(core, 'public struct AyuGramHistoryEntry:')
    native += 'struct PresentationStrings {\n' + ''.join(f'    var {key}: String {{ "{key}" }}\n' for key in keys) + '}\n'
    native += '''
typealias ItemListSectionId = Int32
protocol ListViewItem {}
struct ListViewItemNeighbors {}
protocol ItemListItem { var sectionId: ItemListSectionId { get } }
struct ListViewItemLayoutParams { let width: CGFloat; let leftInset: CGFloat; let rightInset: CGFloat }
struct ListViewItemNodeLayout { let contentSize: CGSize; let insets: UIEdgeInsets }
struct ListViewItemApply {}
struct ListViewItemUpdateAnimation {}
class ListViewItemNode {
    let view = UIView()
    var contentSize = CGSize.zero
    var insets = UIEdgeInsets.zero
    init(layerBacked: Bool) {}
    // Mirrors Display's ListViewItemNode members that subclasses could shadow by accident.
    func tapped() {}
    func selected() {}
}
enum NoError: Error {}
final class Signal<T, E: Error> {}
final class Queue {
    static func mainQueue() -> Queue { Queue() }
    func async(_ f: @escaping () -> Void) { f() }
}
struct CompatibilityCheckColors {
    var fillColor: UIColor { .systemBlue }
    var foregroundColor: UIColor { .white }
}
struct CompatibilityListTheme {
    var itemAccentColor: UIColor { .purple }
    var itemPrimaryTextColor: UIColor { .label }
    var itemSecondaryTextColor: UIColor { .secondaryLabel }
    var itemBlocksBackgroundColor: UIColor { .secondarySystemBackground }
    var itemDestructiveColor: UIColor { .systemRed }
    var itemBlocksSeparatorColor: UIColor { .separator }
    var itemCheckColors = CompatibilityCheckColors()
}
struct CompatibilityTheme { var list = CompatibilityListTheme(); var overallDarkAppearance = false }
typealias PresentationTheme = CompatibilityTheme
let UIScreenPixel: CGFloat = 1
extension UIColor {
    convenience init(rgb: UInt32) { self.init(red: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255, blue: CGFloat(rgb & 0xff) / 255, alpha: 1) }
    func withMultipliedAlpha(_ alpha: CGFloat) -> UIColor { withAlphaComponent(alpha) }
    func mixedWith(_ other: UIColor, alpha: CGFloat) -> UIColor { self }
}
struct ItemListPresentationData { var theme = CompatibilityTheme(); var strings = PresentationStrings() }
struct CompatibilityEngine { func ayuGramArchivedPhotoURL(_ name: String) -> URL? { nil } }
struct AccountContext { var engine = CompatibilityEngine() }
struct EnginePeer: Equatable {}
final class AvatarNode {
    let view = UIView()
    var frame = CGRect.zero
    var isHidden = false
    init(font: UIFont) {}
    func setPeer(context: AccountContext, theme: PresentationTheme, peer: EnginePeer?, synchronousLoad: Bool, displayDimensions: CGSize) {}
}
func avatarPlaceholderFont(size: CGFloat) -> UIFont { .systemFont(ofSize: size) }
func i18n(_ key: String, _ language: String) -> String { key }
'''
    native += re.sub(r'^import \w+\n', '', card, flags=re.M)
    native += declaration(controller, 'private final class AyuArchivePhotoController:')
    native += declaration(controller, 'private final class AyuArchiveDocumentController:')
    ui = output / 'HistoryUICompatibility.swift'
    ui.write_text(native)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios13.0', '-sdk', sdk, '-typecheck', ui], check=True)
    print('History summary, empty state, archive cards, image/share and document previews typechecked with real UIKit and QuickLook')
