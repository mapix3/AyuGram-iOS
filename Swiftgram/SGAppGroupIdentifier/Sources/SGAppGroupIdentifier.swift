import Foundation

public let FALLBACK_BASE_BUNDLE_ID: String = "app.swiftgram.ios"

public func sgBaseBundleIdentifier() -> String {
    let baseBundleId: String
    if let bundleId: String = Bundle.main.bundleIdentifier {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            if let lastDotRange: Range<String.Index> = bundleId.range(of: ".", options: [.backwards]) {
                baseBundleId = String(bundleId[..<lastDotRange.lowerBound])
            } else {
                baseBundleId = FALLBACK_BASE_BUNDLE_ID
            }
        } else {
            baseBundleId = bundleId
        }
    } else {
        baseBundleId = FALLBACK_BASE_BUNDLE_ID
    }
    return baseBundleId
}

private func sgProvisionedAppGroups() -> [String] {
    var candidates: [String] = []
    if let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") {
        candidates.append(path)
    }
    if Bundle.main.bundlePath.hasSuffix(".appex") {
        let appPath = URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("embedded.mobileprovision").path
        candidates.append(appPath)
    }
    for path in candidates {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .isoLatin1), let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>", range: start.upperBound ..< text.endIndex) else {
            continue
        }
        let xml = String(text[start.lowerBound ..< end.upperBound])
        guard let plistData = xml.data(using: .isoLatin1), let plist = (try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)) as? [String: Any], let entitlements = plist["Entitlements"] as? [String: Any], let groups = entitlements["com.apple.security.application-groups"] as? [String], !groups.isEmpty else {
            continue
        }
        return groups
    }
    return []
}

private var sgResolvedGroups: [String: String] = [:]
private let sgResolvedGroupsLock = NSLock()

public func sgResolvedAppGroupIdentifier(base: String) -> String {
    let preferred = "group.\(base)"
    sgResolvedGroupsLock.lock()
    if let cached = sgResolvedGroups[base] {
        sgResolvedGroupsLock.unlock()
        return cached
    }
    sgResolvedGroupsLock.unlock()
    var result = preferred
    if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: preferred) == nil {
        let groups = sgProvisionedAppGroups().filter { !$0.contains("*") }
        let ranked = groups.filter { $0.contains(base) } + groups.filter { !$0.contains(base) }
        if let found = ranked.first(where: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }) {
            result = found
        }
    }
    sgResolvedGroupsLock.lock()
    sgResolvedGroups[base] = result
    sgResolvedGroupsLock.unlock()
    return result
}

private func sgMoveFallback(from fallback: URL, to container: URL) -> Bool {
    let manager = FileManager.default
    guard let items = try? manager.contentsOfDirectory(atPath: fallback.path), !items.isEmpty else {
        return true
    }
    if items.contains("telegram-data") && manager.fileExists(atPath: container.appendingPathComponent("telegram-data").path) {
        return false
    }
    var moved: [String] = []
    for item in items {
        let source = fallback.appendingPathComponent(item)
        let target = container.appendingPathComponent(item)
        if manager.fileExists(atPath: target.path) {
            continue
        }
        do {
            try manager.moveItem(at: source, to: target)
            moved.append(item)
        } catch {
            for back in moved.reversed() {
                try? manager.moveItem(at: container.appendingPathComponent(back), to: fallback.appendingPathComponent(back))
            }
            return false
        }
    }
    return true
}

public func sgAppGroupContainerURL(_ identifier: String = sgAppGroupIdentifier()) -> URL? {
    let isExtension = Bundle.main.bundlePath.hasSuffix(".appex")
    let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
    let fallback = library?.appendingPathComponent("AppGroupFallback", isDirectory: true)
    let preferred = "group.\(sgBaseBundleIdentifier())"
    let resolved = identifier == preferred ? sgResolvedAppGroupIdentifier(base: sgBaseBundleIdentifier()) : identifier
    if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: resolved) {
        if !isExtension, resolved != preferred, let fallback, FileManager.default.fileExists(atPath: fallback.path) {
            if !sgMoveFallback(from: fallback, to: url) {
                return fallback
            }
            if let rest = try? FileManager.default.contentsOfDirectory(atPath: fallback.path), rest.isEmpty {
                try? FileManager.default.removeItem(at: fallback)
            }
        }
        return url
    }
    guard !isExtension, let fallback else {
        return nil
    }
    try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true, attributes: nil)
    return fallback
}

public func sgAppGroupIdentifier() -> String {
    let result: String = sgResolvedAppGroupIdentifier(base: sgBaseBundleIdentifier())
    
    #if DEBUG
    print("APP_GROUP_IDENTIFIER: \(result)")
    #endif
    
    return result
}
