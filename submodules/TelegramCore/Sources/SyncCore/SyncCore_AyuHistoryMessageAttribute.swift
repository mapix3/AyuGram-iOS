import Foundation
import Postbox

public final class AyuHistoryMessageAttribute: MessageAttribute {
    public var retainedOnServerRefresh: Bool { true }
    public let originalText: String
    public let editedAt: Int32?
    public let deletedAt: Int32?
    public init(originalText: String, editedAt: Int32?, deletedAt: Int32?) {
        self.originalText = originalText
        self.editedAt = editedAt
        self.deletedAt = deletedAt
    }
    public init(decoder: PostboxDecoder) {
        self.originalText = decoder.decodeStringForKey("t", orElse: "")
        self.editedAt = decoder.decodeOptionalInt32ForKey("e")
        self.deletedAt = decoder.decodeOptionalInt32ForKey("d")
    }
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.originalText, forKey: "t")
        if let editedAt { encoder.encodeInt32(editedAt, forKey: "e") } else { encoder.encodeNil(forKey: "e") }
        if let deletedAt { encoder.encodeInt32(deletedAt, forKey: "d") } else { encoder.encodeNil(forKey: "d") }
    }
}

public extension Message {
    var ayuHistory: AyuHistoryMessageAttribute? {
        guard let marker = self.attributes.first(where: { $0 is AyuHistoryMessageAttribute }) as? AyuHistoryMessageAttribute, marker.editedAt != nil || marker.deletedAt != nil else { return nil }
        return marker
    }
}
