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

/// The shared app group container. A sideloaded install is usually signed
/// without the `group.<bundle id>` app group, so the system returns nil; the
/// main app then keeps its data in a private Library directory instead of
/// refusing to start. Extensions get nil and keep their existing handling.
public func sgAppGroupContainerURL(_ identifier: String = sgAppGroupIdentifier()) -> URL? {
    if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
        return url
    }
    guard !Bundle.main.bundlePath.hasSuffix(".appex"), let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
        return nil
    }
    let url = library.appendingPathComponent("AppGroupFallback", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    return url
}

public func sgAppGroupIdentifier() -> String {
    let result: String = "group.\(sgBaseBundleIdentifier())"
    
    #if DEBUG
    print("APP_GROUP_IDENTIFIER: \(result)")
    #endif
    
    return result
}
