import Foundation
import UIKit
import AVFAudio
import UserNotifications
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import LocalizedPeerData
import SGSimpleSettings

private func ayuGramSilentWav() -> Data {
    let sampleRate: UInt32 = 8000
    let samples: UInt32 = sampleRate
    let dataSize = samples * 2
    var data = Data()
    func append(_ value: UInt32) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 4))
    }
    func append16(_ value: UInt16) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 2))
    }
    data.append(contentsOf: Array("RIFF".utf8))
    append(36 + dataSize)
    data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8))
    append(16)
    append16(1)
    append16(1)
    append(sampleRate)
    append(sampleRate * 2)
    append16(2)
    append16(16)
    data.append(contentsOf: Array("data".utf8))
    append(dataSize)
    data.append(Data(count: Int(dataSize)))
    return data
}

final class AyuGramKeepAlive {
    private let beginBackgroundTask: (String, @escaping () -> Void) -> UIBackgroundTaskIdentifier?
    private let endBackgroundTask: (UIBackgroundTaskIdentifier) -> Void
    private let updated: (Bool) -> Void

    private var player: AVAudioPlayer?
    private var isPlaying = false
    private var inForeground = true
    private var telegramAudioActive = false
    private var interrupted = false
    private var mode: Int32
    private var deadlineTimer: SwiftSignalKit.Timer?
    private var retryTimer: SwiftSignalKit.Timer?
    private var retryTask: UIBackgroundTaskIdentifier?
    private var observers: [NSObjectProtocol] = []

    private(set) var isWanted = false {
        didSet {
            if self.isWanted != oldValue {
                self.updated(self.isWanted)
            }
        }
    }

    init(beginBackgroundTask: @escaping (String, @escaping () -> Void) -> UIBackgroundTaskIdentifier?, endBackgroundTask: @escaping (UIBackgroundTaskIdentifier) -> Void, updated: @escaping (Bool) -> Void) {
        self.beginBackgroundTask = beginBackgroundTask
        self.endBackgroundTask = endBackgroundTask
        self.updated = updated
        self.mode = AyuGramSettings.shared.extra.backgroundKeepAlive

        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main, using: { [weak self] notification in
            guard let self, let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: raw) else {
                return
            }
            self.handleInterruption(began: type == .began)
        }))
        self.observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance(), queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            self.player = nil
            self.isPlaying = false
            self.apply()
        }))
        self.observers.append(center.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            let mode = AyuGramSettings.shared.extra.backgroundKeepAlive
            if mode != self.mode {
                self.mode = mode
                if !self.inForeground {
                    self.enterBackground()
                }
            }
        }))
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.deadlineTimer?.invalidate()
        self.retryTimer?.invalidate()
    }

    func update(inForeground: Bool) {
        if self.inForeground == inForeground {
            return
        }
        self.inForeground = inForeground
        if inForeground {
            self.deadlineTimer?.invalidate()
            self.deadlineTimer = nil
            self.interrupted = false
            self.isWanted = false
            self.apply()
        } else {
            self.enterBackground()
        }
    }

    func update(telegramAudioActive: Bool) {
        if self.telegramAudioActive == telegramAudioActive {
            return
        }
        self.telegramAudioActive = telegramAudioActive
        self.apply()
    }

    private func enterBackground() {
        self.deadlineTimer?.invalidate()
        self.deadlineTimer = nil
        if self.mode == 0 {
            self.isWanted = false
        } else {
            self.isWanted = true
            if self.mode > 0 {
                let timer = SwiftSignalKit.Timer(timeout: Double(self.mode) * 60.0, repeat: false, completion: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.deadlineTimer = nil
                    self.isWanted = false
                    self.apply()
                }, queue: Queue.mainQueue())
                self.deadlineTimer = timer
                timer.start()
            }
        }
        self.apply()
    }

    private func handleInterruption(began: Bool) {
        guard self.isWanted else {
            return
        }
        if began {
            if self.telegramAudioActive {
                return
            }
            self.interrupted = true
            self.isPlaying = false
            self.scheduleRetry()
        } else {
            self.interrupted = false
            self.apply()
        }
    }

    private func apply() {
        let shouldPlay = self.isWanted && !self.telegramAudioActive && !self.interrupted
        if shouldPlay {
            if !self.isPlaying {
                if self.start() {
                    self.stopRetry()
                } else {
                    self.scheduleRetry()
                }
            }
        } else {
            if !self.interrupted || !self.isWanted {
                self.stopRetry()
            }
            if self.isPlaying {
                self.player?.pause()
                self.isPlaying = false
                if !self.telegramAudioActive {
                    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
                }
            }
        }
    }

    private func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            return false
        }
        if self.player == nil {
            guard let player = try? AVAudioPlayer(data: ayuGramSilentWav()) else {
                return false
            }
            player.numberOfLoops = -1
            player.volume = 0.0
            player.prepareToPlay()
            self.player = player
        }
        guard let player = self.player, player.play() else {
            return false
        }
        self.isPlaying = true
        return true
    }

    private func scheduleRetry() {
        if self.retryTask == nil {
            var taskId: UIBackgroundTaskIdentifier?
            taskId = self.beginBackgroundTask("ayugram-keepalive", { [weak self] in
                guard let self, let current = self.retryTask, current == taskId else {
                    return
                }
                self.retryTask = nil
                self.endBackgroundTask(current)
            })
            self.retryTask = taskId
        }
        if self.retryTimer == nil {
            let timer = SwiftSignalKit.Timer(timeout: 2.0, repeat: true, completion: { [weak self] in
                guard let self else {
                    return
                }
                if !self.isWanted || self.telegramAudioActive {
                    self.stopRetry()
                    return
                }
                if self.start() {
                    self.interrupted = false
                    self.stopRetry()
                }
            }, queue: Queue.mainQueue())
            self.retryTimer = timer
            timer.start()
        }
    }

    private func stopRetry() {
        self.retryTimer?.invalidate()
        self.retryTimer = nil
        if let retryTask = self.retryTask {
            self.retryTask = nil
            self.endBackgroundTask(retryTask)
        }
    }
}

