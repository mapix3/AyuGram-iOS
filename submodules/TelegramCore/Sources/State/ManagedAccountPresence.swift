import SGSimpleSettings
import Foundation
internal import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    private var ghostOfflineTimer: SignalKitTimer?
    private let ghostOfflineDisposable = MetaDisposable()
    
    private var wasOnline: Bool = false
    private var requestedOnline: Bool = false
    private var ayuSettingsObserver: NSObjectProtocol?
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network
        self.ayuSettingsObserver = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { [weak self] in
                guard let self = self else { return }
                self.applyRequestedPresence()
            }
        }
        
        self.shouldKeepOnlinePresenceDisposable = (shouldKeepOnlinePresence
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            self.requestedOnline = value
            self.applyRequestedPresence()
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        if let observer = self.ayuSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
        self.ghostOfflineTimer?.invalidate()
        self.ghostOfflineDisposable.dispose()
    }
    
    private func applyRequestedPresence() {
        let suppressed = AyuGramSettings.shared.snapshot.suppressOnline
        let value = self.requestedOnline && !suppressed
        if self.wasOnline != value {
            self.wasOnline = value
            self.updatePresence(value)
        }
        let keepOffline = self.requestedOnline && suppressed
        if keepOffline {
            if self.ghostOfflineTimer == nil {
                let timer = SignalKitTimer(timeout: 15.0, repeat: true, completion: { [weak self] in
                    self?.sendGhostOffline()
                }, queue: self.queue)
                self.ghostOfflineTimer = timer
                timer.start()
                self.sendGhostOffline()
            }
        } else if let timer = self.ghostOfflineTimer {
            timer.invalidate()
            self.ghostOfflineTimer = nil
            self.sendGhostOffline()
        }
    }

    private func sendGhostOffline() {
        guard AyuGramSettings.shared.snapshot.suppressOnline else {
            return
        }
        self.ghostOfflineDisposable.set((self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }).start())
    }

    private func updatePresence(_ requestedOnline: Bool) {
        let isOnline = requestedOnline && !AyuGramSettings.shared.snapshot.suppressOnline
        self.onlineTimer?.invalidate()
        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            let privacy = AyuGramSettings.shared.snapshot
            Logger.shared.log("AyuGhost", "updateStatus online ghost=\(privacy.ghostMode) online=\(privacy.suppressOnline)")
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
