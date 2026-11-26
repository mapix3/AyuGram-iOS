import Foundation

public enum AyuGramLarpBalance {
    public static let didChange = Notification.Name("AyuGramLarpBalanceDidChange")
    private static let starsKey = "ayugram.larp.stars"
    private static let tonKey = "ayugram.larp.ton"

    public static var stars: Int64? {
        get {
            return (UserDefaults.standard.object(forKey: starsKey) as? NSNumber)?.int64Value
        }
        set {
            if let newValue, newValue >= 0 {
                UserDefaults.standard.set(NSNumber(value: newValue), forKey: starsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: starsKey)
            }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    public static var tonNano: Int64? {
        get {
            return (UserDefaults.standard.object(forKey: tonKey) as? NSNumber)?.int64Value
        }
        set {
            if let newValue, newValue >= 0 {
                UserDefaults.standard.set(NSNumber(value: newValue), forKey: tonKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tonKey)
            }
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    public static func parseStars(_ text: String) -> Int64? {
        let digits = text.filter { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 15 else {
            return nil
        }
        return Int64(digits)
    }

    public static func parseTon(_ text: String) -> Int64? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty, let value = Decimal(string: cleaned), value >= 0, value < 1_000_000_000 else {
            return nil
        }
        let nano = NSDecimalNumber(decimal: value * Decimal(1_000_000_000)).int64Value
        return nano
    }

    public static func formatTon(_ nano: Int64) -> String {
        let value = NSDecimalNumber(value: nano).dividing(by: NSDecimalNumber(value: 1_000_000_000))
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 9
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value) ?? "\(nano)"
    }
}
