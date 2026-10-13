from pathlib import Path
import subprocess
from ayugram_history_checks import declaration


def check_link_free_emoji(source: Path):
    model = (source / 'submodules/TelegramCore/Sources/SyncCore/SyncCore_TextEntitiesMessageAttribute.swift').read_text()
    helpers = (source / 'submodules/TelegramCore/Sources/TelegramEngine/Messages/AyuGramEmojiLinks.swift').read_text()
    prepare = declaration(helpers, 'func ayuPrepareEmojiLinks(')
    assert 'TextUrl' not in prepare and 'https://' not in prepare
    serializer = (source / 'submodules/TelegramCore/Sources/ApiUtils/TextEntitiesMessageAttribute.swift').read_text()
    assert 'apiEntitiesFromMessageTextEntities(attribute.ayuWireEntities' in serializer
    fixture = '''
import Foundation
struct PeerId: Equatable { let value: Int64 }
struct MediaId: Hashable { let namespace: Int; let id: Int64 }
enum Namespaces { enum Media { static let CloudFile = 1 } }
enum MessageTextEntityType: Equatable {
    case CustomEmoji(stickerPack: String?, fileId: Int64)
    case TextUrl(url: String)
    case TextMention(peerId: PeerId)
    case Bold
}
struct MessageTextEntity: Equatable {
    let range: Range<Int>
    let type: MessageTextEntityType
}
protocol MessageAttribute: AnyObject {}
final class PostboxEncoder {
    var values: [String: Any] = [:]
    func encodeObjectArray<T>(_ value: [T], forKey key: String) { values[key] = value }
    func encodeString(_ value: String, forKey key: String) { values[key] = value }
}
final class PostboxDecoder {
    let values: [String: Any]
    init(_ values: [String: Any]) { self.values = values }
    func decodeObjectArrayWithDecoderForKey<T>(_ key: String) -> [T] { values[key] as! [T] }
    func decodeOptionalStringForKey(_ key: String) -> String? { values[key] as? String }
}
'''
    fixture += declaration(helpers, 'public func ayuEmojiFileIdFromLink(').replace('public ', '')
    fixture += declaration(model, 'public class TextEntitiesMessageAttribute:').replace('public ', '')
    fixture += declaration(helpers, 'func ayuMergeLocalEmojiAttributes(')
    fixture += '''
let emoji = MessageTextEntity(range: 0..<2, type: .CustomEmoji(stickerPack: nil, fileId: 9223372036854775806))
let bold = MessageTextEntity(range: 0..<2, type: .Bold)
let userLink = MessageTextEntity(range: 3..<7, type: .TextUrl(url: "https://example.com"))
let legacy = MessageTextEntity(range: 0..<2, type: .TextUrl(url: "https://t.me/addemoji/pack#ayuemoji_42"))
let local = TextEntitiesMessageAttribute(entities: [emoji, bold, userLink, legacy], ayuLocalEmojiText: "😃 link")
precondition(local.ayuWireEntities == [bold, userLink], "Generated emoji links and paid entities never reach the server")
precondition(local.entities.contains(emoji), "The sender still renders the original animated emoji")
precondition(local.associatedMediaIds.contains(MediaId(namespace: 1, id: 9223372036854775806)), "The animation keeps its media reference")
let premium = TextEntitiesMessageAttribute(entities: [emoji, bold, userLink])
precondition(premium.ayuWireEntities == [emoji, bold, userLink], "Actual Premium keeps its native entities")
let encoder = PostboxEncoder()
local.encode(encoder)
let restored = TextEntitiesMessageAttribute(decoder: PostboxDecoder(encoder.values))
precondition(restored == local && restored.ayuWireEntities == local.ayuWireEntities, "Local animation and wire filtering survive reopening")
var attributes: [MessageAttribute] = [TextEntitiesMessageAttribute(entities: [bold, userLink])]
ayuMergeLocalEmojiAttributes(text: "😃 link", previous: [local], updated: &attributes)
let refreshed = attributes[0] as! TextEntitiesMessageAttribute
precondition(refreshed.ayuWireEntities == [bold, userLink] && refreshed.entities.contains(emoji), "Server refresh retains local animation and current formatting")
var edited: [MessageAttribute] = [TextEntitiesMessageAttribute(entities: [bold])]
ayuMergeLocalEmojiAttributes(text: "Different text", previous: [local], updated: &edited)
precondition((edited[0] as! TextEntitiesMessageAttribute).ayuLocalEmojiText == nil, "An edit on another device clears a stale overlay")
var genuine: [MessageAttribute] = [premium]
ayuMergeLocalEmojiAttributes(text: "😃 link", previous: [local], updated: &genuine)
precondition(genuine[0] === premium, "A genuine server Premium entity has priority")
let historical = TextEntitiesMessageAttribute(decoder: PostboxDecoder(["entities": [bold]]))
precondition(historical.ayuLocalEmojiText == nil && historical.ayuWireEntities == [bold], "Older stored messages remain compatible")
print("Link-free emoji serialization, local persistence, refresh, edits and genuine Premium passed")
'''
    output = source / 'build-input/ayu-emoji-checks'
    output.mkdir(parents=True, exist_ok=True)
    file = output / 'EmojiTests.swift'
    file.write_text(fixture)
    binary = output / 'emoji-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', file, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=10)
