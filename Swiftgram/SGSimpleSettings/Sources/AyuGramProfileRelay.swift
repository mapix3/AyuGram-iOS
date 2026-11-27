import Foundation
import AVFoundation
import CoreGraphics

public struct AyuGramProfileNftColors: Codable, Equatable {
    public var center: String
    public var edge: String
    public var pattern: String?
    public var text: String?

    public init(center: String, edge: String, pattern: String?, text: String?) {
        self.center = center
        self.edge = edge
        self.pattern = pattern
        self.text = text
    }

    static func from(json: Any?) -> AyuGramProfileNftColors? {
        guard let json = json as? [String: Any], let center = json["center"] as? String, let edge = json["edge"] as? String, AyuGramProfileNftColors.isHex(center), AyuGramProfileNftColors.isHex(edge) else {
            return nil
        }
        let pattern = (json["pattern"] as? String).flatMap { AyuGramProfileNftColors.isHex($0) ? $0 : nil }
        let text = (json["text"] as? String).flatMap { AyuGramProfileNftColors.isHex($0) ? $0 : nil }
        return AyuGramProfileNftColors(center: center, edge: edge, pattern: pattern, text: text)
    }

    static func isHex(_ value: String) -> Bool {
        return value.count == 6 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    public static func rgb(_ value: String?) -> UInt32? {
        guard let value, AyuGramProfileNftColors.isHex(value) else {
            return nil
        }
        return UInt32(value, radix: 16)
    }

    var jsonObject: [String: Any] {
        var result: [String: Any] = ["center": self.center, "edge": self.edge]
        if let pattern = self.pattern {
            result["pattern"] = pattern
        }
        if let text = self.text {
            result["text"] = text
        }
        return result
    }
}

public struct AyuGramProfileNft: Codable, Equatable {
    public var slug: String?
    public var collection: String?
    public var model: String?
    public var backdrop: String?
    public var pattern: String?
    public var number: Int32?
    public var colors: AyuGramProfileNftColors?
    public var pinned: Bool

    public init(slug: String, pinned: Bool) {
        self.slug = slug
        self.collection = nil
        self.model = nil
        self.backdrop = nil
        self.pattern = nil
        self.number = nil
        self.colors = nil
        self.pinned = pinned
    }

    public init(collection: String, model: String?, backdrop: String?, pattern: String?, number: Int32, colors: AyuGramProfileNftColors?, pinned: Bool) {
        self.slug = nil
        self.collection = collection
        self.model = model
        self.backdrop = backdrop
        self.pattern = pattern
        self.number = number
        self.colors = colors
        self.pinned = pinned
    }

    public var key: String {
        if let slug = self.slug {
            return "slug:" + slug.lowercased()
        }
        return "custom:" + (self.collection ?? "").lowercased() + "#" + String(self.number ?? 0)
    }

    public var title: String {
        if let slug = self.slug {
            return slug
        }
        return (self.collection ?? "") + " #" + String(self.number ?? 0)
    }

    public func withPinned(_ pinned: Bool) -> AyuGramProfileNft {
        var result = self
        result.pinned = pinned
        return result
    }

    public static func parseSlug(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "nft/", options: .caseInsensitive) {
            text = String(text[range.upperBound...])
        } else if let range = text.range(of: "slug=", options: .caseInsensitive) {
            text = String(text[range.upperBound...])
        }
        if let index = text.firstIndex(where: { $0 == "?" || $0 == "#" || $0 == "/" || $0 == "&" || $0 == " " }) {
            text = String(text[..<index])
        }
        return AyuGramProfileNft.isValidSlug(text) ? text : nil
    }

