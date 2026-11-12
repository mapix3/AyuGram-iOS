import Foundation
import UIKit
import AVFAudio
import UserNotifications
import Intents
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import LocalizedPeerData
import SGSimpleSettings
import SGStrings
import AvatarNode

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
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [AyuGramBackgroundNotifier.terminatedIdentifier])
    }

    deinit {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.retryTimer?.invalidate()
    }

    func update(inForeground: Bool) {
        if self.inForeground == inForeground {
            return
        }
        self.inForeground = inForeground
        if inForeground {
            self.interrupted = false
            self.isWanted = false
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [AyuGramBackgroundNotifier.terminatedIdentifier])
        } else {
            self.isWanted = true
        }
        self.apply()
    }

    func update(telegramAudioActive: Bool) {
        if self.telegramAudioActive == telegramAudioActive {
            return
        }
        self.telegramAudioActive = telegramAudioActive
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
    static let terminatedIdentifier = "ayu-terminated"
    private(set) static weak var current: AyuGramBackgroundNotifier?

    private let presentationData: () -> PresentationData?
    private let disposables = DisposableDict<AccountRecordId>()
    private var accountIds = Set<AccountRecordId>()
    private let readDisposables = DisposableDict<AccountRecordId>()
    private var accounts: [AccountRecordId: Account] = [:]
    private var seenGroups = Set<String>()
    private var seenGroupOrder: [String] = []
    private var pending: [AccountRecordId: [EnginePeer.Id: [(identifier: String, index: EngineMessage.Index)]]] = [:]

    init(presentationData: @escaping () -> PresentationData?) {
        self.presentationData = presentationData
        AyuGramBackgroundNotifier.current = self
    }

    deinit {
        self.disposables.dispose()
        self.readDisposables.dispose()
    }

    private static var usesBark: Bool {
        if let barkKey = UserDefaults.standard.string(forKey: "ayuGram.pushRelay.barkKey"), !barkKey.isEmpty {
            return true
        }
        return false
    }

    private static var isEnabled: Bool {
        return UIApplication.shared.applicationState != .active
    }

    func notifyTerminated() {
        if AyuGramBackgroundNotifier.usesBark {
            return
        }
        let locale = self.presentationData()?.strings.baseLanguageCode ?? "en"
        let content = UNMutableNotificationContent()
        content.title = "AyuGram"
        content.body = i18n("Ayu.TerminatedNotice", locale)
        content.sound = .default
        let semaphore = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: AyuGramBackgroundNotifier.terminatedIdentifier, content: content, trigger: nil), withCompletionHandler: { _ in
            semaphore.signal()
        })
        let _ = semaphore.wait(timeout: .now() + 1.0)
    }

    func update(accounts: [(AccountRecordId, Account)]) {
        let ids = Set(accounts.map { $0.0 })
        for id in self.accountIds.subtracting(ids) {
            self.disposables.set(nil, forKey: id)
            self.readDisposables.set(nil, forKey: id)
            self.accounts[id] = nil
            self.pending[id] = nil
        }
        for (id, account) in accounts {
            self.accounts[id] = account
        }
        for (id, account) in accounts where !self.accountIds.contains(id) {
            let accountPeerId = account.peerId
            self.disposables.set((account.stateManager.notificationMessages
            |> deliverOnMainQueue).startStrict(next: { [weak self, weak account] list in
                guard let self, let account, AyuGramBackgroundNotifier.isEnabled else {
                    return
                }
                for (messages, _, notify, _) in list {
                    guard notify, let first = messages.first else {
                        continue
                    }
                    if let groupingKey = first.groupingKey {
                        let key = "\(id.int64)_\(first.id.peerId.toInt64())_\(groupingKey)"
                        if self.seenGroups.contains(key) {
                            continue
                        }
                        self.seenGroups.insert(key)
                        self.seenGroupOrder.append(key)
                        if self.seenGroupOrder.count > 200 {
                            self.seenGroups.remove(self.seenGroupOrder.removeFirst())
                        }
                    }
                    let primary = messages.first(where: { !$0.text.isEmpty }) ?? first
                    let pictureMessage = messages.map({ EngineMessage($0) }).first(where: { AyuGramBackgroundNotifier.picture(in: $0) != nil })
                    self.post(account: account, accountId: id, accountPeerId: accountPeerId, message: EngineMessage(primary), pictureMessage: pictureMessage, count: messages.count)
                }
            }), forKey: id)
        }
        self.accountIds = ids
    }

    private static func picture(in message: EngineMessage) -> TelegramMediaImage? {
        if message.id.peerId.namespace == Namespaces.Peer.SecretChat || message.containsSecretMedia {
            return nil
        }
        if message.attributes.contains(where: { $0 is MediaSpoilerMessageAttribute }) {
            return nil
        }
        for media in message.media {
            if let image = media as? TelegramMediaImage, !image.representations.isEmpty {
                return image
            }
        }
        return nil
    }

    private func post(account: Account, accountId: AccountRecordId, accountPeerId: EnginePeer.Id, message: EngineMessage, pictureMessage: EngineMessage?, count: Int) {
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
        var category = "r"
        if let chatPeer {
            switch chatPeer {
            case .secretChat, .user:
                break
            case let .channel(channel):
                title = chatPeer.displayTitle(strings: strings, displayOrder: order)
                if case .group = channel.info {
                    category = "gr"
                    if !authorTitle.isEmpty {
                        prefix = authorTitle + ": "
                    }
                } else {
                    category = "c"
                }
            default:
                category = "gr"
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
        content.categoryIdentifier = category
        content.threadIdentifier = "ayu-\(accountId.int64)-\(message.id.peerId.toInt64())"
        var userInfo: [AnyHashable: Any] = [
            "accountId": accountId.int64,
            "peerId": message.id.peerId.toInt64(),
            "messageId.namespace": message.id.namespace,
            "messageId.id": message.id.id
        ]
        if let threadId = message.threadId, case let .channel(channel) = chatPeer, channel.isForumOrMonoForum {
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
        let identifier = "m\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)_\(accountId.int64)"
        self.track(accountId: accountId, peerId: message.id.peerId, identifier: identifier, index: message.index)
        let conversationId = "\(message.id.peerId.toInt64())"
        let needsAvatar = AyuGramSecurity.allowsCommunicationNotifications
        let avatarPeer = chatPeer ?? message.author
        var pictureSource: (EngineMessage, TelegramMediaImage, TelegramMediaImageRepresentation)?
        if let pictureMessage, let image = AyuGramBackgroundNotifier.picture(in: pictureMessage), let representation = imageRepresentationLargerThan(image.representations, size: PixelDimensions(width: 500, height: 500)) ?? largestImageRepresentation(image.representations) {
            pictureSource = (pictureMessage, image, representation)
        }
        var avatarImage: UIImage?
        var pictureData: Data?
        var avatarDone = avatarPeer == nil
        var pictureDone = pictureSource == nil
        var delivered = false
        let disposables = DisposableSet()
        let finish: (Bool) -> Void = { [weak self] force in
            if delivered {
                return
            }
            if !force {
                if !pictureDone {
                    return
                }
                if !avatarDone && (needsAvatar || pictureData == nil) {
                    return
                }
            }
            delivered = true
            disposables.dispose()
            self?.deliver(content: content, identifier: identifier, title: title, conversationId: conversationId, avatar: avatarImage, picture: pictureData)
        }
        Queue.mainQueue().after(pictureSource == nil ? 1.5 : 4.0, {
            finish(true)
        })
        if let (pictureMessage, image, representation) = pictureSource {
            let engine = TelegramEngine(account: account)
            let reference = AnyMediaReference.message(message: MessageReference(pictureMessage._asMessage()), media: image).resourceReference(representation.resource)
            disposables.add(engine.resources.fetch(reference: reference, userLocation: .peer(pictureMessage.id.peerId), userContentType: .image).start())
            disposables.add((engine.resources.data(resource: EngineMediaResource(representation.resource))
            |> filter { $0.isComplete }
            |> take(1)
            |> deliverOnMainQueue).start(next: { data in
                if let value = try? Data(contentsOf: URL(fileURLWithPath: data.path)), UIImage(data: value) != nil {
                    pictureData = value
                }
                pictureDone = true
                finish(false)
            }))
        }
        if let avatarPeer {
            disposables.add((peerAvatarCompleteImage(account: account, peer: avatarPeer, size: CGSize(width: 120.0, height: 120.0))
            |> deliverOnMainQueue).start(next: { image in
                if let image {
                    avatarImage = image
                    avatarDone = true
                    finish(false)
                }
            }, completed: {
                avatarDone = true
                finish(false)
            }))
        }
        finish(false)
    }

    private func track(accountId: AccountRecordId, peerId: EnginePeer.Id, identifier: String, index: EngineMessage.Index) {
        var peers = self.pending[accountId] ?? [:]
        let isNewPeer = peers[peerId] == nil
        var list = peers[peerId] ?? []
        list.append((identifier: identifier, index: index))
        if list.count > 100 {
            list.removeFirst(list.count - 100)
        }
        peers[peerId] = list
        self.pending[accountId] = peers
        guard isNewPeer, let account = self.accounts[accountId] else {
            return
        }
        let items = peers.keys.map { TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: $0) }
        self.readDisposables.set((TelegramEngine(account: account).data.subscribe(EngineDataMap(items))
        |> deliverOnMainQueue).startStrict(next: { [weak self] counters in
            guard let self, var peers = self.pending[accountId] else {
                return
            }
            var removed: [String] = []
            for (peerId, counter) in counters {
                guard let list = peers[peerId] else {
                    continue
                }
                let remaining = list.filter { !counter.isIncomingMessageIndexRead($0.index) }
                if remaining.count == list.count {
                    continue
                }
                removed.append(contentsOf: list.filter { counter.isIncomingMessageIndexRead($0.index) }.map { $0.identifier })
                peers[peerId] = remaining.isEmpty ? nil : remaining
            }
            if !removed.isEmpty {
                self.pending[accountId] = peers
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: removed)
            }
        }), forKey: accountId)
    }

    private func deliver(content: UNMutableNotificationContent, identifier: String, title: String, conversationId: String, avatar: UIImage?, picture: Data?) {
        let plain = (content.copy() as? UNNotificationContent) ?? content
        var result: UNNotificationContent = content
        let allowsCommunication = AyuGramSecurity.allowsCommunicationNotifications
        let avatarData = avatar?.pngData()
        var attachment: (data: Data, pathExtension: String)?
        if let picture {
            attachment = (picture, "jpg")
        } else if let avatarData, !allowsCommunication {
            attachment = (avatarData, "png")
        }
        if let attachment {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ayu-attachment-" + identifier.replacingOccurrences(of: ":", with: "-") + "." + attachment.pathExtension)
            if (try? attachment.data.write(to: url)) != nil, let value = try? UNNotificationAttachment(identifier: "attachment", url: url, options: nil) {
                content.attachments = [value]
            }
        }
        if let avatarData, allowsCommunication {
            let image = INImage(imageData: avatarData)
            var components = PersonNameComponents()
            components.nickname = title
            let sender = INPerson(personHandle: INPersonHandle(value: conversationId, type: .unknown), nameComponents: components, displayName: title, image: image, contactIdentifier: nil, customIdentifier: conversationId, isMe: false, suggestionType: .none)
            let me = INPerson(personHandle: INPersonHandle(value: "0", type: .unknown), nameComponents: nil, displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: nil, isMe: true, suggestionType: .none)
            let intent = INSendMessageIntent(recipients: [me], outgoingMessageType: .outgoingMessageText, content: content.body, speakableGroupName: INSpeakableString(spokenPhrase: title), conversationIdentifier: conversationId, serviceName: nil, sender: sender, attachments: nil)
            intent.setImage(image, forParameterNamed: \.sender)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            interaction.donate(completion: nil)
            if let updated = try? content.updating(from: intent) {
                result = updated
            }
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: result, trigger: nil), withCompletionHandler: { error in
            if error != nil {
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: plain, trigger: nil), withCompletionHandler: nil)
            }
        })
    }
}
