import Foundation
import CryptoKit
import MachO
import Security

public enum AyuGramInstallSource: String {
    case sideload, enterprise, testflight, appstore, unknown
}

public enum AyuGramBuildStatus: String {
    case checking, official, modified, unknown
}

public struct AyuGramSigningInfo: Equatable {
    public var teamId: String
    public var teamName: String
    public var certificate: String
    public var profileName: String
    public var source: AyuGramInstallSource
    public var devices: Int

    public init(teamId: String, teamName: String, certificate: String, profileName: String, source: AyuGramInstallSource, devices: Int) {
        self.teamId = teamId
        self.teamName = teamName
        self.certificate = certificate
        self.profileName = profileName
        self.source = source
        self.devices = devices
    }

    /// A free Apple ID signs for a handful of own devices; anything else is a distributor.
    public func identifiesDistributor(status: AyuGramBuildStatus) -> Bool {
        return status == .modified || self.source != .sideload || self.devices > 3
    }
}

public struct AyuGramBlockRules: Equatable {
    public var teams: Set<String> = []
    public var builds: Set<Int> = []
    public var modified = false
    public var message: String?

    public init() {}

    public static func parse(_ data: Data) -> AyuGramBlockRules {
        var rules = AyuGramBlockRules()
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let block = object["block"] as? [String: Any] else {
            return rules
        }
        if let teams = block["teams"] as? [String] {
            rules.teams = Set(teams.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty })
        }
        if let builds = block["builds"] as? [Any] {
            rules.builds = Set(builds.compactMap { item -> Int? in
                if let number = item as? Int {
                    return number
                }
                if let text = item as? String {
                    return Int(text)
                }
                return nil
            })
        }
        rules.modified = (block["modified"] as? Bool) ?? false
        if let message = block["message"] as? String, !message.isEmpty {
            rules.message = String(message.prefix(1000))
        }
        return rules
    }

    public func matches(teamId: String, build: Int, status: AyuGramBuildStatus) -> Bool {
        if !teamId.isEmpty && self.teams.contains(teamId.uppercased()) {
            return true
        }
        if self.builds.contains(build) {
            return true
        }
        return self.modified && status == .modified
    }
}

public struct AyuGramReportTicket {
    public let rid: String
    public let token: String
}

public final class AyuGramSecurity {
    public static let shared = AyuGramSecurity()
    public static let didChange = Notification.Name("AyuGram.Security.didChange")
    public static let relayURL = "https://ayugram-push.ayugram-status.workers.dev"
    public static let releaseURL = "https://github.com/mapix3/AyuGram-iOS/releases/download/build-"

    public let signing: AyuGramSigningInfo

    private let lock = NSLock()
    private var currentStatus: AyuGramBuildStatus = .checking
    private var rules = AyuGramBlockRules()
    private var started = false
    private let statsMarkerKey = "ayugram.stats.last"
    private let installIdKey = "ayugram.stats.id"
    private let accountsKey = "ayugram.stats.accounts"
    private let banKey = "ayugram.moderation.banned"
    private let warningSeenKey = "ayugram.moderation.warning"
    private var lastModerationCheck: Date?
    private var currentWarning: String?

    private init() {
        self.signing = AyuGramSecurity.readSigning()
    }

    public var build: Int {
        return Int((Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "") ?? 0
    }

    public var status: AyuGramBuildStatus {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.currentStatus
    }

    public var isBlocked: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.rules.matches(teamId: self.signing.teamId, build: self.build, status: self.currentStatus) || UserDefaults.standard.bool(forKey: self.banKey)
    }

    public var isBanned: Bool {
        return UserDefaults.standard.bool(forKey: self.banKey)
    }

