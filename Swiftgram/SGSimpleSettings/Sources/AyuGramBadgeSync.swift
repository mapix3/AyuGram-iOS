import Foundation

public struct AyuGramBadgePayment: Equatable {
    public var cryptoBot: String
    public var xRocket: String
    public var tonAddress: String
    public var tonAmount: String
    public var tonComment: String
    public var tonURL: String
    public var tonOpen: String

    public var hasTon: Bool {
        return !self.tonAddress.isEmpty && !self.tonAmount.isEmpty && !self.tonURL.isEmpty
    }
}

public final class AyuGramBadgeSync {
    public static let shared = AyuGramBadgeSync()

    private let lock = NSLock()
    private var lastRefresh: Double = 0.0
    private var refreshing = false
    private let secretKey = "ayugram.badges.secret"
    public private(set) var payURL = "https://t.me/send?start=IVM3XypxxOuG"
    public private(set) var price = "3"
    public private(set) var payment: AyuGramBadgePayment?

    public func start() {
        AyuGramClientBadges.shared.refreshHandler = { [weak self] force in
            self?.refresh(force: force)
        }
        self.refresh(force: false)
    }

    public func refresh(force: Bool = false) {
        lock.lock()
        let now = Date().timeIntervalSince1970
        if refreshing || (!force && now - lastRefresh < 300.0) {
            lock.unlock()
            return
        }
        refreshing = true
        lastRefresh = now
        lock.unlock()
        guard let url = URL(string: AyuGramSecurity.relayURL + "/badges") else {
            return
        }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request, completionHandler: { data, response, _ in
            session.finishTasksAndInvalidate()
            self.lock.lock()
            self.refreshing = false
            self.lock.unlock()
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let items = object["items"] as? [[String: Any]] else {
                return
            }
            if let pay = object["pay"] as? String, pay.hasPrefix("https://") {
                self.payURL = pay
            }
            if let price = object["price"] as? String, !price.isEmpty {
                self.price = String(price.prefix(8))
            }
            var updated: [Int64: AyuGramCustomBadge] = [:]
            for item in items.prefix(5000) {
                guard let idText = item["id"] as? String, let id = Int64(idText), AyuGramClientBadges.valid(id), let raw = item["b"], let rawData = try? JSONSerialization.data(withJSONObject: raw), var badge = try? JSONDecoder().decode(AyuGramCustomBadge.self, from: rawData) else {
                    continue
                }
                badge.enabled = true
                updated[id] = badge
            }
            AyuGramClientBadges.shared.replaceSupporters(updated)
        }).resume()
    }

    private var secret: String {
        if let value = UserDefaults.standard.string(forKey: self.secretKey), value.count >= 24 {
            return value
        }
        let value = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(value, forKey: self.secretKey)
        return value
    }

    private func post(_ path: String, _ body: [String: Any], completion: @escaping (Int, [String: Any]) -> Void) {
        guard let url = URL(string: AyuGramSecurity.relayURL + path), let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(0, [:])
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request, completionHandler: { data, response, _ in
            session.finishTasksAndInvalidate()
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
            DispatchQueue.main.async {
                completion(status, object)
            }
        }).resume()
    }

    private func decode(_ raw: Any?) -> AyuGramCustomBadge {
        if let raw, let data = try? JSONSerialization.data(withJSONObject: raw), var badge = try? JSONDecoder().decode(AyuGramCustomBadge.self, from: data) {
            badge.enabled = true
            return badge
        }
        var badge = AyuGramCustomBadge()
        badge.enabled = true
        return badge
    }

    private func link(_ value: Any?, schemes: [String]) -> String {
        guard let text = value as? String, text.count <= 512, schemes.contains(where: { text.hasPrefix($0) }), URL(string: text) != nil else {
            return ""
        }
        return text
    }

    private func readPayment(_ object: [String: Any], code: String) -> AyuGramBadgePayment? {
        guard let pay = object["pay"] as? [String: Any] else {
            return nil
        }
        var payment = AyuGramBadgePayment(cryptoBot: self.link(pay["cryptobot"], schemes: ["https://t.me/"]), xRocket: self.link(pay["xrocket"], schemes: ["https://t.me/"]), tonAddress: "", tonAmount: "", tonComment: code, tonURL: "", tonOpen: "")
        if let ton = pay["ton"] as? [String: Any], let address = ton["address"] as? String, address.count == 48, let amount = ton["amount"] as? String, amount.count <= 16, amount.allSatisfy({ $0.isNumber || $0 == "." }) {
            payment.tonAddress = address
            payment.tonAmount = amount
            payment.tonURL = self.link(ton["url"], schemes: ["ton://transfer/"])
            payment.tonOpen = self.link(ton["open"], schemes: ["https://app.tonkeeper.com/transfer/"])
            if payment.tonOpen.isEmpty {
                payment.tonOpen = payment.tonURL
            }
        }
        return payment
    }

    private func readState(_ status: Int, _ object: [String: Any]) -> AyuGramSupporterState {
        guard status == 200 else {
            return .failed
        }
        if (object["granted"] as? Bool) == true {
            self.payment = nil
            return .granted(self.decode(object["badge"]))
        }
        if let code = object["code"] as? String, !code.isEmpty {
            if let payment = self.readPayment(object, code: code) {
                self.payment = payment
            }
            return .pending(code)
        }
        self.payment = nil
        return .none
    }

    public func supporterStatus(accountId: Int64, completion: @escaping (AyuGramSupporterState) -> Void) {
        self.post("/badges/status", ["id": String(accountId), "secret": self.secret], completion: { status, object in
            completion(self.readState(status, object))
        })
    }

    public func requestSupporter(accountId: Int64, name: String, completion: @escaping (AyuGramSupporterState) -> Void) {
        self.post("/badges/request", ["id": String(accountId), "secret": self.secret, "name": name], completion: { status, object in
            if (object["granted"] as? Bool) == true && object["badge"] == nil {
                self.supporterStatus(accountId: accountId, completion: completion)
                return
            }
            let state = self.readState(status, object)
            if case .none = state {
                completion(.failed)
            } else {
                completion(state)
            }
        })
    }

    public func setSupporterBadge(accountId: Int64, badge: AyuGramCustomBadge, completion: @escaping (Bool) -> Void) {
        var shown = badge
        shown.enabled = true
        AyuGramClientBadges.shared.setSupporter(accountId, badge: shown)
        let payload: [String: Any] = ["symbol": badge.symbol, "emoji": badge.emoji, "shape": Int(badge.shape), "top": badge.top, "bottom": badge.bottom, "darkGlyph": badge.darkGlyph]
        self.post("/badges/set", ["id": String(accountId), "secret": self.secret, "badge": payload], completion: { status, _ in
            completion(status == 200)
        })
    }
}