    public static func isValidSlug(_ text: String) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return false
        }
        let name = Array(parts[0].unicodeScalars)
        let number = Array(parts[1].unicodeScalars)
        guard name.count >= 2, name.count <= 48, number.count >= 1, number.count <= 7 else {
            return false
        }
        func isLetter(_ scalar: Unicode.Scalar) -> Bool {
            return (scalar >= "a" && scalar <= "z") || (scalar >= "A" && scalar <= "Z")
        }
        func isDigit(_ scalar: Unicode.Scalar) -> Bool {
            return scalar >= "0" && scalar <= "9"
        }
        guard isLetter(name[0]), name.allSatisfy({ isLetter($0) || isDigit($0) }) else {
            return false
        }
        guard number[0] != "0", number.allSatisfy({ isDigit($0) }) else {
            return false
        }
        return true
    }

    static func cleanLabel(_ value: Any?) -> String? {
        guard let value = value as? String else {
            return nil
        }
        let forbidden = CharacterSet(charactersIn: "<>&\"'`").union(.controlCharacters)
        let cleaned = String(String.UnicodeScalarView(value.unicodeScalars.filter { !forbidden.contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return nil
        }
        return String(cleaned.prefix(48))
    }

    static func from(json: [String: Any]) -> AyuGramProfileNft? {
        let pinned = (json["pinned"] as? Bool) ?? false
        if let slug = json["slug"] as? String {
            guard AyuGramProfileNft.isValidSlug(slug) else {
                return nil
            }
            return AyuGramProfileNft(slug: slug, pinned: pinned)
        }
        guard let collection = AyuGramProfileNft.cleanLabel(json["collection"]), let numberValue = (json["number"] as? NSNumber)?.int64Value, numberValue >= 1, numberValue <= 9999999 else {
            return nil
        }
        return AyuGramProfileNft(collection: collection, model: AyuGramProfileNft.cleanLabel(json["model"]), backdrop: AyuGramProfileNft.cleanLabel(json["backdrop"]), pattern: AyuGramProfileNft.cleanLabel(json["pattern"]), number: Int32(numberValue), colors: AyuGramProfileNftColors.from(json: json["colors"]), pinned: pinned)
    }

    var jsonObject: [String: Any] {
        var result: [String: Any] = ["pinned": self.pinned]
        if let slug = self.slug {
            result["slug"] = slug
            return result
        }
        result["collection"] = self.collection ?? ""
        result["number"] = Int(self.number ?? 1)
        if let model = self.model {
            result["model"] = model
        }
        if let backdrop = self.backdrop {
            result["backdrop"] = backdrop
        }
        if let pattern = self.pattern {
            result["pattern"] = pattern
        }
        if let colors = self.colors {
            result["colors"] = colors.jsonObject
        }
        return result
    }
}

public struct AyuGramProfileBackground: Codable, Equatable {
    public var isVideo: Bool
    public var url: String
    public var width: Int
    public var height: Int
    public var mime: String
    public var size: Int
    public var duration: Double?
    public var updatedAt: Double

    public var localFileName: String? {
        return AyuGramProfileRelay.mediaFileName(url: self.url)
    }

    static func from(json: Any?) -> AyuGramProfileBackground? {
        guard let json = json as? [String: Any], let type = json["type"] as? String, type == "photo" || type == "video", let url = json["url"] as? String, let canonicalURL = AyuGramProfileRelay.canonicalMediaURL(url) else {
            return nil
        }
        let width = (json["width"] as? NSNumber)?.intValue ?? 0
        let height = (json["height"] as? NSNumber)?.intValue ?? 0
        let size = (json["size"] as? NSNumber)?.intValue ?? 0
        let duration = (json["duration"] as? NSNumber)?.doubleValue
        let updatedAt = (json["updatedAt"] as? NSNumber)?.doubleValue ?? 0.0
        let mime = (json["mime"] as? String) ?? (type == "video" ? "video/mp4" : "image/jpeg")
        return AyuGramProfileBackground(isVideo: type == "video", url: canonicalURL, width: width, height: height, mime: String(mime.prefix(40)), size: size, duration: duration, updatedAt: updatedAt)
    }
}

public enum AyuGramProfileListMode: String, Codable, Equatable {
    case none
    case extend
    case media
}

public struct AyuGramProfileStyle: Codable, Equatable {
    public var accent: UInt32?
    public var plate: UInt32?
    public var opacity: Double
    public var list: AyuGramProfileListMode
    public var avatar: Double
    public var title: Double
    public var blur: Double

    public static let standard = AyuGramProfileStyle(accent: nil, plate: nil, opacity: 0.55, list: .none, avatar: 1.0, title: 1.0, blur: 0.0)

    public init(accent: UInt32?, plate: UInt32?, opacity: Double, list: AyuGramProfileListMode, avatar: Double, title: Double, blur: Double) {
        self.accent = accent.map { $0 & 0xffffff }
        self.plate = plate.map { $0 & 0xffffff }
        self.opacity = AyuGramProfileStyle.clamp(opacity, 0.0, 1.0, 0.55)
        self.list = list
        self.avatar = AyuGramProfileStyle.clamp(avatar, 0.4, 1.6, 1.0)
        self.title = AyuGramProfileStyle.clamp(title, 0.5, 1.5, 1.0)
        self.blur = AyuGramProfileStyle.clamp(blur, 0.0, 1.0, 0.0)
    }

    public var isStandard: Bool {
        return self == AyuGramProfileStyle.standard
    }

    static func clamp(_ value: Double, _ minValue: Double, _ maxValue: Double, _ fallback: Double) -> Double {
        guard value.isFinite else {
            return fallback
        }
        return (max(minValue, min(maxValue, value)) * 100.0).rounded() / 100.0
    }

    static func color(_ value: Any?) -> UInt32? {
        guard let string = value as? String, string.count == 6, let number = UInt32(string, radix: 16) else {
            return nil
        }
        return number
    }

    static func hex(_ value: UInt32) -> String {
        return String(format: "%06x", value & 0xffffff)
    }

    static func from(json: Any?) -> AyuGramProfileStyle? {
        guard let json = json as? [String: Any] else {
            return nil
        }
        let list = (json["list"] as? String).flatMap(AyuGramProfileListMode.init(rawValue:)) ?? .none
        let style = AyuGramProfileStyle(
            accent: AyuGramProfileStyle.color(json["accent"]),
            plate: AyuGramProfileStyle.color(json["plate"]),
            opacity: (json["opacity"] as? NSNumber)?.doubleValue ?? 0.55,
            list: list,
            avatar: (json["avatar"] as? NSNumber)?.doubleValue ?? 1.0,
            title: (json["title"] as? NSNumber)?.doubleValue ?? 1.0,
            blur: (json["blur"] as? NSNumber)?.doubleValue ?? 0.0
        )
        return style.isStandard ? nil : style
    }

    var jsonObject: [String: Any] {
        return [
            "accent": self.accent.map { AyuGramProfileStyle.hex($0) as Any } ?? NSNull(),
            "plate": self.plate.map { AyuGramProfileStyle.hex($0) as Any } ?? NSNull(),
            "opacity": self.opacity,
            "list": self.list.rawValue,
            "avatar": self.avatar,
            "title": self.title,
            "blur": self.blur
        ]
    }
}

public struct AyuGramProfileHolder: Equatable {
    public var id: Int64
    public var pinned: Bool

    public init(id: Int64, pinned: Bool) {
        self.id = id
        self.pinned = pinned
    }
}

public struct AyuGramProfileEntry: Codable, Equatable {
    public var id: Int64
    public var nfts: [AyuGramProfileNft]
    public var usernames: [String]
    public var background: AyuGramProfileBackground?
    public var bubbles: Bool
    public var hideReal: Bool
    public var hiddenGifts: [String]
    public var statusSlug: String?
    public var number: String?
    public var brightness: Double
    public var style: AyuGramProfileStyle?
    public var listBackground: AyuGramProfileBackground?
    public var updatedAt: Double

    public init(id: Int64, nfts: [AyuGramProfileNft], usernames: [String], background: AyuGramProfileBackground?, bubbles: Bool, hideReal: Bool = false, hiddenGifts: [String] = [], statusSlug: String? = nil, number: String? = nil, brightness: Double = 0.0, style: AyuGramProfileStyle? = nil, listBackground: AyuGramProfileBackground? = nil, updatedAt: Double) {
        self.id = id
        self.nfts = nfts
        self.usernames = usernames
        self.background = background
        self.bubbles = bubbles
        self.hideReal = hideReal
        self.hiddenGifts = hiddenGifts
        self.statusSlug = statusSlug
        self.number = number
        self.brightness = AyuGramProfileEntry.clampBrightness(brightness)
        self.style = style
        self.listBackground = listBackground
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, nfts, usernames, background, bubbles, hideReal, hiddenGifts, statusSlug, number, brightness, style, listBackground, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int64.self, forKey: .id)
        self.nfts = try container.decodeIfPresent([AyuGramProfileNft].self, forKey: .nfts) ?? []
        self.usernames = try container.decodeIfPresent([String].self, forKey: .usernames) ?? []
        self.background = try container.decodeIfPresent(AyuGramProfileBackground.self, forKey: .background)
        self.bubbles = try container.decodeIfPresent(Bool.self, forKey: .bubbles) ?? false
        self.hideReal = try container.decodeIfPresent(Bool.self, forKey: .hideReal) ?? false
        self.hiddenGifts = try container.decodeIfPresent([String].self, forKey: .hiddenGifts) ?? []
        self.statusSlug = try container.decodeIfPresent(String.self, forKey: .statusSlug)
        self.number = try container.decodeIfPresent(String.self, forKey: .number).flatMap(AyuGramProfileEntry.normalizeNumber)
        let brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 0.0
        self.brightness = AyuGramProfileEntry.clampBrightness(brightness)
        self.style = try? container.decodeIfPresent(AyuGramProfileStyle.self, forKey: .style)
        self.listBackground = try? container.decodeIfPresent(AyuGramProfileBackground.self, forKey: .listBackground)
        self.updatedAt = try container.decodeIfPresent(Double.self, forKey: .updatedAt) ?? 0.0
    }

    public var isEmpty: Bool {
        return self.nfts.isEmpty && self.usernames.isEmpty && self.background == nil && !self.bubbles && !self.hideReal && self.hiddenGifts.isEmpty && self.number == nil && self.style == nil && self.listBackground == nil
    }

    public var effectiveStyle: AyuGramProfileStyle {
        return self.style ?? AyuGramProfileStyle.standard
    }

    public var statusNft: AyuGramProfileNft? {
        guard let statusSlug = self.statusSlug?.lowercased() else {
            return nil
        }
        return self.nfts.first(where: { $0.slug?.lowercased() == statusSlug })
    }

    public func isFakeNumber(_ value: String) -> Bool {
        guard let number = self.number, let normalized = AyuGramProfileEntry.normalizeNumber(value) else {
            return false
        }
        return number == normalized
    }

    public static func clampBrightness(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0.0
        }
        return (max(-1.0, min(1.0, value)) * 100.0).rounded() / 100.0
    }

    public static func normalizeNumber(_ value: String) -> String? {
        guard value.count <= 32 else {
            return nil
        }
        var digits = String(String.UnicodeScalarView(value.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "(" && $0 != ")" && $0 != "-" }))
        if digits.hasPrefix("+") {
            digits.removeFirst()
        }
        guard digits.count == 11, digits.hasPrefix("888"), digits.unicodeScalars.allSatisfy({ $0 >= "0" && $0 <= "9" }) else {
            return nil
        }
        return "+" + digits
    }

    public static func formatNumber(_ value: String) -> String {
        guard let normalized = AyuGramProfileEntry.normalizeNumber(value) else {
            return value
        }
        let digits = Array(normalized.dropFirst())
        return "+" + String(digits[0 ..< 3]) + " " + String(digits[3 ..< 7]) + " " + String(digits[7 ..< 11])
    }

    public var orderedNfts: [AyuGramProfileNft] {
        return self.nfts.filter { $0.pinned } + self.nfts.filter { !$0.pinned }
    }

    public func isFakeUsername(_ value: String) -> Bool {
        var name = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        return self.usernames.contains(name)
    }

    public static func normalizeUsername(_ value: String) -> String? {
        var name = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("@") {
            name.removeFirst()
        }
        if let range = name.range(of: "t.me/") {
            name = String(name[range.upperBound...])
        }
        guard name.count >= 4, name.count <= 32, name.unicodeScalars.allSatisfy({ ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "_" }) else {
            return nil
        }
        return name
    }

    static func from(json: [String: Any]) -> AyuGramProfileEntry? {
        guard let idValue = json["id"], let id = Int64("\(idValue)"), id > 0 else {
            return nil
        }
        var nfts: [AyuGramProfileNft] = []
        var seenNfts = Set<String>()
        for item in ((json["nfts"] as? [[String: Any]]) ?? []).prefix(30) {
            if let nft = AyuGramProfileNft.from(json: item), !seenNfts.contains(nft.key) {
                seenNfts.insert(nft.key)
                nfts.append(nft)
            }
        }
        var usernames: [String] = []
        for item in ((json["usernames"] as? [String]) ?? []).prefix(10) {
            if let name = AyuGramProfileEntry.normalizeUsername(item), !usernames.contains(name) {
                usernames.append(name)
            }
        }
        let bubbles = (json["bubbles"] as? Bool) ?? false
        let hideReal = (json["hideReal"] as? Bool) ?? false
        let hiddenGifts = Array(((json["hiddenGifts"] as? [String]) ?? []).prefix(300))
        var statusSlug: String?
        if let status = json["status"] as? [String: Any], let slug = status["slug"] as? String, AyuGramProfileNft.isValidSlug(slug), let nft = nfts.first(where: { $0.slug?.lowercased() == slug.lowercased() }) {
            statusSlug = nft.slug
        }
        let number = (json["number"] as? String).flatMap(AyuGramProfileEntry.normalizeNumber)
        var brightness = 0.0
        if let value = json["brightness"] as? NSNumber {
            brightness = value.doubleValue
        } else if let background = json["background"] as? [String: Any], let value = background["brightness"] as? NSNumber {
            brightness = value.doubleValue
        }
        let updatedAt = (json["updatedAt"] as? NSNumber)?.doubleValue ?? 0.0
        return AyuGramProfileEntry(id: id, nfts: nfts, usernames: usernames, background: AyuGramProfileBackground.from(json: json["background"]), bubbles: bubbles, hideReal: hideReal, hiddenGifts: hiddenGifts, statusSlug: statusSlug, number: number, brightness: brightness, style: AyuGramProfileStyle.from(json: json["style"]), listBackground: AyuGramProfileBackground.from(json: json["listBackground"]), updatedAt: updatedAt)
    }
}

