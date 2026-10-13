import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

public func ayuEmojiFileIdFromLink(_ url: String) -> Int64? {
    guard let components = URLComponents(string: url), components.scheme == "https",
          components.host == "t.me", components.path.hasPrefix("/addemoji/"),
          components.path.count > "/addemoji/".count,
          let fragment = components.fragment, fragment.hasPrefix("ayuemoji_"),
          let id = Int64(fragment.dropFirst("ayuemoji_".count)), id != 0 else { return nil }
    return id
}

func ayuPrepareEmojiLinks(account: Account, peerId: PeerId, messages: [(Bool, EnqueueMessage)]) -> Signal<[(Bool, EnqueueMessage)], NoError> {
    guard AyuGramSettings.shared.client.localPremium,
          peerId.namespace != Namespaces.Peer.SecretChat else { return .single(messages) }
    return account.postbox.transaction { transaction -> Bool in
        transaction.getPeer(account.peerId)?.isPremium ?? false
    }
    |> map { isPremium in
        if isPremium { return messages }
        return messages.map { transformed, message in
            guard case let .message(text, _, _, _, _, _, _, _, _, _) = message else { return (transformed, message) }
            return (transformed, message.withUpdatedAttributes { attributes in
                attributes.map { attribute -> MessageAttribute in
                    guard let attribute = attribute as? TextEntitiesMessageAttribute else { return attribute }
                    let entities = attribute.entities
                    guard entities.contains(where: { if case .CustomEmoji = $0.type { return true }; return false }) else { return attribute }
                    return TextEntitiesMessageAttribute(entities: entities, ayuLocalEmojiText: text)
                }
            })
        }
    }
}

func ayuMergeLocalEmojiAttributes(text: String, previous: [MessageAttribute], updated: inout [MessageAttribute]) {
    guard let local = previous.compactMap({ $0 as? TextEntitiesMessageAttribute }).first(where: { $0.ayuLocalEmojiText == text }) else { return }
    let native = updated.compactMap { $0 as? TextEntitiesMessageAttribute }.first
    if native?.ayuLocalEmojiText != nil { return }
    if native?.ayuWireEntities.contains(where: { if case .CustomEmoji = $0.type { return true }; return false }) == true { return }
    let custom = local.entities.filter { if case .CustomEmoji = $0.type { return true }; return false }
    guard !custom.isEmpty else { return }
    let merged = TextEntitiesMessageAttribute(entities: (native?.ayuWireEntities ?? []) + custom, ayuLocalEmojiText: text)
    if let index = updated.firstIndex(where: { $0 is TextEntitiesMessageAttribute }) {
        updated[index] = merged
    } else {
        updated.append(merged)
    }
}

public extension Message {
    var ayuDisplayMedia: [Media] {
        let markerURLs = Set(attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap { $0.ayuWireEntities }.compactMap { entity -> String? in
            guard case let .TextUrl(url) = entity.type, ayuEmojiFileIdFromLink(url) != nil else { return nil }
            return url.components(separatedBy: "#")[0]
        })
        guard !markerURLs.isEmpty else { return media }
        return media.filter { media in
            guard let page = media as? TelegramMediaWebpage, case let .Loaded(content) = page.content else { return true }
            return !markerURLs.contains(content.url.components(separatedBy: "#")[0])
        }
    }
}