    public var pendingWarning: String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.currentWarning
    }

    public static func accountHash(_ id: Int64) -> String {
        let digest = SHA256.hash(data: Data("ayugram-account|\(id)".utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    public var accountHashes: [String] {
        return UserDefaults.standard.stringArray(forKey: self.accountsKey) ?? []
    }

    public func noteAccount(_ id: Int64) {
        guard id != 0 else {
            return
        }
        let hash = AyuGramSecurity.accountHash(id)
        var hashes = self.accountHashes
        if hashes.contains(hash) {
            return
        }
        hashes.append(hash)
        UserDefaults.standard.set(Array(hashes.suffix(8)), forKey: self.accountsKey)
    }

    public func acknowledgeWarning() {
        self.lock.lock()
        let warning = self.currentWarning
        self.currentWarning = nil
        self.lock.unlock()
        if let warning {
            UserDefaults.standard.set(warning, forKey: self.warningSeenKey)
        }
    }

    public func refreshModeration() {
        self.lock.lock()
        if let last = self.lastModerationCheck, Date().timeIntervalSince(last) < 600.0 {
            self.lock.unlock()
            return
        }
        self.lastModerationCheck = Date()
        self.lock.unlock()
        let hashes = self.accountHashes
        guard !hashes.isEmpty, let url = URL(string: AyuGramSecurity.relayURL + "/stats/status"), let body = try? JSONSerialization.data(withJSONObject: ["id": self.installId, "accounts": hashes] as [String: Any]) else {
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request, completionHandler: { data, response, error in
            session.finishTasksAndInvalidate()
            guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }
            let banned = (object["banned"] as? Bool) ?? false
            var changed = UserDefaults.standard.bool(forKey: self.banKey) != banned
            UserDefaults.standard.set(banned, forKey: self.banKey)
            if let warning = object["warning"] as? String, !warning.isEmpty, warning != UserDefaults.standard.string(forKey: self.warningSeenKey) {
                self.lock.lock()
                if self.currentWarning != warning {
                    self.currentWarning = warning
                    changed = true
                }
                self.lock.unlock()
            }
            if changed {
                self.notify()
            }
        }).resume()
    }

    public var blockMessage: String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.rules.message
    }

    public var installId: String {
        if let value = UserDefaults.standard.string(forKey: self.installIdKey), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: self.installIdKey)
        return value
    }

    public func applyManifest(_ data: Data) {
        let parsed = AyuGramBlockRules.parse(data)
        self.lock.lock()
        let changed = parsed != self.rules
        self.rules = parsed
        self.lock.unlock()
        if changed {
            self.notify()
        }
    }

    public func start(variant: String, statsEnabled: @escaping () -> Bool) {
        self.lock.lock()
        if self.started {
            self.lock.unlock()
            return
        }
        self.started = true
        self.lock.unlock()
        let variants = variant == "custom" ? ["custom", "standard"] : ["standard", "custom"]
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3.0, execute: {
            let local = AyuGramSecurity.localFingerprint()
            self.verify(local: local, variants: variants, completion: { status in
                self.setStatus(status)
                if statsEnabled() {
                    self.sendStats(variant: variant)
                }
            })
        })
    }

    public func sendStats(variant: String) {
        let day = Int(Date().timeIntervalSince1970 / 86400.0)
        let marker = "\(self.build)|\(day)|\(self.status.rawValue)|\(self.accountHashes.joined(separator: ","))"
        if UserDefaults.standard.string(forKey: self.statsMarkerKey) == marker {
            return
        }
        self.post(path: "/stats/ping", body: self.payload(variant: variant), completion: { ok in
            if ok {
                UserDefaults.standard.set(marker, forKey: self.statsMarkerKey)
            }
        })
    }

    public func report(text: String, target: Int64, targetName: String, attachments: Int, variant: String, completion: @escaping (Bool, AyuGramReportTicket?) -> Void) {
        var body = self.payload(variant: variant)
        body["text"] = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        if target != 0 {
            body["target"] = String(target)
        }
        if !targetName.isEmpty {
            body["targetName"] = String(targetName.prefix(160))
        }
        body["attachments"] = attachments
        guard let url = URL(string: AyuGramSecurity.relayURL + "/stats/report"), let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false, nil)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request, completionHandler: { data, response, error in
            session.finishTasksAndInvalidate()
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            var ticket: AyuGramReportTicket?
            if ok, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rid = object["rid"] as? String, let token = object["token"] as? String {
                ticket = AyuGramReportTicket(rid: rid, token: token)
            }
            DispatchQueue.main.async {
                completion(ok, ticket)
            }
        }).resume()
    }

    public func attach(ticket: AyuGramReportTicket, data: Data, contentType: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: AyuGramSecurity.relayURL + "/stats/attach/" + ticket.rid) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120.0)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(ticket.token, forHTTPHeaderField: "X-AyuGram-Token")
        let session = URLSession(configuration: .ephemeral)
        session.uploadTask(with: request, from: data, completionHandler: { _, response, error in
            session.finishTasksAndInvalidate()
            let ok = error == nil && (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                completion(ok)
            }
        }).resume()
    }

    private func setStatus(_ status: AyuGramBuildStatus) {
        self.lock.lock()
        let changed = self.currentStatus != status
        self.currentStatus = status
        self.lock.unlock()
        if changed {
            self.notify()
        }
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AyuGramSecurity.didChange, object: nil)
        }
    }

    private func payload(variant: String) -> [String: Any] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let reveal = self.signing.identifiesDistributor(status: self.status)
        return [
            "id": self.installId,
            "build": self.build,
            "variant": variant,
            "source": self.signing.source.rawValue,
            "status": self.status.rawValue,
            "team": reveal ? self.signing.teamId : "",
            "teamName": reveal ? self.signing.teamName : "",
            "cert": reveal ? self.signing.certificate : "",
            "profile": reveal ? self.signing.profileName : "",
            "bundle": reveal ? (Bundle.main.bundleIdentifier ?? "") : "",
            "devices": self.signing.devices,
            "accounts": self.accountHashes,
            "os": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "device": AyuGramSecurity.deviceModel
        ]
    }

    private func post(path: String, body: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: AyuGramSecurity.relayURL + path), let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: request, completionHandler: { _, response, error in
            session.finishTasksAndInvalidate()
            completion(error == nil && (response as? HTTPURLResponse)?.statusCode == 200)
        }).resume()
    }

    private func verify(local: [String: String], variants: [String], completion: @escaping (AyuGramBuildStatus) -> Void) {
        guard let variant = variants.first else {
            completion(.modified)
            return
        }
        let build = self.build
        guard build > 0, let url = URL(string: "\(AyuGramSecurity.releaseURL)\(build)/AyuGram-\(variant)-\(build).integrity.json") else {
            completion(.modified)
            return
        }
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0), completionHandler: { data, response, error in
            session.finishTasksAndInvalidate()
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil || (code != 200 && code != 404) {
                completion(.unknown)
                return
            }
            if code == 200, let data, data.count < 262144, let remote = AyuGramSecurity.parseFingerprint(data, build: build), AyuGramSecurity.compare(local: local, remote: remote) == .official {
                completion(.official)
                return
            }
            self.verify(local: local, variants: Array(variants.dropFirst()), completion: completion)
        }).resume()
    }

    public static func parseFingerprint(_ data: Data, build: Int) -> [String: String]? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let images = object["images"] as? [String: String] else {
            return nil
        }
        guard ((object["build"] as? Int) ?? 0) == build else {
            return nil
        }
        return images
    }

    public static func compare(local: [String: String], remote: [String: String]) -> AyuGramBuildStatus {
        if local.isEmpty || remote.isEmpty {
            return .modified
        }
        for (image, hash) in local {
            guard let expected = remote[image], expected == hash else {
                return .modified
            }
        }
        return .official
    }

    public static func isFingerprintedImage(_ relative: String, executable: String) -> Bool {
        if relative == executable {
            return true
        }
        if relative.hasPrefix("PlugIns/") || relative.hasPrefix("Extensions/") {
            return false
        }
        if relative.hasSuffix(".dylib") {
            return true
        }
        let parts = relative.split(separator: "/").map(String.init)
        if parts.count == 3 && parts[0] == "Frameworks" && parts[1].hasSuffix(".framework") {
            return parts[2] + ".framework" == parts[1]
        }
        return false
    }

    public static func localFingerprint() -> [String: String] {
        var result: [String: String] = [:]
        let bundleName = (Bundle.main.bundlePath as NSString).lastPathComponent
        let marker = "/" + bundleName + "/"
        let executable = (Bundle.main.infoDictionary?["CFBundleExecutable"] as? String) ?? ""
        for index in 0 ..< _dyld_image_count() {
            guard let name = _dyld_get_image_name(index), let header = _dyld_get_image_header(index) else {
                continue
            }
            let path = String(cString: name)
            guard let range = path.range(of: marker) else {
                continue
            }
            let relative = String(path[range.upperBound...])
            guard AyuGramSecurity.isFingerprintedImage(relative, executable: executable) else {
                continue
            }
            var size: UInt = 0
            let section = header.withMemoryRebound(to: mach_header_64.self, capacity: 1, { pointer in
                return getsectiondata(pointer, "__TEXT", "__text", &size)
            })
            guard let section, size > 0 else {
                continue
            }
            let digest = SHA256.hash(data: UnsafeRawBufferPointer(start: UnsafeRawPointer(section), count: Int(size)))
            result[relative] = digest.map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine, { buffer in
            return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        })
    }

    static func provisioningPlist(_ data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound ..< data.endIndex) else {
            return nil
        }
        let slice = data.subdata(in: start.lowerBound ..< end.upperBound)
        return (try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil)) as? [String: Any]
    }

    static func keychainTeamId() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "ayugram.team.probe",
            kSecAttrService as String: "ayugram.team.probe",
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = query
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess, let attributes = result as? [String: Any], let group = attributes[kSecAttrAccessGroup as String] as? String, let prefix = group.split(separator: ".").first else {
            return nil
        }
        let value = String(prefix)
        return value.count == 10 ? value : nil
    }

    static func readSigning() -> AyuGramSigningInfo {
        var info = AyuGramSigningInfo(teamId: AyuGramSecurity.keychainTeamId() ?? "", teamName: "", certificate: "", profileName: "", source: .unknown, devices: 0)
        if let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"), let data = FileManager.default.contents(atPath: path), let plist = AyuGramSecurity.provisioningPlist(data) {
            if info.teamId.isEmpty, let teams = plist["TeamIdentifier"] as? [String], let first = teams.first {
                info.teamId = first
            }
            info.teamName = (plist["TeamName"] as? String) ?? ""
            info.profileName = (plist["Name"] as? String) ?? ""
            if let certificates = plist["DeveloperCertificates"] as? [Data], let first = certificates.first, let certificate = SecCertificateCreateWithData(nil, first as CFData) {
                info.certificate = (SecCertificateCopySubjectSummary(certificate) as String?) ?? ""
            }
            info.devices = (plist["ProvisionedDevices"] as? [String])?.count ?? 0
            info.source = (plist["ProvisionsAllDevices"] as? Bool) == true ? .enterprise : .sideload
        } else if let receipt = Bundle.main.value(forKey: "appStoreReceiptURL") as? URL {
            if receipt.lastPathComponent == "sandboxReceipt" {
                info.source = .testflight
            } else if FileManager.default.fileExists(atPath: receipt.path) {
                info.source = .appstore
            }
        }
        return info
    }
}
