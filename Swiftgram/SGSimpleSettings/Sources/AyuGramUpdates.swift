import Foundation

public struct AyuGramUpdateInfo: Equatable {
    public let build: Int
    public let version: String
    public let url: String
}

/// Checks the published update manifest. Only the manifest is downloaded; nothing
/// about the user or the device is sent.
public final class AyuGramUpdates {
    public static let shared = AyuGramUpdates()
    public static let didChange = Notification.Name("AyuGram.Updates.didChange")
    public static let manifestURL = URL(string: "https://raw.githubusercontent.com/mapix3/AyuGram-iOS/standard/update.json")!
    public static let channelURL = "https://t.me/ayugramiosupdates"
    public static let developerId: Int64 = 1272887902

    private let lock = NSLock()
    private var available: AyuGramUpdateInfo?
    private let ignoredKey = "ayugram.updates.ignoredBuild"

    public init() {}

    public var availableUpdate: AyuGramUpdateInfo? {
        lock.lock(); defer { lock.unlock() }
        return available
    }

    public var currentBuild: Int {
        return Int((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "") ?? 0
    }

    public func isIgnored(_ info: AyuGramUpdateInfo) -> Bool {
        return UserDefaults.standard.integer(forKey: ignoredKey) >= info.build
    }

    public func ignore(_ info: AyuGramUpdateInfo) {
        UserDefaults.standard.set(info.build, forKey: ignoredKey)
    }

    /// Parses the manifest; only https links are accepted.
    public static func parse(_ data: Data, currentBuild: Int) -> AyuGramUpdateInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let build = (object["build"] as? Int) ?? (object["build"] as? String).flatMap(Int.init),
              build > currentBuild,
              let url = object["url"] as? String, url.hasPrefix("https://") else { return nil }
        let version = (object["version"] as? String) ?? String(build)
        return AyuGramUpdateInfo(build: build, version: version, url: url)
    }

    public func check(completion: @escaping (AyuGramUpdateInfo?) -> Void) {
        var request = URLRequest(url: Self.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        let session = URLSession(configuration: .ephemeral)
        let current = currentBuild
        session.dataTask(with: request) { [weak self] data, response, _ in
            var info: AyuGramUpdateInfo?
            if let data, data.count <= 16384, (response as? HTTPURLResponse)?.statusCode == 200 {
                info = Self.parse(data, currentBuild: current)
            }
            session.finishTasksAndInvalidate()
            DispatchQueue.main.async {
                guard let self else { return }
                self.lock.lock()
                let changed = self.available != info
                self.available = info
                self.lock.unlock()
                if changed {
                    NotificationCenter.default.post(name: Self.didChange, object: self)
                }
                completion(info)
            }
        }.resume()
    }
}
