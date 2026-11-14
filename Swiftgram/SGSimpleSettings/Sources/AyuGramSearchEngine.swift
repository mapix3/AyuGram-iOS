import Foundation

public struct AyuGramSearchEngine {
    public let title: String
    public let base: String
    public let parameter: String

    public static let all: [AyuGramSearchEngine] = [
        AyuGramSearchEngine(title: "Google", base: "https://www.google.com/search", parameter: "q"),
        AyuGramSearchEngine(title: "DuckDuckGo", base: "https://duckduckgo.com/", parameter: "q"),
        AyuGramSearchEngine(title: "Bing", base: "https://www.bing.com/search", parameter: "q"),
        AyuGramSearchEngine(title: "Yandex", base: "https://yandex.com/search/", parameter: "text"),
        AyuGramSearchEngine(title: "Brave", base: "https://search.brave.com/search", parameter: "q")
    ]

    public static var current: AyuGramSearchEngine {
        let index = Int(AyuGramSettings.shared.extra.searchEngine)
        return index >= 0 && index < all.count ? all[index] : all[0]
    }

    public func url(query: String) -> String? {
        var components = URLComponents(string: self.base)
        components?.queryItems = [URLQueryItem(name: self.parameter, value: query)]
        return components?.url?.absoluteString
    }
}