final class AyuGramBackgroundNotifier {
    private let presentationData: () -> PresentationData?
    private let disposables = DisposableDict<AccountRecordId>()
    private var accountIds = Set<AccountRecordId>()

    init(presentationData: @escaping () -> PresentationData?) {
        self.presentationData = presentationData
    }

    deinit {
        self.disposables.dispose()
    }

    private static var isEnabled: Bool {
        if AyuGramSettings.shared.extra.backgroundKeepAlive == 0 {
            return false
        }
        if let barkKey = UserDefaults.standard.string(forKey: "ayuGram.pushRelay.barkKey"), !barkKey.isEmpty {
            return false
        }
        return UIApplication.shared.applicationState != .active
    }

    func update(accounts: [(AccountRecordId, Account)]) {
        let ids = Set(accounts.map { $0.0 })
        for id in self.accountIds.subtracting(ids) {
            self.disposables.set(nil, forKey: id)
        }
        for (id, account) in accounts where !self.accountIds.contains(id) {
            let accountPeerId = account.peerId
            self.disposables.set((account.stateManager.notificationMessages
            |> deliverOnMainQueue).startStrict(next: { [weak self] list in
                guard let self, AyuGramBackgroundNotifier.isEnabled else {
                    return
                }
                for (messages, _, notify, _) in list {
                    guard notify, let first = messages.first else {
                        continue
                    }
                    self.post(accountId: id, accountPeerId: accountPeerId, message: EngineMessage(first), count: messages.count)
                }
            }), forKey: id)
        }
        self.accountIds = ids
    }

    private func post(accountId: AccountRecordId, accountPeerId: EnginePeer.Id, message: EngineMessage, count: Int) {
        guard let presentationData = self.presentationData() else {
            return
        }
        if message.author?.id == accountPeerId && !message.flags.contains(.WasScheduled) {
            return
        }
        for media in message.media {
            if let action = media as? TelegramMediaAction, case .messageAutoremoveTimeoutUpdated = action.action {
                return
            }
        }
        let strings = presentationData.strings
        let order = presentationData.nameDisplayOrder
        let chatPeer = message.peers[message.id.peerId].flatMap { EnginePeer($0) }
        let authorTitle = message.author?.displayTitle(strings: strings, displayOrder: order) ?? ""
        var title = authorTitle
        var prefix = ""
        if let chatPeer {
            switch chatPeer {
            case .secretChat, .user:
                break
            case let .channel(channel):
                title = chatPeer.displayTitle(strings: strings, displayOrder: order)
                if case .group = channel.info, !authorTitle.isEmpty {
                    prefix = authorTitle + ": "
                }
            default:
                title = chatPeer.displayTitle(strings: strings, displayOrder: order)
                if !authorTitle.isEmpty {
                    prefix = authorTitle + ": "
                }
            }
        }
        let description = descriptionStringForMessage(contentSettings: ContentSettings.default, message: message, strings: strings, nameDisplayOrder: order, dateTimeFormat: presentationData.dateTimeFormat, accountPeerId: accountPeerId).0.string
        var body = prefix + description
        if count > 1 {
            body += " (+\(count - 1))"
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = "ayu-\(accountId.int64)-\(message.id.peerId.toInt64())"
        var userInfo: [AnyHashable: Any] = [
            "accountId": accountId.int64,
            "peerId": message.id.peerId.toInt64(),
            "messageId.namespace": message.id.namespace,
            "messageId.id": message.id.id
        ]
        if let threadId = message.threadId {
            userInfo["threadId"] = threadId
        }
        content.userInfo = userInfo
        let isSilent = message.attributes.contains(where: { attribute in
            if let attribute = attribute as? NotificationInfoMessageAttribute {
                return attribute.flags.contains(.muted)
            }
            return false
        })
        if !isSilent {
            content.sound = .default
        }
        let identifier = "ayu-\(accountId.int64)-\(message.id.peerId.toInt64())-\(message.id.namespace)-\(message.id.id)"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil), withCompletionHandler: nil)
    }
}
