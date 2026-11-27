import Foundation

public func doesUrlMatchText(url: String, text: String, fullText: String) -> Bool {
    if fullText.range(of: "\u{202e}") != nil {
        return false
    }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
    if !url.unicodeScalars.allSatisfy({ allowed.contains($0) }) {
        return false
    }
    if url == text {
        return true
    }
    return false
}

public extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        let generalDelimitersToEncode = ":#[]@"
        let subDelimitersToEncode = "!$&'()*+,;="
        
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: generalDelimitersToEncode + subDelimitersToEncode)
        
        return allowed
    }()
}

public func isValidUrl(_ url: String, validSchemes: [String: Bool] = ["http": true, "https": true, "tonsite": true]) -> Bool {
    if let escapedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: escapedUrl), let scheme = url.scheme?.lowercased(), let requiresTopLevelDomain = validSchemes[scheme], let host = url.host, (!requiresTopLevelDomain || host.contains(".")) && url.user == nil {
        if requiresTopLevelDomain {
            let components = host.components(separatedBy: ".")
            let domain = (components.last ?? "")
            if domain.isEmpty {
                return false
            }
        }
        return true
    } else {
        return false
    }
}

public func explicitUrl(_ url: String) -> String {
    var url = url
    if !url.lowercased().hasPrefix("http:") && !url.lowercased().hasPrefix("https:") && !url.lowercased().hasPrefix("tonsite:") && url.range(of: "://") == nil {
        if let parsedUrl = URL(string: "http://\(url)"), parsedUrl.host?.hasSuffix(".ton") == true {
            url = "tonsite://\(url)"
        } else {
            url = "https://\(url)"
        }
    }
    return url
}

private let validUrlSet: CharacterSet = {
    var set = CharacterSet(charactersIn: "a".unicodeScalars.first! ... "z".unicodeScalars.first!)
    set.insert(charactersIn: "A".unicodeScalars.first! ... "Z".unicodeScalars.first!)
    set.insert(charactersIn: "0".unicodeScalars.first! ... "9".unicodeScalars.first!)
    set.insert(charactersIn: ".?!@#$^&%*-+=,:;'\"`<>()[]{}/\\|~ ")
    return set
}()

public func urlEncodedStringFromString(_ string: String) -> String {
    var nsString: NSString = string as NSString
    if let value = nsString.removingPercentEncoding {
        nsString = value as NSString
    }
    return nsString.addingPercentEncoding(withAllowedCharacters: validUrlSet) ?? ""
}

public let ayuGramDeepLinkBridgeBase = "https://marketplace.mapixdev.com/go/"

public func ayuGramBridgedDeepLink(_ url: String) -> String {
    let scheme = "ayugram://"
    guard url.lowercased().hasPrefix(scheme) else {
        return url
    }
    let rest = String(url.dropFirst(scheme.count))
    if rest.isEmpty {
        return ayuGramDeepLinkBridgeBase + "settings"
    }
    return ayuGramDeepLinkBridgeBase + rest
}

public func ayuGramDeepLinkFromBridge(_ url: String) -> String? {
    if url.lowercased().hasPrefix("ayugram://") {
        return url
    }
    guard let components = URLComponents(string: url), let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http", let host = components.host?.lowercased() else {
        return nil
    }
    let prefix: String
    switch host {
    case "marketplace.mapixdev.com":
        prefix = "/go/"
    case "relay.mapixdev.com":
        prefix = "/market/go/"
    default:
        return nil
    }
    let path = components.percentEncodedPath
    guard path.lowercased().hasPrefix(prefix) else {
        return nil
    }
    let rest = String(path.dropFirst(prefix.count))
    if rest.isEmpty {
        return nil
    }
    var result = "ayugram://" + rest
    if let query = components.percentEncodedQuery, !query.isEmpty {
        result += "?" + query
    }
    return result
}