public struct AyuGramProfileLimits: Equatable {
    public var nfts: Int
    public var pinned: Int
    public var usernames: Int
    public var photo: Int
    public var video: Int
    public var seconds: Double
    public var numbers: Int
    public var holders: Int

    public static let standard = AyuGramProfileLimits(nfts: 30, pinned: 6, usernames: 10, photo: 1572864, video: 20971520, seconds: .infinity, numbers: 1, holders: 100)

    static func from(json: Any?) -> AyuGramProfileLimits {
        guard let json = json as? [String: Any] else {
            return .standard
        }
        let fallback = AyuGramProfileLimits.standard
        func value(_ key: String, _ defaultValue: Int) -> Int {
            if let number = json[key] as? NSNumber, number.intValue > 0 {
                return number.intValue
            }
            return defaultValue
        }
        let seconds = (json["seconds"] as? NSNumber)?.doubleValue ?? 0.0
        return AyuGramProfileLimits(nfts: value("nfts", fallback.nfts), pinned: value("pinned", fallback.pinned), usernames: value("usernames", fallback.usernames), photo: value("photo", fallback.photo), video: value("video", fallback.video), seconds: seconds > 0.0 ? seconds : fallback.seconds, numbers: value("numbers", fallback.numbers), holders: value("holders", fallback.holders))
    }
}

public struct AyuGramOwnProfile: Equatable {
    public var entry: AyuGramProfileEntry
    public var claimed: Bool
    public var verified: Bool
    public var limits: AyuGramProfileLimits
}

public struct AyuGramProfileVerification: Equatable {
    public var url: URL
    public var code: String
    public var expiresAt: Double
}

public enum AyuGramProfileError: Error, Equatable {
    case network
    case unavailable
    case locked
    case unverified
    case banned
    case blocked
    case rateLimited
    case tooLarge
    case tooLong
    case badMedia
    case unsupported
    case reservedUsername(String)
    case badUsername(String)
    case numberTaken
    case badNumber
    case statusNotOwned
    case invalid
    case server
}

public enum AyuGramProfileStatusChange: Equatable {
    case set(String)
    case clear
}

public enum AyuGramProfileNumberChange: Equatable {
    case set(String)
    case clear
}

public enum AyuGramProfileStyleChange: Equatable {
    case set(AyuGramProfileStyle)
    case clear
}

public enum AyuGramProfileMediaSlot: String {
    case main
    case list
}

