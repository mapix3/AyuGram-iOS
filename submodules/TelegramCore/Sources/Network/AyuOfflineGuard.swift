import Foundation
import SGSimpleSettings
internal import TelegramApi
import SwiftSignalKit
import MtProtoKit

final class AyuOfflineGuard {
    weak var network: Network?
    private let queue = Queue()
    private var pending = false
    private var lastSent: Double = 0.0
    private let disposable = MetaDisposable()

    private static let passiveNamespaces: Set<String> = ["updates", "help", "langpack", "upload", "auth"]
    private static let passivePrefixes: [String] = ["get", "search", "check", "resolve", "export", "fetch"]
    private static let activeNames: Set<String> = ["messages.getMessagesViews", "stories.incrementStoryViews", "messages.getBotCallbackAnswer", "messages.requestWebView", "messages.requestSimpleWebView", "messages.requestAppWebView", "messages.requestMainWebView", "messages.startBot", "channels.joinChannel", "messages.importChatInvite"]

    static func isActivity(_ name: String) -> Bool {
        if name == "account.updateStatus" {
            return false
        }
        if activeNames.contains(name) {
            return true
        }
        let parts = name.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else {
            return false
        }
        if passiveNamespaces.contains(String(parts[0])) {
            return false
        }
        let method = String(parts[1])
        for prefix in passivePrefixes where method.hasPrefix(prefix) {
            return false
        }
        return true
    }

    func noteRequest(_ name: String) {
        guard AyuGramSettings.shared.snapshot.suppressOnline, AyuOfflineGuard.isActivity(name) else {
            return
        }
        self.queue.async { [weak self] in
            self?.schedule(after: name)
        }
    }

    private func schedule(after name: String) {
        if self.pending {
            return
        }
        self.pending = true
        let delay = max(0.5, self.lastSent + 3.0 - CFAbsoluteTimeGetCurrent())
        Logger.shared.log("AyuGhost", "offline after \(name) in \(delay)")
        self.queue.after(delay) { [weak self] in
            self?.fire()
        }
    }

    private func fire() {
        self.pending = false
        self.send()
    }

    private func send() {
        guard AyuGramSettings.shared.snapshot.suppressOnline, let network = self.network else {
            return
        }
        self.lastSent = CFAbsoluteTimeGetCurrent()
        self.disposable.set((network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }).start())
    }
}
