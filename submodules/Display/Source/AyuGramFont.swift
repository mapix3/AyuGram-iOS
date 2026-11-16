import UIKit
import CoreText
import SGSimpleSettings

public enum AyuGramFontOverride {
    private static let family: String = {
        let settings = AyuGramPersonalization.shared.settings
        if settings.fontFamily == "custom" {
            guard let url = AyuGramPersonalization.shared.customFontURL, !settings.customFontFamily.isEmpty else {
                return ""
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            return settings.customFontFamily
        }
        return settings.fontFamily
    }()

    public static var isActive: Bool {
        return !self.family.isEmpty
    }

    public static func font(size: CGFloat, weight: UIFont.Weight, italic: Bool = false) -> UIFont? {
        let family = self.family
        if family.isEmpty {
            return nil
        }
        return self.make(family: family, size: size, weight: weight, italic: italic)
    }

    public static func make(family: String, size: CGFloat, weight: UIFont.Weight, italic: Bool = false) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        var descriptor: UIFontDescriptor
        switch family {
        case "rounded":
            descriptor = base.withDesign(.rounded) ?? base
        case "serif":
            descriptor = base.withDesign(.serif) ?? base
        case "mono":
            descriptor = base.withDesign(.monospaced) ?? base
        default:
            descriptor = UIFontDescriptor(fontAttributes: [.family: family, .traits: [UIFontDescriptor.TraitKey.weight: weight]])
        }
        if italic, let updated = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) {
            descriptor = updated
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}
