import Foundation

// Isolate the new Foundation-only store from unrelated application dependencies.
final class SGSimpleSettings {
    static let shared = SGSimpleSettings()
    let ayuGram = AyuGramSettings()
}

@main
struct AyuGramSettingsTests {
    static func main() {
        let suite = "AyuGramTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AyuGramSettings(defaults: defaults)
        assert(store.snapshot == AyuGramPrivacySettings())
        store.update { $0.antiTyping = true; $0.ghostMode = true }
        let ghost = store.snapshot
        assert(ghost.suppressRead && ghost.suppressOnline && ghost.suppressTyping)
        assert(ghost.suppressRecording && ghost.suppressUploading && ghost.suppressStoryViews)
        assert(!ghost.messageHistory, "Ghost Mode must never opt into keeping message content")
        store.update { $0.ghostMode = false }
        assert(store.snapshot.suppressTyping && !store.snapshot.suppressRead)
        assert(AyuGramSettings(defaults: defaults).snapshot == store.snapshot)

        // Concurrent modifications of distinct fields must not overwrite one another.
        DispatchQueue.concurrentPerform(iterations: 4) { index in
            store.update { value in
                switch index {
                case 0: value.antiRead = true
                case 1: value.antiOnline = true
                case 2: value.antiRecording = true
                default: value.antiUploading = true
                }
            }
        }
        assert(store.snapshot.suppressRead && store.snapshot.suppressOnline)
        assert(store.snapshot.suppressRecording && store.snapshot.suppressUploading)
        var observed = false
        let observer = NotificationCenter.default.addObserver(forName: AyuGramSettings.didChange, object: nil, queue: nil) { _ in
            // This would deadlock if changes were published while holding the store lock.
            observed = store.snapshot.storyPrivacy
        }
        store.update { $0.storyPrivacy = true }
        NotificationCenter.default.removeObserver(observer)
        assert(observed)
        #if AYUGRAM_CLIENT_EXTRAS
        let privacyBefore = store.snapshot
        assert(store.client == AyuGramClientSettings())
        store.updateClient { $0.localPremium = true; $0.maxPinnedChats = 99 }
        assert(store.client.localPremium && store.client.pinnedChatLimit == 30)
        assert(store.snapshot == privacyBefore, "Client preferences must preserve existing privacy settings")
        assert(AyuGramSettings(defaults: defaults).client == store.client)
        store.updateClient { $0.maxPinnedChats = -10 }
        assert(store.client.pinnedChatLimit == 5)
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            if index == 0 { store.updateClient { $0.maxPinnedChats = 17 } }
            else { store.update { $0.messageHistory = true } }
        }
        assert(store.client.pinnedChatLimit == 17 && store.client.localPremium)
        assert(store.snapshot.messageHistory && store.snapshot.antiRead)
        #if AYUGRAM_REFINEMENTS
        store.setLocalStatus(peerId: 1001, status: AyuGramLocalStatus(fileId: 9001, expirationDate: nil))
        store.setLocalStatus(peerId: 1002, status: AyuGramLocalStatus(fileId: 9002, expirationDate: nil))
        assert(store.localStatus(peerId: 1001)?.fileId == 9001)
        assert(store.localStatus(peerId: 1002)?.fileId == 9002)
        assert(AyuGramSettings(defaults: defaults).localStatus(peerId: 1001)?.fileId == 9001)
        store.setLocalStatus(peerId: 1001, status: AyuGramLocalStatus(fileId: nil, expirationDate: nil))
        assert(store.localStatus(peerId: 1001) != nil && store.localStatus(peerId: 1001)?.fileId == nil)
        store.setLocalStatus(peerId: 1002, status: AyuGramLocalStatus(fileId: 9002, expirationDate: 1))
        assert(store.localStatus(peerId: 1002) == nil)
        store.updateClient { $0.localPremium = false }
        assert(store.localStatus(peerId: 1001) == nil)
        store.updateClient { $0.localPremium = true }
        store.setLocalStatus(peerId: 1001, status: nil)
        assert(store.localStatus(peerId: 1001) == nil)
        assert(store.client.pinnedChatLimit == 17 && store.snapshot.antiRead)
        print("Local emoji status: account isolation, persistence, expiration and disabling passed")
        #endif
        #if AYUGRAM_EXTRA_SETTINGS
        assert(store.extra == AyuGramExtraSettings(), "New options start with their defaults")
        assert(store.extra.ignoreCopyProtection && store.extra.allowScreenshots && store.extra.readOnSend && store.extra.offlineAfterSending)
        defaults.set(Data(#"{"allowScreenshots":false}"#.utf8), forKey: "swiftgram.ayuGram.extra.v1")
        let partial = AyuGramSettings(defaults: defaults).extra
        assert(!partial.allowScreenshots && partial.ignoreCopyProtection && partial.offlineAfterSending && partial.ghostQuickToggle, "Missing keys keep their defaults")
        let privacyBeforeExtra = store.snapshot
        let clientBeforeExtra = store.client
        store.updateExtra { $0.readOnSend = false; $0.allowScreenshots = false }
        assert(!store.extra.readOnSend && !store.extra.allowScreenshots && store.extra.ignoreCopyProtection)
        assert(store.snapshot == privacyBeforeExtra && store.client == clientBeforeExtra, "Extra options preserve other settings")
        assert(AyuGramSettings(defaults: defaults).extra == store.extra)
        assert(defaults.object(forKey: AyuGramSettings.allowScreenshotsDefaultsKey) as? Bool == false, "Screenshot option is mirrored for Objective-C")
        store.setGhostMode(true)
        assert(store.snapshot.ghostMode && store.snapshot.suppressStoryViews && store.snapshot.suppressOnline)
        store.setGhostMode(false)
        assert(!store.snapshot.ghostMode && store.snapshot.antiRead, "Quick toggle keeps individual switches")
        print("AyuGram extra options: defaults, partial decoding, persistence and quick toggle passed")
        #endif
        print("AyuGram client preferences: persistence, bounds and privacy preservation passed")
        #endif
        print("AyuGram settings: persistence, Ghost Mode, concurrency and observer tests passed")
    }
}
