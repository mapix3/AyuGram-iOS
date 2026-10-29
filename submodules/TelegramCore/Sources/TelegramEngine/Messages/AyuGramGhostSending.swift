import Foundation
import Postbox
import SwiftSignalKit
import SGSimpleSettings

private let ayuGhostScheduleDelay: Int32 = 12

func ayuPrepareGhostSending(account: Account, peerId: PeerId, messages: [(Bool, EnqueueMessage)]) -> Signal<[(Bool, EnqueueMessage)], NoError> {
    let extra = AyuGramSettings.shared.extra
    let silent = extra.sendsSilently
    let schedule = extra.scheduleInGhost && AyuGramSettings.shared.snapshot.ghostMode
    guard silent || schedule, peerId.namespace != Namespaces.Peer.SecretChat else {
        return .single(messages)
    }
    return account.postbox.transaction { transaction -> Bool in
        if !schedule || peerId == account.peerId {
            return false
        }
        if let user = transaction.getPeer(peerId) as? TelegramUser, user.botInfo != nil {
            return false
        }
        return true
    }
    |> map { canSchedule -> [(Bool, EnqueueMessage)] in
        let scheduleTime = Int32(Date().timeIntervalSince1970) + ayuGhostScheduleDelay
        return messages.map { transformed, message in
            return (transformed, message.withUpdatedAttributes { attributes in
                var attributes = attributes
                if silent, !attributes.contains(where: { $0 is NotificationInfoMessageAttribute }) {
                    attributes.append(NotificationInfoMessageAttribute(flags: .muted))
                }
                if canSchedule, !attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute || $0 is OutgoingQuickReplyMessageAttribute }) {
                    attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil))
                }
                return attributes
            })
        }
    }
}
