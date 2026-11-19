import Foundation
import SwiftSignalKit
import TelegramCore
import SGSimpleSettings

public struct AyuGramFakeNftItem: Equatable {
    public let nft: AyuGramProfileNft
    public let gift: StarGift.UniqueGift?

    public init(nft: AyuGramProfileNft, gift: StarGift.UniqueGift?) {
        self.nft = nft
        self.gift = gift
    }

    public var key: String {
        return self.nft.key
    }

    public var displayGift: StarGift.UniqueGift? {
        return self.gift.map(ayuGramFakeDisplayGift)
    }

    public var starGift: ProfileGiftsContext.State.StarGift? {
        guard let gift = self.displayGift else {
            return nil
        }
        return ayuGramFakeStarGift(gift, pinned: self.nft.pinned)
    }
}

public func ayuGramRawPeerId(_ peerId: EnginePeer.Id) -> Int64 {
    return peerId.id._internalGetInt64Value()
}

public func ayuGramProfileExtrasSupported(_ peerId: EnginePeer.Id) -> Bool {
    return peerId.namespace == Namespaces.Peer.CloudUser && ayuGramRawPeerId(peerId) > 0
}

public func ayuGramProfileEntry(peerId: EnginePeer.Id, refresh: Bool = true) -> AyuGramProfileEntry? {
    guard ayuGramProfileExtrasSupported(peerId) else {
        return nil
    }
    let rawId = ayuGramRawPeerId(peerId)
    if refresh {
        return AyuGramProfileRelay.shared.observe(rawId: rawId)
    }
    return AyuGramProfileRelay.shared.entry(rawId: rawId)
}

public func ayuGramFakeDisplayGift(_ gift: StarGift.UniqueGift) -> StarGift.UniqueGift {
    return gift.withResellAmounts(nil)
}

public func ayuGramFakeStarGift(_ gift: StarGift.UniqueGift, pinned: Bool) -> ProfileGiftsContext.State.StarGift {
    return ProfileGiftsContext.State.StarGift(
        gift: .unique(ayuGramFakeDisplayGift(gift)),
        reference: nil,
        fromPeer: nil,
        date: 0,
        text: nil,
        entities: nil,
        nameHidden: false,
        savedToProfile: true,
        pinnedToTop: pinned,
        convertStars: nil,
        canUpgrade: false,
        canExportDate: nil,
        upgradeStars: nil,
        transferStars: nil,
        canTransferDate: nil,
        canResaleDate: nil,
        collectionIds: nil,
        prepaidUpgradeHash: nil,
        upgradeSeparate: false,
        dropOriginalDetailsStars: nil,
        number: nil,
        isRefunded: false,
        canCraftAt: nil
    )
}

public func ayuGramProfileEntrySignal(peerId: EnginePeer.Id) -> Signal<AyuGramProfileEntry?, NoError> {
    guard ayuGramProfileExtrasSupported(peerId) else {
        return .single(nil)
    }
    let rawId = ayuGramRawPeerId(peerId)
    return Signal<AyuGramProfileEntry?, NoError> { subscriber in
        subscriber.putNext(AyuGramProfileRelay.shared.observe(rawId: rawId))
        let observer = NotificationCenter.default.addObserver(forName: AyuGramProfileRelay.didChange, object: nil, queue: .main, using: { notification in
            guard let ids = notification.userInfo?["peerIds"] as? [Int64], ids.contains(rawId) else {
                return
            }
            subscriber.putNext(AyuGramProfileRelay.shared.entry(rawId: rawId))
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}

public final class AyuGramFakeNftResolver {
    public static let shared = AyuGramFakeNftResolver()

    private let lock = NSLock()
    private var gifts: [String: StarGift.UniqueGift] = [:]
    private var failures: [String: Double] = [:]

    private init() {
    }

    public func cachedGift(slug: String) -> StarGift.UniqueGift? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.gifts[slug.lowercased()]
    }

    private func store(slug: String, gift: StarGift.UniqueGift) {
        self.lock.lock()
        if self.gifts.count > 400 {
            self.gifts.removeAll()
        }
        self.gifts[slug.lowercased()] = gift
        self.failures.removeValue(forKey: slug.lowercased())
        self.lock.unlock()
    }

    private func markFailed(slug: String) {
        self.lock.lock()
        self.failures[slug.lowercased()] = Date().timeIntervalSince1970
        self.lock.unlock()
    }

    private func recentlyFailed(slug: String) -> Bool {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let failed = self.failures[slug.lowercased()] {
            return Date().timeIntervalSince1970 - failed < 120.0
        }
        return false
    }

    public func fetch(engine: TelegramEngine, slug: String) -> Signal<StarGift.UniqueGift, GetUniqueStarGiftError> {
        return engine.payments.getUniqueStarGift(slug: slug)
        |> beforeNext { [weak self] gift in
            self?.store(slug: slug, gift: gift)
        }
    }

    public func resolve(engine: TelegramEngine, slug: String) -> Signal<StarGift.UniqueGift?, NoError> {
        if let cached = self.cachedGift(slug: slug) {
            return .single(cached)
        }
        return engine.payments.cachedUniqueStarGift(slug: slug)
        |> mapToSignal { [weak self] cached -> Signal<StarGift.UniqueGift?, NoError> in
            guard let self else {
                return .single(cached)
            }
            if let cached {
                self.store(slug: slug, gift: cached)
                return .single(cached)
            }
            if self.recentlyFailed(slug: slug) {
                return .single(nil)
            }
            return self.fetch(engine: engine, slug: slug)
            |> map(Optional.init)
            |> `catch` { [weak self] _ -> Signal<StarGift.UniqueGift?, NoError> in
                self?.markFailed(slug: slug)
                return .single(nil)
            }
        }
    }
}

public func ayuGramFakeNftItems(engine: TelegramEngine, peerId: EnginePeer.Id) -> Signal<[AyuGramFakeNftItem], NoError> {
    guard ayuGramProfileExtrasSupported(peerId) else {
        return .single([])
    }
    return ayuGramProfileEntrySignal(peerId: peerId)
    |> map { entry -> [AyuGramProfileNft] in
        return entry?.orderedNfts ?? []
    }
    |> distinctUntilChanged
    |> mapToSignal { nfts -> Signal<[AyuGramFakeNftItem], NoError> in
        if nfts.isEmpty {
            return .single([])
        }
        let signals = nfts.map { nft -> Signal<AyuGramFakeNftItem, NoError> in
            guard let slug = nft.slug else {
                return .single(AyuGramFakeNftItem(nft: nft, gift: nil))
            }
            if let cached = AyuGramFakeNftResolver.shared.cachedGift(slug: slug) {
                return .single(AyuGramFakeNftItem(nft: nft, gift: cached))
            }
            return .single(AyuGramFakeNftItem(nft: nft, gift: nil))
            |> then(
                AyuGramFakeNftResolver.shared.resolve(engine: engine, slug: slug)
                |> map { gift -> AyuGramFakeNftItem in
                    return AyuGramFakeNftItem(nft: nft, gift: gift)
                }
            )
        }
        return combineLatest(signals)
        |> distinctUntilChanged
    }
}
