import Foundation
import SwiftSignalKit
import TelegramCore
import SGSimpleSettings
import SGStrings

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

public func ayuGramPeerId(rawId: Int64) -> EnginePeer.Id {
    return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(rawId))
}

public func ayuGramProfileHidesRealGifts(entry: AyuGramProfileEntry?, peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Bool {
    guard let entry, entry.hideReal, peerId != accountPeerId else {
        return false
    }
    return true
}

public func ayuGramProfileBubblesVisible(entry: AyuGramProfileEntry?) -> Bool {
    guard let entry, entry.bubbles else {
        return false
    }
    return AyuGramProfileRelay.bubblesEnabled
}

public func ayuGramProfileViewerSettingsSignal() -> Signal<Bool, NoError> {
    return Signal<Bool, NoError> { subscriber in
        subscriber.putNext(AyuGramProfileRelay.bubblesEnabled)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramProfileRelay.viewerDidChange, object: nil, queue: .main, using: { _ in
            subscriber.putNext(AyuGramProfileRelay.bubblesEnabled)
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}

public func ayuGramNftHoldersSignal(slug: String) -> Signal<[AyuGramProfileHolder], NoError> {
    guard AyuGramProfileNft.isValidSlug(slug) else {
        return .single([])
    }
    if let cached = AyuGramProfileRelay.shared.cachedHolders(slug: slug) {
        return .single(cached)
    }
    return Signal<[AyuGramProfileHolder], NoError> { subscriber in
        AyuGramProfileRelay.shared.holders(slug: slug, completion: { result in
            switch result {
            case let .success(holders):
                subscriber.putNext(holders)
            case .failure:
                subscriber.putNext([])
            }
            subscriber.putCompletion()
        })
        return EmptyDisposable
    }
}

public func ayuGramNumberHolderSignal(number: String) -> Signal<EnginePeer.Id?, NoError> {
    guard AyuGramProfileEntry.normalizeNumber(number) != nil else {
        return .single(nil)
    }
    if let cached = AyuGramProfileRelay.shared.cachedNumberHolder(number: number) {
        return .single(cached.map(ayuGramPeerId(rawId:)))
    }
    return Signal<EnginePeer.Id?, NoError> { subscriber in
        AyuGramProfileRelay.shared.numberHolder(number: number, completion: { result in
            switch result {
            case let .success(rawId):
                subscriber.putNext(rawId.map(ayuGramPeerId(rawId:)))
            case .failure:
                subscriber.putNext(nil)
            }
            subscriber.putCompletion()
        })
        return EmptyDisposable
    }
}

public func ayuGramProfileHidesRealGiftsSignal(peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Signal<Bool, NoError> {
    if peerId == accountPeerId {
        return .single(false)
    }
    return ayuGramProfileEntrySignal(peerId: peerId)
    |> map { entry -> Bool in
        return ayuGramProfileHidesRealGifts(entry: entry, peerId: peerId, accountPeerId: accountPeerId)
    }
    |> distinctUntilChanged
}

public func ayuGramGiftHideKey(gift: StarGift, date: Int32) -> String {
    switch gift {
    case let .unique(uniqueGift):
        return "u:" + uniqueGift.slug.lowercased()
    case let .generic(genericGift):
        return "g:\(genericGift.id):\(date)"
    }
}

public func ayuGramProfileHiddenGiftKeysSignal(peerId: EnginePeer.Id, accountPeerId: EnginePeer.Id) -> Signal<Set<String>, NoError> {
    if peerId == accountPeerId {
        return .single(Set())
    }
    return ayuGramProfileEntrySignal(peerId: peerId)
    |> map { entry -> Set<String> in
        return Set(entry?.hiddenGifts ?? [])
    }
    |> distinctUntilChanged
}

public func ayuGramFakeEmojiStatus(gift: StarGift.UniqueGift) -> PeerEmojiStatus? {
    var fileId: Int64?
    var patternFileId: Int64?
    var colors: (inner: Int32, outer: Int32, pattern: Int32, text: Int32)?
    for attribute in gift.attributes {
        switch attribute {
        case let .model(_, file, _, _):
            fileId = file.fileId.id
        case let .pattern(_, file, _):
            patternFileId = file.fileId.id
        case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _):
            colors = (inner: innerColor, outer: outerColor, pattern: patternColor, text: textColor)
        default:
            break
        }
    }
    guard let fileId, let patternFileId, let colors else {
        return nil
    }
    return PeerEmojiStatus(content: .starGift(id: gift.id, fileId: fileId, title: gift.title, slug: gift.slug, patternFileId: patternFileId, innerColor: colors.inner, outerColor: colors.outer, patternColor: colors.pattern, textColor: colors.text), expirationDate: nil)
}

public func ayuGramProfileErrorText(_ error: AyuGramProfileError, locale: String) -> String {
    switch error {
    case .network:
        return i18n("Ayu.ProfileExtras.Error.Network", locale)
    case .unavailable:
        return i18n("Ayu.ProfileExtras.Error.Unavailable", locale)
    case .locked:
        return i18n("Ayu.ProfileExtras.Error.Locked", locale)
    case .unverified:
        return i18n("Ayu.ProfileExtras.Error.Unverified", locale)
    case .banned, .blocked:
        return i18n("Ayu.ProfileExtras.Error.Banned", locale)
    case .rateLimited:
        return i18n("Ayu.ProfileExtras.Error.RateLimited", locale)
    case .tooLarge:
        return i18n("Ayu.ProfileExtras.Error.TooLarge", locale)
    case .tooLong:
        return i18n("Ayu.ProfileExtras.Error.TooLong", locale)
    case .badMedia, .unsupported:
        return i18n("Ayu.ProfileExtras.Error.BadMedia", locale)
    case let .reservedUsername(value):
        return i18n("Ayu.ProfileExtras.Error.Reserved", locale, "@" + value)
    case .badUsername:
        return i18n("Ayu.ProfileExtras.Error.BadUsername", locale)
    case .numberTaken:
        return i18n("Ayu.ProfileExtras.Error.NumberTaken", locale)
    case .badNumber:
        return i18n("Ayu.ProfileExtras.Error.BadNumber", locale)
    case .statusNotOwned:
        return i18n("Ayu.ProfileExtras.Error.StatusNotOwned", locale)
    case .invalid, .server:
        return i18n("Ayu.ProfileExtras.Error.Invalid", locale)
    }
}

public enum AyuGramOwnNftAction: Equatable {
    case togglePinned(key: String)
    case toggleStatus(slug: String)
    case delete(key: String)
    case toggleHiddenGift(key: String)
}

public enum AyuGramOwnEditError: Error, Equatable {
    case profile(AyuGramProfileError)
    case pinLimit
    case notFound

    public func text(locale: String) -> String {
        switch self {
        case let .profile(error):
            return ayuGramProfileErrorText(error, locale: locale)
        case .pinLimit:
            return i18n("Ayu.ProfileExtras.Error.PinLimit", locale)
        case .notFound:
            return i18n("Ayu.ProfileExtras.Error.Invalid", locale)
        }
    }
}

public func ayuGramOwnNftPatch(entry: AyuGramProfileEntry, limits: AyuGramProfileLimits, action: AyuGramOwnNftAction) -> Result<AyuGramProfilePatch, AyuGramOwnEditError> {
    var nfts = entry.nfts
    switch action {
    case let .togglePinned(key):
        guard let index = nfts.firstIndex(where: { $0.key == key }) else {
            return .failure(.notFound)
        }
        if !nfts[index].pinned && nfts.filter({ $0.pinned }).count >= limits.pinned {
            return .failure(.pinLimit)
        }
        nfts[index] = nfts[index].withPinned(!nfts[index].pinned)
        return .success(AyuGramProfilePatch(nfts: nfts))
    case let .toggleStatus(slug):
        guard let nft = nfts.first(where: { $0.slug?.lowercased() == slug.lowercased() }), let nftSlug = nft.slug else {
            return .failure(.notFound)
        }
        if entry.statusSlug?.lowercased() == nftSlug.lowercased() {
            return .success(AyuGramProfilePatch(status: .clear))
        }
        return .success(AyuGramProfilePatch(status: .set(nftSlug)))
    case let .delete(key):
        guard let index = nfts.firstIndex(where: { $0.key == key }) else {
            return .failure(.notFound)
        }
        let removed = nfts.remove(at: index)
        var patch = AyuGramProfilePatch(nfts: nfts)
        if let removedSlug = removed.slug?.lowercased(), entry.statusSlug?.lowercased() == removedSlug {
            patch.status = .clear
        }
        return .success(patch)
    case let .toggleHiddenGift(key):
        var hidden = entry.hiddenGifts
        if let index = hidden.firstIndex(of: key) {
            hidden.remove(at: index)
        } else {
            if hidden.count >= 300 {
                hidden.removeFirst()
            }
            hidden.append(key)
        }
        return .success(AyuGramProfilePatch(hiddenGifts: hidden))
    }
}

public func ayuGramApplyOwnNftAction(accountPeerId: EnginePeer.Id, action: AyuGramOwnNftAction, completion: @escaping (AyuGramOwnEditError?) -> Void) {
    let accountId = ayuGramRawPeerId(accountPeerId)
    AyuGramProfileRelay.shared.loadOwn(accountId: accountId, completion: { result in
        switch result {
        case let .success(own):
            guard own.verified else {
                completion(.profile(.unverified))
                return
            }
            switch ayuGramOwnNftPatch(entry: own.entry, limits: own.limits, action: action) {
            case let .success(patch):
                AyuGramProfileRelay.shared.updateOwn(accountId: accountId, patch: patch, completion: { result in
                    switch result {
                    case .success:
                        completion(nil)
                    case let .failure(error):
                        completion(.profile(error))
                    }
                })
            case let .failure(error):
                completion(error)
            }
        case let .failure(error):
            completion(.profile(error))
        }
    })
}

public func ayuGramRandomAnonymousNumber() -> String {
    var digits = "888"
    for _ in 0 ..< 8 {
        digits.append(String(Int.random(in: 0 ... 9)))
    }
    return "+" + digits
}

public func ayuGramFakeNumberHolderPeer(engine: TelegramEngine, query: String) -> Signal<EnginePeer?, NoError> {
    guard let number = AyuGramProfileEntry.normalizeNumber(query) else {
        return .single(nil)
    }
    return ayuGramNumberHolderSignal(number: number)
    |> timeout(4.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    |> mapToSignal { peerId -> Signal<EnginePeer?, NoError> in
        guard let peerId else {
            return .single(nil)
        }
        let _ = AyuGramProfileRelay.shared.observe(rawId: ayuGramRawPeerId(peerId))
        return engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> map { peer -> EnginePeer? in
            guard let peer, case let .user(user) = peer else {
                return nil
            }
            if let phone = user.phone, AyuGramProfileEntry.normalizeNumber(phone) == number {
                return nil
            }
            return peer
        }
    }
}

public func ayuGramFakeNumberHolderText(peer: EnginePeer, query: String?, locale: String) -> String? {
    guard let query, let number = AyuGramProfileEntry.normalizeNumber(query), case let .user(user) = peer, ayuGramProfileExtrasSupported(peer.id) else {
        return nil
    }
    if let phone = user.phone, AyuGramProfileEntry.normalizeNumber(phone) == number {
        return nil
    }
    let rawId = ayuGramRawPeerId(peer.id)
    let holds = AyuGramProfileRelay.shared.entry(rawId: rawId)?.number == number || AyuGramProfileRelay.shared.cachedNumberHolder(number: number) == .some(rawId)
    guard holds else {
        return nil
    }
    return "⚠️ " + i18n("Ayu.FakeNumber.Plaque", locale) + " · " + AyuGramProfileEntry.formatNumber(number)
}
