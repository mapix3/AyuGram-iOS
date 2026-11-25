import Foundation

public enum SGNotificationOverride: Equatable {
    case none
    case silenced
    case disabled
}

extension SGSimpleSettings {
    private func notificationAction(value: String, exceptionsKey: String, chatId: Int64?) -> String {
        if let chatId, let exceptions = UserDefaults(suiteName: APP_GROUP_IDENTIFIER)?.dictionary(forKey: exceptionsKey) as? [String: String], let exception = exceptions["\(chatId)"] {
            return exception
        }
        return value
    }

    public func notificationOverride(isPinned: Bool, isMentionOrReply: Bool, chatId: Int64?) -> SGNotificationOverride {
        var actions: [String] = []
        if isPinned {
            actions.append(self.notificationAction(value: self.pinnedMessageNotifications, exceptionsKey: Keys.pinnedMessageNotifications.rawValue + "Exceptions", chatId: chatId))
        }
        if isMentionOrReply {
            actions.append(self.notificationAction(value: self.mentionsAndRepliesNotifications, exceptionsKey: Keys.mentionsAndRepliesNotifications.rawValue + "Exceptions", chatId: chatId))
        }
        if actions.contains(PinnedMessageNotificationsSettings.disabled.rawValue) {
            return .disabled
        }
        if actions.contains(PinnedMessageNotificationsSettings.silenced.rawValue) {
            return .silenced
        }
        return .none
    }
}
