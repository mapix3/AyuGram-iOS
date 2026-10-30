import Foundation
import Postbox
import SwiftSignalKit

public struct AyuGramImportedMessage: Equatable {
    public let timestamp: Int32
    public let incoming: Bool
    public let text: String

    public init(timestamp: Int32, incoming: Bool, text: String) {
        self.timestamp = timestamp
        self.incoming = incoming
        self.text = text
    }
}

public extension TelegramEngine {
    func ayuGramImportLocally(peerId: EnginePeer.Id, messages: [AyuGramImportedMessage]) -> Signal<Int, NoError> {
        let accountPeerId = self.account.peerId
        return self.account.postbox.transaction { transaction -> Int in
            guard transaction.getPeer(peerId) != nil else {
                return 0
            }
            let stored = messages.filter { !$0.text.isEmpty }.map { message -> StoreMessage in
                return StoreMessage(peerId: peerId, namespace: Namespaces.Message.Local, customStableId: nil, globallyUniqueId: Int64.random(in: Int64.min ... Int64.max), groupingKey: nil, threadId: nil, timestamp: message.timestamp, flags: message.incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: message.incoming ? peerId : accountPeerId, text: message.text, attributes: [], media: [])
            }
            var index = 0
            while index < stored.count {
                let end = min(index + 500, stored.count)
                let _ = transaction.addMessages(Array(stored[index ..< end]), location: .Random)
                index = end
            }
            return stored.count
        }
    }
}