public struct AyuGramProfilePatch: Equatable {
    public var nfts: [AyuGramProfileNft]?
    public var usernames: [String]?
    public var bubbles: Bool?
    public var hideReal: Bool?
    public var hiddenGifts: [String]?
    public var status: AyuGramProfileStatusChange?
    public var number: AyuGramProfileNumberChange?
    public var brightness: Double?
    public var style: AyuGramProfileStyleChange?

    public init(nfts: [AyuGramProfileNft]? = nil, usernames: [String]? = nil, bubbles: Bool? = nil, hideReal: Bool? = nil, hiddenGifts: [String]? = nil, status: AyuGramProfileStatusChange? = nil, number: AyuGramProfileNumberChange? = nil, brightness: Double? = nil, style: AyuGramProfileStyleChange? = nil) {
        self.nfts = nfts
        self.usernames = usernames
        self.bubbles = bubbles
        self.hideReal = hideReal
        self.hiddenGifts = hiddenGifts
        self.status = status
        self.number = number
        self.brightness = brightness
        self.style = style
    }

    public var isEmpty: Bool {
        return self.nfts == nil && self.usernames == nil && self.bubbles == nil && self.hideReal == nil && self.hiddenGifts == nil && self.status == nil && self.number == nil && self.brightness == nil && self.style == nil
    }

    var jsonObject: [String: Any] {
        var body: [String: Any] = [:]
        if let nfts = self.nfts {
            body["nfts"] = nfts.map { $0.jsonObject }
        }
        if let usernames = self.usernames {
            body["usernames"] = usernames
        }
        if let bubbles = self.bubbles {
            body["bubbles"] = bubbles
        }
        if let hideReal = self.hideReal {
            body["hideReal"] = hideReal
        }
        if let hiddenGifts = self.hiddenGifts {
            body["hiddenGifts"] = hiddenGifts
        }
        if let status = self.status {
            switch status {
            case let .set(slug):
                body["status"] = ["slug": slug]
            case .clear:
                body["status"] = NSNull()
            }
        }
        if let number = self.number {
            switch number {
            case let .set(value):
                body["number"] = value
            case .clear:
                body["number"] = NSNull()
            }
        }
        if let brightness = self.brightness {
            body["background"] = ["brightness": AyuGramProfileEntry.clampBrightness(brightness)]
        }
        if let style = self.style {
            switch style {
            case let .set(value):
                body["style"] = value.isStandard ? NSNull() : value.jsonObject
            case .clear:
                body["style"] = NSNull()
            }
        }
        return body
    }
}

public struct AyuGramProfileLocalMedia: Equatable {
    public let url: URL
    public let isVideo: Bool
}

public final class AyuGramProfileRelay {
    public static let shared = AyuGramProfileRelay()
    public static let didChange = Notification.Name("AyuGram.ProfileRelay.didChange")

    private let lock = NSLock()
    private var entries: [Int64: AyuGramProfileEntry] = [:]
    private var fetchedAt: [Int64: Double] = [:]
    private var pending = Set<Int64>()
    private var inFlight = Set<Int64>()
    private var flushScheduled = false
    private var etags: [String: String] = [:]
    private var unavailableUntil: Double = 0.0
    private var recent: [Int64] = []
    private var previews: [Int64: AyuGramProfileLocalMedia] = [:]
    private var listPreviews: [Int64: AyuGramProfileLocalMedia] = [:]
    private var downloading = Set<String>()
    private var mediaFailures: [String: Double] = [:]
    private var existingMedia = Set<String>()
    private var saveScheduled = false
    private var activeAccountId: Int64?
    private let queue = DispatchQueue(label: "org.ayugram.profile-relay", qos: .utility)
    private let session = URLSession(configuration: .ephemeral)
    private let freshInterval: Double = 120.0
    private let retryInterval: Double = 30.0
    private let lookupInterval: Double = 60.0
    private var holderCache: [String: (value: [AyuGramProfileHolder], fetchedAt: Double)] = [:]
    private var numberCache: [String: (value: Int64?, fetchedAt: Double)] = [:]
    private var lookupBlockedUntil: Double = 0.0

    public static let viewerDidChange = Notification.Name("AyuGram.ProfileRelay.viewerDidChange")
    private static let bubblesEnabledKey = "ayuGram.profileExtras.showBubbles"

