import Foundation

public enum AyuGramIconSettings {
    private static let key = "swiftgram.ayuGram.iconSelection.v1"
    public static var selectedName: String? { UserDefaults.standard.string(forKey: key) }
    public static func select(_ name: String?) {
        UserDefaults.standard.set(name ?? "AyuClassic", forKey: key)
    }
}
