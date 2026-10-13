from pathlib import Path
import subprocess
from ayugram_history_checks import declaration


def receipt_regression_code(source: Path):
    code = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramManualReceipts.swift').read_text()
    functions = '\n'.join(declaration(code, 'func ' + name + '(') for name in
                          ['ayuReceiptThreadId', 'ayuApplyThreadReceipt', 'ayuConsumeMentionLocally'])
    return '''import Foundation
struct MessageId: Hashable { let peerId: Int; let namespace: Int; let id: Int32 }
struct MessageIndex { let id: MessageId }
struct MessageTags: OptionSet {
    let rawValue: Int
    static let unseenPersonalMessage = MessageTags(rawValue: 1)
    static let other = MessageTags(rawValue: 2)
}
final class ConsumablePersonalMentionMessageAttribute {
    let consumed: Bool; let pending: Bool
    init(consumed: Bool, pending: Bool) { self.consumed = consumed; self.pending = pending }
}
final class MediaLifetimeAttribute { let countdownBeginTime: Int? = nil }
struct StoreMessageFlags { let value: Int; init(_ value: Int) { self.value = value } }
struct StoreMessageForwardInfo { init(_ value: Int) {} }
struct Author { let id: Int }
struct StoreMessage {
    let id: MessageId; let customStableId: Int?; let globallyUniqueId: Int?; let groupingKey: Int?; let threadId: Int64?
    let timestamp: Int; let flags: StoreMessageFlags; let tags: MessageTags; let globalTags: Int; let localTags: Int
    let forwardInfo: StoreMessageForwardInfo?; let authorId: Int?; let text: String; let attributes: [AnyObject]; let media: [String]
}
struct Message {
    let id: MessageId; let globallyUniqueId = 10; let groupingKey = 11; let threadId: Int64? = 55
    let timestamp = 20; let flags = 3; let tags: MessageTags; let globalTags = 7; let localTags = 8
    let forwardInfo: Int? = nil; let author: Author? = Author(id: 9); let text = "Mention with timed media"
    let attributes: [AnyObject]; let media = ["unopened photo"]
}
enum MessageUpdate { case update(StoreMessage) }
enum PendingActionType { case consumeUnseenPersonalMessage }
struct MessageHistoryThreadData {
    var incomingUnreadCount: Int32 = 10; var maxIncomingReadId: Int32 = 100
    var maxKnownMessageId: Int32 = 250; var isMarkedUnread = true
}
struct DataBox { let value: MessageHistoryThreadData; func get<T>(_ type: T.Type) -> T? { value as? T } }
struct StoredMessageHistoryThreadInfo {
    let data: DataBox
    init?(_ value: MessageHistoryThreadData) { data = DataBox(value: value) }
}
final class Transaction {
    var message: Message?
    var stored: StoreMessage?
    var pending: [MessageId] = []
    var thread = MessageHistoryThreadData()
    var writes = 0
    var writtenPeer: Int?; var writtenThread: Int64?
    func updateMessage(_ id: MessageId, update: (Message) -> MessageUpdate) {
        if let message, message.id == id, case let .update(value) = update(message) { stored = value }
    }
    func setPendingMessageAction(type: PendingActionType, id: MessageId, action: Int?) { pending.removeAll { $0 == id } }
    func getMessageHistoryThreadInfo(peerId: Int, threadId: Int64) -> StoredMessageHistoryThreadInfo? { StoredMessageHistoryThreadInfo(thread) }
    func getThreadMessageCount(peerId: Int, threadId: Int64, namespace: Int, fromIdExclusive: Int32, toIndex: MessageIndex) -> Int? { 3 }
    func setMessageHistoryThreadInfo(peerId: Int, threadId: Int64, info: StoredMessageHistoryThreadInfo) {
        thread = info.data.value; writes += 1; writtenPeer = peerId; writtenThread = threadId
    }
}
''' + functions + '''
// Ordinary replies have a threadId in Postbox, but a whole-chat receipt must
// use history rather than readDiscussion. Explicit thread UI stays scoped.
precondition(ayuReceiptThreadId(requested: nil, message: 123, isForum: false, afterSending: false) == nil)
precondition(ayuReceiptThreadId(requested: nil, message: 123, isForum: false, afterSending: true) == nil)
precondition(ayuReceiptThreadId(requested: 123, message: 456, isForum: false, afterSending: false) == 123)
precondition(ayuReceiptThreadId(requested: 123, message: nil, isForum: true, afterSending: false) == 123)
precondition(ayuReceiptThreadId(requested: nil, message: 123, isForum: true, afterSending: true) == 123)
precondition(ayuReceiptThreadId(requested: nil, message: 123, isForum: true, afterSending: false) == nil)
precondition(ayuReceiptThreadId(requested: 0, message: 123, isForum: false, afterSending: false) == nil)
let id = MessageId(peerId: 1, namespace: 0, id: 110)
let otherId = MessageId(peerId: 2, namespace: 0, id: 110)
for pending in [false, true] {
    let lifetime = MediaLifetimeAttribute()
    let t = Transaction()
    t.message = Message(id: id, tags: [.unseenPersonalMessage, .other], attributes: [lifetime, ConsumablePersonalMentionMessageAttribute(consumed: false, pending: pending)])
    t.pending = [id, otherId]
    ayuConsumeMentionLocally(transaction: t, id: id)
    let result = t.stored!
    precondition(!result.tags.contains(.unseenPersonalMessage) && result.tags.contains(.other))
    let mention = result.attributes[1] as! ConsumablePersonalMentionMessageAttribute
    precondition(mention.consumed && !mention.pending, "Visible mentions, including stale pending ones, clear locally")
    precondition(result.attributes[0] === lifetime && lifetime.countdownBeginTime == nil, "Never consume timed media")
    precondition(result.media == ["unopened photo"] && result.text == t.message!.text && result.threadId == 55)
    precondition(result.timestamp == 20 && result.flags.value == 3 && result.globalTags == 7 && result.localTags == 8)
    precondition(t.pending == [otherId], "No other chat's queued receipt is removed")
    t.stored = nil
    ayuConsumeMentionLocally(transaction: t, id: otherId)
    precondition(t.stored == nil, "Unknown and other-peer IDs cannot change this message")
}
let t = Transaction()
ayuApplyThreadReceipt(transaction: t, index: MessageIndex(id: id), threadId: 55)
precondition(t.thread.incomingUnreadCount == 7 && t.thread.maxIncomingReadId == 110 && t.thread.maxKnownMessageId == 250)
precondition(!t.thread.isMarkedUnread && t.writtenPeer == 1 && t.writtenThread == 55)
ayuApplyThreadReceipt(transaction: t, index: MessageIndex(id: id), threadId: 55)
precondition(t.writes == 1, "Retries never decrement a topic twice")
print("Production receipt routing, stale mention repair, media preservation and scoped thread counts passed")
'''


def check_receipt_regressions(source: Path, output: Path):
    code = receipt_regression_code(source)
    file = output / 'ReceiptRegressionTests.swift'
    file.write_text(code)
    binary = output / 'receipt-regression-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', file, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=10)