    public static var bubblesEnabled: Bool {
        get {
            return (UserDefaults.standard.object(forKey: AyuGramProfileRelay.bubblesEnabledKey) as? Bool) ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: AyuGramProfileRelay.bubblesEnabledKey)
            let post = {
                NotificationCenter.default.post(name: AyuGramProfileRelay.viewerDidChange, object: nil)
            }
            if Thread.isMainThread {
                post()
            } else {
                DispatchQueue.main.async(execute: post)
            }
        }
    }

    private init() {
        self.loadFromDisk()
    }

    public static var baseDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent("AyuGramProfiles", isDirectory: true)
    }

    public static var mediaDirectory: URL {
        return AyuGramProfileRelay.baseDirectory.appendingPathComponent("media", isDirectory: true)
    }

    private static var storeURL: URL {
        return AyuGramProfileRelay.baseDirectory.appendingPathComponent("profiles.json")
    }

    static func mediaFileName(url: String) -> String? {
        guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http", let host = components.host, !host.isEmpty, components.user == nil, components.password == nil, components.query == nil, components.fragment == nil, url.count <= 512 else {
            return nil
        }
        let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: false)
        guard pathParts.count == 5, pathParts[1] == "profile", pathParts[2] == "media" else {
            return nil
        }
        let parts = Array(pathParts.dropFirst(3))
        guard parts.count == 2, let id = Int64(parts[0]), id > 0 else {
            return nil
        }
        let fileParts = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard fileParts.count == 2, fileParts[0].count >= 8, fileParts[0].count <= 32, fileParts[0].unicodeScalars.allSatisfy({ ($0 >= "0" && $0 <= "9") || ($0 >= "a" && $0 <= "f") }) else {
            return nil
        }
        let ext = String(fileParts[1]).lowercased()
        guard ["jpg", "jpeg", "png", "heic", "mp4", "mov"].contains(ext) else {
            return nil
        }
        return "\(id)_\(fileParts[0]).\(ext)"
    }

    static func canonicalMediaURL(_ url: String) -> String? {
        guard mediaFileName(url: url) != nil, let components = URLComponents(string: url) else {
            return nil
        }
        return AyuGramSecurity.relayURL + components.path
    }

    public var activeAccount: Int64? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.activeAccountId
    }

    public func setActiveAccount(_ rawId: Int64?) {
        self.lock.lock()
        let changed = self.activeAccountId != rawId
        self.activeAccountId = rawId
        self.lock.unlock()
        if changed, let rawId {
            self.request(rawIds: [rawId], force: true)
        }
    }

    public func entry(rawId: Int64) -> AyuGramProfileEntry? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.entries[rawId]
    }

    public func observe(rawId: Int64) -> AyuGramProfileEntry? {
        self.request(rawIds: [rawId], force: false)
        return self.entry(rawId: rawId)
    }

    public func refreshVisible() {
        self.lock.lock()
        let ids = self.recent
        self.lock.unlock()
        self.request(rawIds: ids, force: false)
    }

    public func request(rawIds: [Int64], force: Bool = false) {
        let now = Date().timeIntervalSince1970
        var scheduled = false
        self.lock.lock()
        for id in rawIds where id > 0 {
            if let index = self.recent.firstIndex(of: id) {
                self.recent.remove(at: index)
            }
            self.recent.append(id)
            if self.recent.count > 24 {
                self.recent.removeFirst(self.recent.count - 24)
            }
            if self.inFlight.contains(id) || self.pending.contains(id) {
                continue
            }
            if !force, let fetched = self.fetchedAt[id], now - fetched < self.freshInterval {
                continue
            }
            self.pending.insert(id)
            scheduled = true
        }
        let shouldFlush = scheduled && !self.flushScheduled
        if shouldFlush {
            self.flushScheduled = true
        }
        self.lock.unlock()
        if shouldFlush {
            self.queue.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.flush()
            }
        }
    }

    private func flush() {
        let now = Date().timeIntervalSince1970
        self.lock.lock()
        self.flushScheduled = false
        if now < self.unavailableUntil {
            self.etags.removeAll()
            var removed: [Int64] = []
            for id in self.pending {
                self.fetchedAt[id] = now
                if self.entries.removeValue(forKey: id) != nil {
                    removed.append(id)
                }
            }
            self.pending.removeAll()
            self.lock.unlock()
            if !removed.isEmpty {
                self.scheduleSave()
                self.notify(removed)
            }
            return
        }
        let ids = Array(self.pending).sorted()
        self.pending.removeAll()
        for id in ids {
            self.inFlight.insert(id)
        }
        self.lock.unlock()
        var index = 0
        while index < ids.count {
            let chunk = Array(ids[index ..< min(ids.count, index + 50)])
            self.fetch(chunk)
            index += 50
        }
    }

    private func fetch(_ ids: [Int64]) {
        let key = ids.map { String($0) }.joined(separator: ",")
        guard let url = URL(string: AyuGramSecurity.relayURL + "/profile?ids=" + key) else {
            self.finish(ids: ids, entries: nil, retry: true)
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        self.lock.lock()
        let etag = self.etags[key]
        self.lock.unlock()
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        self.session.dataTask(with: request, completionHandler: { [weak self] data, response, _ in
            guard let self else {
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if status == 304 {
                self.finish(ids: ids, entries: nil, retry: false)
                return
            }
            if status == 503 {
                self.lock.lock()
                self.unavailableUntil = Date().timeIntervalSince1970 + 600.0
                self.etags.removeAll()
                self.lock.unlock()
                self.finish(ids: ids, entries: [:], retry: false)
                return
            }
            guard status == 200, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let items = object["items"] as? [[String: Any]] else {
                self.finish(ids: ids, entries: nil, retry: true)
                return
            }
            var parsed: [Int64: AyuGramProfileEntry] = [:]
            for item in items.prefix(ids.count) {
                if let entry = AyuGramProfileEntry.from(json: item), ids.contains(entry.id), !entry.isEmpty {
                    parsed[entry.id] = entry
                }
            }
            if let newEtag = http?.value(forHTTPHeaderField: "ETag"), !newEtag.isEmpty, newEtag.count < 200 {
                self.lock.lock()
                if self.etags.count > 200 {
                    self.etags.removeAll()
                }
                self.etags[key] = newEtag
                self.lock.unlock()
            }
            self.finish(ids: ids, entries: parsed, retry: false)
        }).resume()
    }

    private func finish(ids: [Int64], entries parsed: [Int64: AyuGramProfileEntry]?, retry: Bool) {
        let now = Date().timeIntervalSince1970
        var changed: [Int64] = []
        self.lock.lock()
        for id in ids {
            self.inFlight.remove(id)
            if retry {
                self.fetchedAt[id] = now - self.freshInterval + self.retryInterval
            } else {
                self.fetchedAt[id] = now
            }
            if let parsed {
                let updated = parsed[id]
                if self.entries[id] != updated {
                    self.entries[id] = updated
                    changed.append(id)
                }
            }
        }
        self.lock.unlock()
        if !changed.isEmpty {
            self.scheduleSave()
            self.notify(changed)
        }
    }

    private func apply(entry: AyuGramProfileEntry) {
        var changed = false
        self.lock.lock()
        let value: AyuGramProfileEntry? = entry.isEmpty ? nil : entry
        if self.entries[entry.id] != value {
            self.entries[entry.id] = value
            changed = true
        }
        self.fetchedAt[entry.id] = Date().timeIntervalSince1970
        self.lock.unlock()
        if changed {
            self.scheduleSave()
            self.notify([entry.id])
        }
    }

    private func notify(_ ids: [Int64]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AyuGramProfileRelay.didChange, object: self, userInfo: ["peerIds": ids])
            AyuGramClientBadges.shared.touch(rawPeerIds: ids)
        }
    }

    private struct Store: Codable {
        var entries: [AyuGramProfileEntry]
        var fetched: [String: Double]
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: AyuGramProfileRelay.storeURL), let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return
        }
        for entry in store.entries where entry.id > 0 && !entry.isEmpty {
            self.entries[entry.id] = entry
            if let fetched = store.fetched[String(entry.id)] {
                self.fetchedAt[entry.id] = min(fetched, Date().timeIntervalSince1970 - self.freshInterval)
            }
        }
    }

    private func scheduleSave() {
        self.lock.lock()
        if self.saveScheduled {
            self.lock.unlock()
            return
        }
        self.saveScheduled = true
        self.lock.unlock()
        self.queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.save()
        }
    }

    private func save() {
        self.lock.lock()
        self.saveScheduled = false
        var list = Array(self.entries.values)
        list.sort(by: { (self.fetchedAt[$0.id] ?? 0.0) > (self.fetchedAt[$1.id] ?? 0.0) })
        if list.count > 1000 {
            list = Array(list.prefix(1000))
        }
        var fetched: [String: Double] = [:]
        for entry in list {
            fetched[String(entry.id)] = self.fetchedAt[entry.id] ?? 0.0
        }
        self.lock.unlock()
        guard let data = try? JSONEncoder().encode(Store(entries: list, fetched: fetched)) else {
            return
        }
        let directory = AyuGramProfileRelay.baseDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        try? data.write(to: AyuGramProfileRelay.storeURL, options: .atomic)
    }

    public func localListMedia(rawId: Int64) -> AyuGramProfileLocalMedia? {
        self.lock.lock()
        let preview = self.listPreviews[rawId]
        let background = self.entries[rawId]?.listBackground
        self.lock.unlock()
        if let preview {
            return preview
        }
        return self.cachedMedia(background: background, rawId: rawId)
    }

    public func setListPreview(rawId: Int64, url: URL, isVideo: Bool) {
        self.lock.lock()
        let previous = self.listPreviews[rawId]
        self.listPreviews[rawId] = AyuGramProfileLocalMedia(url: url, isVideo: isVideo)
        self.lock.unlock()
        if let previous, previous.url != url {
            try? FileManager.default.removeItem(at: previous.url)
        }
        self.notify([rawId])
    }

    public func clearListPreview(rawId: Int64) {
        self.lock.lock()
        let previous = self.listPreviews.removeValue(forKey: rawId)
        self.lock.unlock()
        if let previous {
            try? FileManager.default.removeItem(at: previous.url)
            self.notify([rawId])
        }
    }

    public func localMedia(rawId: Int64) -> AyuGramProfileLocalMedia? {
        self.lock.lock()
        let preview = self.previews[rawId]
        let background = self.entries[rawId]?.background
        self.lock.unlock()
        if let preview {
            return preview
        }
        return self.cachedMedia(background: background, rawId: rawId)
    }

    private func cachedMedia(background: AyuGramProfileBackground?, rawId: Int64) -> AyuGramProfileLocalMedia? {
        guard let background, let name = background.localFileName else {
            return nil
        }
        let url = AyuGramProfileRelay.mediaDirectory.appendingPathComponent(name)
        self.lock.lock()
        let known = self.existingMedia.contains(name)
        self.lock.unlock()
        if known || FileManager.default.fileExists(atPath: url.path) {
            if !known {
                self.lock.lock()
                self.existingMedia.insert(name)
                self.lock.unlock()
            }
            return AyuGramProfileLocalMedia(url: url, isVideo: background.isVideo)
        }
        self.download(background: background, name: name, rawId: rawId)
        return nil
    }

    public func setPreview(rawId: Int64, url: URL, isVideo: Bool) {
        self.lock.lock()
        let previous = self.previews[rawId]
        self.previews[rawId] = AyuGramProfileLocalMedia(url: url, isVideo: isVideo)
        self.lock.unlock()
        if let previous, previous.url != url {
            try? FileManager.default.removeItem(at: previous.url)
        }
        self.notify([rawId])
    }

    public func clearPreview(rawId: Int64) {
        self.lock.lock()
        let previous = self.previews.removeValue(forKey: rawId)
        self.lock.unlock()
        if let previous {
            try? FileManager.default.removeItem(at: previous.url)
            self.notify([rawId])
        }
    }

    public static func makePreviewURL(fileExtension: String) -> URL {
        let directory = AyuGramProfileRelay.mediaDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("preview_" + UUID().uuidString + "." + fileExtension)
    }

    private func download(background: AyuGramProfileBackground, name: String, rawId: Int64) {
        guard let canonicalURL = AyuGramProfileRelay.canonicalMediaURL(background.url), let remote = URL(string: canonicalURL) else {
            return
        }
        let now = Date().timeIntervalSince1970
        self.lock.lock()
        if self.downloading.contains(name) {
            self.lock.unlock()
            return
        }
        if let failed = self.mediaFailures[name], now - failed < 60.0 {
            self.lock.unlock()
            return
        }
        self.downloading.insert(name)
        self.lock.unlock()
        let target = AyuGramProfileRelay.mediaDirectory.appendingPathComponent(name)
        self.session.downloadTask(with: URLRequest(url: remote, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60.0), completionHandler: { [weak self] location, response, _ in
            guard let self else {
                return
            }
            var success = false
            if let location, (response as? HTTPURLResponse)?.statusCode == 200 {
                let size = ((try? FileManager.default.attributesOfItem(atPath: location.path))?[.size] as? NSNumber)?.intValue ?? 0
                if size > 0 && size <= 24 * 1024 * 1024 {
                    try? FileManager.default.createDirectory(at: AyuGramProfileRelay.mediaDirectory, withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: target)
                    success = (try? FileManager.default.moveItem(at: location, to: target)) != nil
                }
            }
            self.lock.lock()
            self.downloading.remove(name)
            if success {
                self.existingMedia.insert(name)
            } else {
                self.mediaFailures[name] = Date().timeIntervalSince1970
            }
            self.lock.unlock()
            if success {
                self.queue.async { [weak self] in
                    self?.trimMediaCache()
                }
                self.notify([rawId])
                if background.isVideo {
                    AyuGramProfileRelay.compactVideo(at: target, completion: { [weak self] changed in
                        if changed {
                            self?.notify([rawId])
                        }
                    })
                }
            }
        }).resume()
    }

    static func compactVideo(at url: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"], completionHandler: {
            guard let track = asset.tracks(withMediaType: .video).first else {
                completion(false)
                return
            }
            let oriented = track.naturalSize.applying(track.preferredTransform)
            let width = abs(oriented.width)
            let height = abs(oriented.height)
            let rate = track.nominalFrameRate
            guard width > 0, height > 0, max(width, height) > 1920.5 else {
                completion(false)
                return
            }
            let scale = min(1.0, 1920.0 / max(width, height))
            let render = CGSize(width: max(2.0, floor(width * scale / 2.0) * 2.0), height: max(2.0, floor(height * scale / 2.0) * 2.0))
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(track.preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
            instruction.layerInstructions = [layer]
            let video = AVMutableVideoComposition()
            video.renderSize = render
            video.frameDuration = CMTime(value: 1, timescale: Int32(max(24.0, min(120.0, rate > 0 ? Double(rate).rounded() : 30.0))))
            video.instructions = [instruction]
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
                completion(false)
                return
            }
            let isMov = url.pathExtension.lowercased() == "mov"
            let temporary = url.deletingLastPathComponent().appendingPathComponent("compact_" + UUID().uuidString + (isMov ? ".mov" : ".mp4"))
            session.outputURL = temporary
            session.outputFileType = isMov ? .mov : .mp4
            session.videoComposition = video
            session.shouldOptimizeForNetworkUse = true
            session.exportAsynchronously(completionHandler: {
                guard session.status == .completed, FileManager.default.fileExists(atPath: temporary.path) else {
                    try? FileManager.default.removeItem(at: temporary)
                    completion(false)
                    return
                }
                let replaced = (try? FileManager.default.replaceItemAt(url, withItemAt: temporary)) != nil
                if !replaced {
                    try? FileManager.default.removeItem(at: temporary)
                }
                completion(replaced)
            })
        })
    }

    private func store(file: URL, for background: AyuGramProfileBackground) {
        guard let name = background.localFileName else {
            return
        }
        let target = AyuGramProfileRelay.mediaDirectory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: AyuGramProfileRelay.mediaDirectory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        if (try? FileManager.default.copyItem(at: file, to: target)) != nil {
            self.lock.lock()
            self.existingMedia.insert(name)
            self.lock.unlock()
            if background.isVideo {
                AyuGramProfileRelay.compactVideo(at: target, completion: { _ in })
            }
        }
    }

    private func trimMediaCache() {
        let directory = AyuGramProfileRelay.mediaDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return
        }
        self.lock.lock()
        let protected = Set(self.previews.values.map { $0.url.lastPathComponent } + self.listPreviews.values.map { $0.url.lastPathComponent })
        self.lock.unlock()
        var items: [(url: URL, size: Int, date: Date)] = []
        var total = 0
        for file in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize ?? 0
            total += size
            items.append((url: file, size: size, date: values?.contentModificationDate ?? Date.distantPast))
        }
        guard total > 150 * 1024 * 1024 else {
            return
        }
        items.sort(by: { $0.date < $1.date })
        for item in items {
            if total <= 100 * 1024 * 1024 {
                break
            }
            if protected.contains(item.url.lastPathComponent) {
                continue
            }
            try? FileManager.default.removeItem(at: item.url)
            self.lock.lock()
            self.existingMedia.remove(item.url.lastPathComponent)
            self.lock.unlock()
            total -= item.size
        }
    }

    public func authorize(_ request: inout URLRequest, accountId: Int64) -> Bool {
        guard accountId > 0 else {
            return false
        }
        if let active = self.activeAccount, active != accountId {
            return false
        }
        request.setValue(String(accountId), forHTTPHeaderField: "X-AyuGram-Id")
        request.setValue(AyuGramBadgeSync.shared.secret, forHTTPHeaderField: "X-AyuGram-Secret")
        return true
    }

    private func authorizedRequest(path: String, method: String, accountId: Int64) -> URLRequest? {
        guard accountId > 0, let url = URL(string: AyuGramSecurity.relayURL + path) else {
            return nil
        }
        if let active = self.activeAccount, active != accountId {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        request.httpMethod = method
        request.setValue(String(accountId), forHTTPHeaderField: "X-AyuGram-Id")
        request.setValue(AyuGramBadgeSync.shared.secret, forHTTPHeaderField: "X-AyuGram-Secret")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func error(status: Int, object: [String: Any]) -> AyuGramProfileError {
        let code = (object["error"] as? String) ?? ""
        switch status {
        case 0:
            return .network
        case 503:
            return .unavailable
        case 429:
            return .rateLimited
        case 413:
            return .tooLarge
        case 415:
            return .unsupported
        case 403:
            switch code {
            case "banned":
                return .banned
            case "blocked":
                return .blocked
            case "unverified":
                return .unverified
            default:
                return .locked
            }
        case 422:
            return code == "too_long" ? .tooLong : .badMedia
        case 400:
            let value = (object["value"] as? String) ?? ""
            switch code {
            case "reserved_username":
                return .reservedUsername(value)
            case "bad_username":
                return .badUsername(value)
            case "bad_number":
                return .badNumber
            case "status_not_owned":
                return .statusNotOwned
            default:
                return .invalid
            }
        case 409:
            return code == "number_taken" ? .numberTaken : .invalid
        default:
            return .server
        }
    }

    private func parseOwn(_ object: [String: Any], accountId: Int64) -> AyuGramOwnProfile {
        var json = object
        json["id"] = String(accountId)
        let entry = AyuGramProfileEntry.from(json: json) ?? AyuGramProfileEntry(id: accountId, nfts: [], usernames: [], background: nil, bubbles: false, updatedAt: 0.0)
        return AyuGramOwnProfile(entry: entry, claimed: (object["claimed"] as? Bool) ?? false, verified: (object["verified"] as? Bool) ?? true, limits: AyuGramProfileLimits.from(json: object["limits"]))
    }

    private func perform(_ request: URLRequest, accountId: Int64, completion: @escaping (Result<AyuGramOwnProfile, AyuGramProfileError>) -> Void) {
        self.session.dataTask(with: request, completionHandler: { [weak self] data, response, error in
            guard let self else {
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let status = error == nil || code != 200 ? code : 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let result: Result<AyuGramOwnProfile, AyuGramProfileError>
            if status == 200 && object.isEmpty {
                result = .failure(.server)
            } else if status == 200 {
                let own = self.parseOwn(object, accountId: accountId)
                if own.verified {
                    self.apply(entry: own.entry)
                }
                result = .success(own)
            } else {
                result = .failure(AyuGramProfileRelay.error(status: status, object: object))
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    public func loadOwn(accountId: Int64, completion: @escaping (Result<AyuGramOwnProfile, AyuGramProfileError>) -> Void) {
        guard let request = self.authorizedRequest(path: "/profile/me", method: "GET", accountId: accountId) else {
            completion(.failure(.invalid))
            return
        }
        self.perform(request, accountId: accountId, completion: completion)
    }

    public func verificationStatus(accountId: Int64, completion: @escaping (Result<Bool, AyuGramProfileError>) -> Void) {
        guard let request = self.authorizedRequest(path: "/profile/verify/status", method: "GET", accountId: accountId) else {
            completion(.failure(.invalid))
            return
        }
        self.session.dataTask(with: request, completionHandler: { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let result: Result<Bool, AyuGramProfileError>
            if status == 200 {
                result = .success((object["verified"] as? Bool) ?? false)
            } else {
                result = .failure(AyuGramProfileRelay.error(status: status, object: object))
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    public func startVerification(accountId: Int64, completion: @escaping (Result<AyuGramProfileVerification, AyuGramProfileError>) -> Void) {
        guard var request = self.authorizedRequest(path: "/profile/verify/start", method: "POST", accountId: accountId) else {
            completion(.failure(.invalid))
            return
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        self.session.dataTask(with: request, completionHandler: { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let result: Result<AyuGramProfileVerification, AyuGramProfileError>
            if status == 200 {
                if let link = object["url"] as? String, link.hasPrefix("https://t.me/"), link.count <= 200, let url = URL(string: link) {
                    let code = String(((object["code"] as? String) ?? "").prefix(8))
                    let expiresAt = ((object["expiresAt"] as? NSNumber)?.doubleValue ?? 0.0) / 1000.0
                    result = .success(AyuGramProfileVerification(url: url, code: code, expiresAt: expiresAt > 0.0 ? expiresAt : Date().timeIntervalSince1970 + 600.0))
                } else {
                    result = .failure(.server)
                }
            } else {
                result = .failure(AyuGramProfileRelay.error(status: status, object: object))
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    public func updateOwn(accountId: Int64, patch: AyuGramProfilePatch, completion: @escaping (Result<AyuGramOwnProfile, AyuGramProfileError>) -> Void) {
        let body = patch.jsonObject
        guard !body.isEmpty, var request = self.authorizedRequest(path: "/profile", method: "PUT", accountId: accountId), let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.invalid))
            return
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        self.perform(request, accountId: accountId, completion: { [weak self] result in
            self?.invalidateLookups()
            completion(result)
        })
    }

    private func invalidateLookups() {
        self.lock.lock()
        self.holderCache.removeAll()
        self.numberCache.removeAll()
        self.lock.unlock()
    }

    public func cachedHolders(slug: String) -> [AyuGramProfileHolder]? {
        let key = slug.lowercased()
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let cached = self.holderCache[key], Date().timeIntervalSince1970 - cached.fetchedAt < self.lookupInterval else {
            return nil
        }
        return cached.value
    }

    public func holders(slug: String, completion: @escaping (Result<[AyuGramProfileHolder], AyuGramProfileError>) -> Void) {
        guard AyuGramProfileNft.isValidSlug(slug), let encoded = slug.addingPercentEncoding(withAllowedCharacters: .alphanumerics), let url = URL(string: AyuGramSecurity.relayURL + "/profile/holders?slug=" + encoded) else {
            completion(.failure(.invalid))
            return
        }
        let key = slug.lowercased()
        if let cached = self.cachedHolders(slug: key) {
            completion(.success(cached))
            return
        }
        let now = Date().timeIntervalSince1970
        self.lock.lock()
        let blocked = now < self.lookupBlockedUntil || now < self.unavailableUntil
        self.lock.unlock()
        if blocked {
            completion(.failure(.rateLimited))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        self.session.dataTask(with: request, completionHandler: { [weak self] data, response, _ in
            guard let self else {
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let result: Result<[AyuGramProfileHolder], AyuGramProfileError>
            if status == 200, let items = object["items"] as? [[String: Any]] {
                var holders: [AyuGramProfileHolder] = []
                var seen = Set<Int64>()
                for item in items.prefix(100) {
                    guard let idValue = item["id"], let id = Int64("\(idValue)"), id > 0, !seen.contains(id) else {
                        continue
                    }
                    seen.insert(id)
                    holders.append(AyuGramProfileHolder(id: id, pinned: (item["pinned"] as? Bool) ?? false))
                }
                self.lock.lock()
                if self.holderCache.count > 200 {
                    self.holderCache.removeAll()
                }
                self.holderCache[key] = (value: holders, fetchedAt: Date().timeIntervalSince1970)
                self.lock.unlock()
                result = .success(holders)
            } else {
                if status == 429 || status == 503 {
                    self.lock.lock()
                    self.lookupBlockedUntil = Date().timeIntervalSince1970 + 300.0
                    self.lock.unlock()
                }
                result = .failure(AyuGramProfileRelay.error(status: status, object: object))
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    public func cachedNumberHolder(number: String) -> Int64?? {
        guard let normalized = AyuGramProfileEntry.normalizeNumber(number) else {
            return .some(nil)
        }
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        guard let cached = self.numberCache[normalized], Date().timeIntervalSince1970 - cached.fetchedAt < self.lookupInterval else {
            return nil
        }
        return .some(cached.value)
    }

    public func numberHolder(number: String, completion: @escaping (Result<Int64?, AyuGramProfileError>) -> Void) {
        guard let normalized = AyuGramProfileEntry.normalizeNumber(number), let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .alphanumerics), let url = URL(string: AyuGramSecurity.relayURL + "/profile/number?n=" + encoded) else {
            completion(.success(nil))
            return
        }
        if let cached = self.cachedNumberHolder(number: normalized) {
            completion(.success(cached))
            return
        }
        let now = Date().timeIntervalSince1970
        self.lock.lock()
        let blocked = now < self.lookupBlockedUntil || now < self.unavailableUntil
        self.lock.unlock()
        if blocked {
            completion(.failure(.rateLimited))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20.0)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        self.session.dataTask(with: request, completionHandler: { [weak self] data, response, _ in
            guard let self else {
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let result: Result<Int64?, AyuGramProfileError>
            if status == 200 || status == 404 {
                var holder: Int64?
                if status == 200, let idValue = object["id"], let id = Int64("\(idValue)"), id > 0 {
                    holder = id
                }
                self.lock.lock()
                if self.numberCache.count > 200 {
                    self.numberCache.removeAll()
                }
                self.numberCache[normalized] = (value: holder, fetchedAt: Date().timeIntervalSince1970)
                self.lock.unlock()
                result = .success(holder)
            } else {
                if status == 429 || status == 503 {
                    self.lock.lock()
                    self.lookupBlockedUntil = Date().timeIntervalSince1970 + 300.0
                    self.lock.unlock()
                }
                result = .failure(AyuGramProfileRelay.error(status: status, object: object))
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }).resume()
    }

    public func removeBackground(accountId: Int64, slot: AyuGramProfileMediaSlot = .main, completion: @escaping (Result<AyuGramOwnProfile, AyuGramProfileError>) -> Void) {
        guard let request = self.authorizedRequest(path: slot == .list ? "/profile/background?slot=list" : "/profile/background", method: "DELETE", accountId: accountId) else {
            completion(.failure(.invalid))
            return
        }
        if slot == .list {
            self.clearListPreview(rawId: accountId)
        } else {
            self.clearPreview(rawId: accountId)
        }
        self.perform(request, accountId: accountId, completion: completion)
    }

    public func removeAll(accountId: Int64, completion: @escaping (Result<AyuGramOwnProfile, AyuGramProfileError>) -> Void) {
        guard let request = self.authorizedRequest(path: "/profile", method: "DELETE", accountId: accountId) else {
            completion(.failure(.invalid))
            return
        }
        self.clearPreview(rawId: accountId)
        self.clearListPreview(rawId: accountId)
        self.perform(request, accountId: accountId, completion: { [weak self] result in
            self?.invalidateLookups()
            completion(result)
        })
    }

    public func uploadBackground(accountId: Int64, slot: AyuGramProfileMediaSlot = .main, file: URL, mime: String, width: Int, height: Int, progress: @escaping (Double) -> Void, completion: @escaping (Result<AyuGramOwnProfile, AyuGramProfileError>) -> Void) {
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, var request = self.authorizedRequest(path: slot == .list ? "/profile/background?slot=list" : "/profile/background", method: "PUT", accountId: accountId) else {
            completion(.failure(.badMedia))
            return
        }
        request.timeoutInterval = 120.0
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        if width > 0 && height > 0 {
            request.setValue(String(width), forHTTPHeaderField: "X-AyuGram-Width")
            request.setValue(String(height), forHTTPHeaderField: "X-AyuGram-Height")
        }
        let delegate = AyuGramProfileUploadDelegate(progress: { value in
            DispatchQueue.main.async {
                progress(value)
            }
        }, completion: { [weak self] status, data in
            guard let self else {
                return
            }
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let result: Result<AyuGramOwnProfile, AyuGramProfileError>
            if status == 200 && object.isEmpty {
                result = .failure(.server)
            } else if status == 200 {
                let own = self.parseOwn(object, accountId: accountId)
                if let background = slot == .list ? own.entry.listBackground : own.entry.background {
                    self.store(file: file, for: background)
                }
                self.apply(entry: own.entry)
                result = .success(own)
            } else {
                result = .failure(AyuGramProfileRelay.error(status: status, object: object))
            }
            DispatchQueue.main.async {
                completion(result)
            }
        })
        let uploadSession = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        uploadSession.uploadTask(with: request, fromFile: file).resume()
        uploadSession.finishTasksAndInvalidate()
    }
}

private final class AyuGramProfileUploadDelegate: NSObject, URLSessionDataDelegate {
    private let progress: (Double) -> Void
    private let completion: (Int, Data?) -> Void
    private var data = Data()

    init(progress: @escaping (Double) -> Void, completion: @escaping (Int, Data?) -> Void) {
        self.progress = progress
        self.completion = completion
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 {
            self.progress(min(1.0, max(0.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend))))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let code = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let status = error == nil || code != 200 ? code : 0
        self.completion(status, self.data.isEmpty ? nil : self.data)
    }
}
