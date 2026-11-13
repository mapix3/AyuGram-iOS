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
    private var loadingAvatars = Set<String>()
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

    private var primaryId: AccountRecordId?

    func update(primary: AccountRecordId?, accounts: [(AccountRecordId, Account)]) {
        self.primaryId = primary
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
                guard let self, let account else {
                    return
                }
                let enabled = AyuGramBackgroundNotifier.isEnabled || id != self.primaryId
                for (rawMessages, _, notify, _) in list {
                    let messages = rawMessages.map { EngineMessage($0) }
                    guard notify, let first = messages.first else {
                        continue
                    }
                    if let peer = first.enginePeers[first.id.peerId] ?? first.author {
                        let _ = self.avatarData(account: account, accountId: id, peer: peer)
                    }
                    if !enabled {
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
                    let pictureMessage = messages.first(where: { AyuGramBackgroundNotifier.picture(in: $0) != nil })
                    self.post(account: account, accountId: id, accountPeerId: accountPeerId, message: primary, pictureMessage: pictureMessage, count: messages.count)
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
        let avatarData = (chatPeer ?? message.author).flatMap { self.avatarData(account: account, accountId: accountId, peer: $0) }
        guard let pictureMessage, let representation = AyuGramBackgroundNotifier.pictureRepresentation(in: pictureMessage, side: 300) else {
            self.deliver(content: content, identifier: identifier, title: title, conversationId: conversationId, avatar: avatarData, picture: nil)
            return
        }
        if let path = TelegramEngine(account: account).resources.completedResourcePath(id: EngineMediaResource(representation.resource).id), let value = try? Data(contentsOf: URL(fileURLWithPath: path)), UIImage(data: value) != nil {
            self.deliver(content: content, identifier: identifier, title: title, conversationId: conversationId, avatar: avatarData, picture: value)
            return
        }
        let _ = (AyuGramBackgroundNotifier.loadPicture(account: account, message: pictureMessage, side: 300, timeout: 2.5)
        |> take(1)).start(next: { [weak self] picture in
            if picture == nil {
                content.categoryIdentifier = "ayu-" + category
                userInfo["ayuPictureId"] = pictureMessage.id.id
                content.userInfo = userInfo
            }
            self?.deliver(content: content, identifier: identifier, title: title, conversationId: conversationId, avatar: avatarData, picture: picture)
        })
    }

    private static let avatarSide: CGFloat = 512.0

    private static let avatarDirectory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ayu-avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }()

    private static func isRoundedRect(_ peer: EnginePeer) -> Bool {
        if case let .channel(channel) = peer, channel.isForumOrMonoForum {
            return true
        }
        return false
    }

    private static func renderAvatar(data: Data, roundedRect: Bool) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0.0, image.size.height > 0.0 else {
            return nil
        }
        let side = AyuGramBackgroundNotifier.avatarSide
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let rect = CGRect(origin: CGPoint(), size: CGSize(width: side, height: side))
        return UIGraphicsImageRenderer(size: rect.size, format: format).pngData(actions: { _ in
            if roundedRect {
                UIBezierPath(roundedRect: rect, cornerRadius: floor(side * 0.25)).addClip()
            } else {
                UIBezierPath(ovalIn: rect).addClip()
            }
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(origin: CGPoint(x: (side - size.width) / 2.0, y: (side - size.height) / 2.0), size: size))
        })
    }

    private func avatarData(account: Account, accountId: AccountRecordId, peer: EnginePeer) -> Data? {
        guard let representation = largestImageRepresentation(peer.profileImageRepresentations) else {
            let side = floor(AyuGramBackgroundNotifier.avatarSide / max(1.0, UIScreen.main.scale))
            var result: UIImage?
            let _ = peerAvatarCompleteImage(account: account, peer: peer, size: CGSize(width: side, height: side), font: avatarPlaceholderFont(size: floor(side * 0.4))).start(next: { image in
                result = image
            })
            return result?.pngData()
        }
        let prefix = "\(accountId.int64)_\(peer.id.toInt64())_"
        let resourceId = EngineMediaResource(representation.resource).id.stringRepresentation
        let name = prefix + String(resourceId.map { $0.isLetter || $0.isNumber ? $0 : "-" }) + ".png"
        let url = AyuGramBackgroundNotifier.avatarDirectory.appendingPathComponent(name)
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            return data
        }
        if self.loadingAvatars.contains(name) {
            return nil
        }
        guard let peerReference = PeerReference(peer._asPeer()) else {
            return nil
        }
        self.loadingAvatars.insert(name)
        let roundedRect = AyuGramBackgroundNotifier.isRoundedRect(peer)
        let _ = (AyuGramBackgroundNotifier.loadResource(account: account, reference: .avatar(peer: peerReference, resource: representation.resource), resource: EngineMediaResource(representation.resource), userLocation: .other, userContentType: .avatar, timeout: 30.0)
        |> take(1)).start(next: { [weak self] data in
            self?.loadingAvatars.remove(name)
            guard let data, let rendered = AyuGramBackgroundNotifier.renderAvatar(data: data, roundedRect: roundedRect) else {
                return
            }
            if let files = try? FileManager.default.contentsOfDirectory(atPath: AyuGramBackgroundNotifier.avatarDirectory.path) {
                for file in files where file.hasPrefix(prefix) && file != name {
                    try? FileManager.default.removeItem(at: AyuGramBackgroundNotifier.avatarDirectory.appendingPathComponent(file))
                }
            }
            try? rendered.write(to: url, options: .atomic)
        })
        return nil
    }

    private static func pictureRepresentation(in message: EngineMessage, side: Int32) -> TelegramMediaImageRepresentation? {
        guard let image = AyuGramBackgroundNotifier.picture(in: message) else {
            return nil
        }
        return imageRepresentationLargerThan(image.representations, size: PixelDimensions(width: side, height: side)) ?? largestImageRepresentation(image.representations)
    }

    private static func loadResource(account: Account, reference: MediaResourceReference, resource: EngineMediaResource, userLocation: MediaResourceUserLocation, userContentType: MediaResourceUserContentType, timeout timeoutValue: Double) -> Signal<Data?, NoError> {
        let engine = TelegramEngine(account: account)
        let signal = Signal<Data?, NoError> { subscriber in
            let priorityDisposable = engine.resources.pushPriorityDownload(resourceId: resource.id.stringRepresentation, priority: 2)
            let fetchDisposable = engine.resources.fetch(reference: reference, userLocation: userLocation, userContentType: userContentType).start()
            let dataDisposable = (engine.resources.data(resource: resource)
            |> filter { $0.isComplete }
            |> take(1)).start(next: { data in
                if let value = try? Data(contentsOf: URL(fileURLWithPath: data.path)), UIImage(data: value) != nil {
                    subscriber.putNext(value)
                } else {
                    subscriber.putNext(nil)
                }
                subscriber.putCompletion()
            })
            return ActionDisposable {
                priorityDisposable.dispose()
                fetchDisposable.dispose()
                dataDisposable.dispose()
            }
        }
        return signal
        |> timeout(timeoutValue, queue: Queue.mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
    }

    private static func loadPicture(account: Account, message: EngineMessage, side: Int32, timeout: Double) -> Signal<Data?, NoError> {
        guard let image = AyuGramBackgroundNotifier.picture(in: message), let representation = AyuGramBackgroundNotifier.pictureRepresentation(in: message, side: side) else {
            return .single(nil)
        }
        let reference = AnyMediaReference.message(message: MessageReference(message._asMessage()), media: image).resourceReference(representation.resource)
        return AyuGramBackgroundNotifier.loadResource(account: account, reference: reference, resource: EngineMediaResource(representation.resource), userLocation: .peer(message.id.peerId), userContentType: .image, timeout: timeout)
    }

    static let pictureActionIdentifier = "ayuPicture"

    static var pictureActionTitle: String {
        return i18n("Ayu.NotificationPicture", AyuGramBackgroundNotifier.current?.presentationData()?.strings.baseLanguageCode ?? "en")
    }

    func loadPicture(notification: UNNotification, completion: @escaping () -> Void) {
        let request = notification.request
        let userInfo = request.content.userInfo
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            completion()
            return
        }
        content.sound = nil
        let restore: (Data?) -> Void = { picture in
            if let picture {
                let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ayu-attachment-" + request.identifier.replacingOccurrences(of: ":", with: "-") + ".jpg")
                if (try? picture.write(to: url)) != nil, let value = try? UNNotificationAttachment(identifier: "attachment", url: url, options: nil) {
                    content.attachments = [value]
                    if content.categoryIdentifier.hasPrefix("ayu-") {
                        content.categoryIdentifier = String(content.categoryIdentifier.dropFirst(4))
                    }
                }
            }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: nil), withCompletionHandler: { _ in
                Queue.mainQueue().async {
                    completion()
                }
            })
        }
        guard let accountIdValue = userInfo["accountId"] as? Int64, let account = self.accounts[AccountRecordId(rawValue: accountIdValue)], let peerIdValue = userInfo["peerId"] as? Int64, let namespace = userInfo["messageId.namespace"] as? Int32, let id = userInfo["ayuPictureId"] as? Int32 else {
            restore(nil)
            return
        }
        let messageId = EngineMessage.Id(peerId: EnginePeer.Id(peerIdValue), namespace: namespace, id: id)
        let _ = (TelegramEngine(account: account).data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
        |> mapToSignal { message -> Signal<Data?, NoError> in
            guard let message else {
                return .single(nil)
            }
            return AyuGramBackgroundNotifier.loadPicture(account: account, message: message, side: 500, timeout: 20.0)
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { picture in
            restore(picture)
        })
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

    private func deliver(content: UNMutableNotificationContent, identifier: String, title: String, conversationId: String, avatar: Data?, picture: Data?) {
        let plain = (content.copy() as? UNNotificationContent) ?? content
        var result: UNNotificationContent = content
        let allowsCommunication = AyuGramSecurity.allowsCommunicationNotifications
        var attachment: (data: Data, pathExtension: String)?
        if let picture {
            attachment = (picture, "jpg")
        } else if let avatar, !allowsCommunication {
            attachment = (avatar, "png")
        }
        if let attachment {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ayu-attachment-" + identifier.replacingOccurrences(of: ":", with: "-") + "." + attachment.pathExtension)
            if (try? attachment.data.write(to: url)) != nil, let value = try? UNNotificationAttachment(identifier: "attachment", url: url, options: nil) {
                content.attachments = [value]
            }
        }
        if let avatar, allowsCommunication {
            let image = INImage(imageData: avatar)
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
