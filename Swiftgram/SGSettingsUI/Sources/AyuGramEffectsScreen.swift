import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import SGItemListUI
import SGSimpleSettings
import SGStrings

private enum AyuEffectsSection: Int32 {
    case master, background, density, speed, grain, bubbles, animations, interface
}

private enum AyuEffectsToggle: Equatable {
    case enabled, reactToTouch, aurora, parallax, ripple, glow, glass, textReveal, avatarRings
}

private enum AyuEffectsPicker: Equatable {
    case particles, deleteStyle, sendStyle
}

private enum AyuEffectsSlider: Equatable {
    case density, speed, grain
}

private enum AyuEffectsTint: Equatable {
    case purple, indigo, blue, teal, green, orange, red, pink, gray

    var color: UIColor {
        switch self {
        case .purple: return AyuGramRowColor.purple
        case .indigo: return AyuGramRowColor.indigo
        case .blue: return AyuGramRowColor.blue
        case .teal: return AyuGramRowColor.teal
        case .green: return AyuGramRowColor.green
        case .orange: return AyuGramRowColor.orange
        case .red: return AyuGramRowColor.red
        case .pink: return AyuGramRowColor.pink
        case .gray: return AyuGramRowColor.gray
        }
    }
}

private final class AyuEffectsArguments {
    let toggle: (AyuEffectsToggle, Bool) -> Void
    let pick: (AyuEffectsPicker) -> Void
    let slide: (AyuEffectsSlider, Int32) -> Void

    init(toggle: @escaping (AyuEffectsToggle, Bool) -> Void, pick: @escaping (AyuEffectsPicker) -> Void, slide: @escaping (AyuEffectsSlider, Int32) -> Void) {
        self.toggle = toggle
        self.pick = pick
        self.slide = slide
    }
}

private enum AyuEffectsEntry: ItemListNodeEntry {
    case header(id: Int, section: AyuEffectsSection, text: String)
    case toggle(id: Int, section: AyuEffectsSection, key: AyuEffectsToggle, symbol: String, tint: AyuEffectsTint, title: String, subtitle: String?, value: Bool, enabled: Bool)
    case picker(id: Int, section: AyuEffectsSection, key: AyuEffectsPicker, symbol: String, tint: AyuEffectsTint, title: String, label: String, enabled: Bool)
    case slider(id: Int, section: AyuEffectsSection, key: AyuEffectsSlider, value: Int32)
    case footer(id: Int, section: AyuEffectsSection, text: String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .footer(_, section, _):
            return section.rawValue
        case let .toggle(_, section, _, _, _, _, _, _, _):
            return section.rawValue
        case let .picker(_, section, _, _, _, _, _, _):
            return section.rawValue
        case let .slider(_, section, _, _):
            return section.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case let .header(id, _, _), let .footer(id, _, _):
            return id
        case let .toggle(id, _, _, _, _, _, _, _, _):
            return id
        case let .picker(id, _, _, _, _, _, _, _):
            return id
        case let .slider(id, _, _, _):
            return id
        }
    }

    static func <(lhs: AyuEffectsEntry, rhs: AyuEffectsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! AyuEffectsArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .toggle(_, _, key, symbol, tint, title, subtitle, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: enabled ? tint.color : AyuGramRowColor.gray), title: title, text: subtitle, value: value, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .picker(_, _, key, symbol, tint, title, label, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: ayuGramRowIcon(symbol, color: enabled ? tint.color : AyuGramRowColor.gray), title: title, enabled: enabled, label: label, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.pick(key)
                }
            })
        case let .slider(_, _, key, value):
            return SliderPercentageItem(theme: presentationData.theme, strings: presentationData.strings, value: value, sectionId: self.section, systemStyle: .glass, updated: { value in
                arguments.slide(key, value)
            })
        case let .footer(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func ayuEffectsParticlesKey(_ value: AyuGramEffectsSettings.Particles) -> String {
    switch value {
    case .off: return "Ayu.Effects.Particles.Off"
    case .snow: return "Ayu.Effects.Particles.Snow"
    case .stars: return "Ayu.Effects.Particles.Stars"
    case .fireflies: return "Ayu.Effects.Particles.Fireflies"
    case .petals: return "Ayu.Effects.Particles.Petals"
    case .bubbles: return "Ayu.Effects.Particles.Bubbles"
    }
}

private func ayuEffectsDeleteKey(_ value: AyuGramEffectsSettings.DeleteStyle) -> String {
    switch value {
    case .standard: return "Ayu.Effects.Delete.Standard"
    case .dust: return "Ayu.Effects.Delete.Dust"
    case .burn: return "Ayu.Effects.Delete.Burn"
    case .shatter: return "Ayu.Effects.Delete.Shatter"
    case .implode: return "Ayu.Effects.Delete.Implode"
    }
}

private func ayuEffectsSendKey(_ value: AyuGramEffectsSettings.SendStyle) -> String {
    switch value {
    case .standard: return "Ayu.Effects.Send.Standard"
    case .spring: return "Ayu.Effects.Send.Spring"
    case .sparkles: return "Ayu.Effects.Send.Sparkles"
    case .warp: return "Ayu.Effects.Send.Warp"
    }
}

private func ayuEffectsPercent(_ value: Double) -> Int32 {
    return Int32((max(0.0, min(1.0, value)) * 100.0).rounded())
}

private func ayuEffectsEntries(data: PresentationData, effects: AyuGramEffectsSettings) -> [AyuEffectsEntry] {
    let locale = data.strings.baseLanguageCode
    func s(_ key: String) -> String {
        return i18n(key, locale)
    }
    let on = effects.enabled
    var entries: [AyuEffectsEntry] = []

    entries.append(.toggle(id: 10, section: .master, key: .enabled, symbol: "sparkles", tint: .purple, title: s("Ayu.Effects.Master"), subtitle: nil, value: on, enabled: true))
    entries.append(.footer(id: 20, section: .master, text: s("Ayu.Effects.MasterInfo")))

    entries.append(.header(id: 100, section: .background, text: s("Ayu.Effects.BackgroundSection")))
    entries.append(.picker(id: 110, section: .background, key: .particles, symbol: "snowflake", tint: .blue, title: s("Ayu.Effects.Particles"), label: s(ayuEffectsParticlesKey(effects.particles)), enabled: on))
    entries.append(.toggle(id: 120, section: .background, key: .reactToTouch, symbol: "hand.point.up.left.fill", tint: .orange, title: s("Ayu.Effects.ReactToTouch"), subtitle: nil, value: effects.particlesReactToTouch, enabled: on && effects.particles != .off))
    entries.append(.toggle(id: 130, section: .background, key: .aurora, symbol: "rays", tint: .teal, title: s("Ayu.Effects.Aurora"), subtitle: s("Ayu.Effects.AuroraInfo"), value: effects.auroraGradient, enabled: on))
    entries.append(.toggle(id: 140, section: .background, key: .parallax, symbol: "square.3.layers.3d", tint: .indigo, title: s("Ayu.Effects.Parallax"), subtitle: s("Ayu.Effects.ParallaxInfo"), value: effects.deepParallax, enabled: on))
    entries.append(.toggle(id: 150, section: .background, key: .ripple, symbol: "drop.fill", tint: .blue, title: s("Ayu.Effects.Ripple"), subtitle: s("Ayu.Effects.RippleInfo"), value: effects.backgroundRipple, enabled: on))
    entries.append(.footer(id: 160, section: .background, text: s("Ayu.Effects.BackgroundFooter")))

    if on && effects.particles != .off {
        entries.append(.header(id: 200, section: .density, text: s("Ayu.Effects.ParticleDensity")))
        entries.append(.slider(id: 210, section: .density, key: .density, value: ayuEffectsPercent(effects.particleDensity)))
        entries.append(.header(id: 300, section: .speed, text: s("Ayu.Effects.ParticleSpeed")))
        entries.append(.slider(id: 310, section: .speed, key: .speed, value: ayuEffectsPercent(effects.particleSpeed)))
    }
    if on {
        entries.append(.header(id: 400, section: .grain, text: s("Ayu.Effects.Grain")))
        entries.append(.slider(id: 410, section: .grain, key: .grain, value: ayuEffectsPercent(effects.gradientGrain)))
        entries.append(.footer(id: 420, section: .grain, text: s("Ayu.Effects.GrainInfo")))
    }

    entries.append(.header(id: 500, section: .bubbles, text: s("Ayu.Effects.BubblesSection")))
    entries.append(.toggle(id: 510, section: .bubbles, key: .glow, symbol: "light.max", tint: .pink, title: s("Ayu.Effects.BubbleGlow"), subtitle: s("Ayu.Effects.BubbleGlowInfo"), value: effects.bubbleGlow, enabled: on))
    entries.append(.toggle(id: 520, section: .bubbles, key: .glass, symbol: "bubble.left.and.bubble.right.fill", tint: .teal, title: s("Ayu.Effects.GlassBubbles"), subtitle: s("Ayu.Effects.GlassBubblesInfo"), value: effects.glassBubbles, enabled: on))

    entries.append(.header(id: 600, section: .animations, text: s("Ayu.Effects.AnimationsSection")))
    entries.append(.picker(id: 610, section: .animations, key: .deleteStyle, symbol: "trash.fill", tint: .red, title: s("Ayu.Effects.DeleteStyle"), label: s(ayuEffectsDeleteKey(effects.deleteStyle)), enabled: on))
    entries.append(.picker(id: 620, section: .animations, key: .sendStyle, symbol: "paperplane.fill", tint: .blue, title: s("Ayu.Effects.SendStyle"), label: s(ayuEffectsSendKey(effects.sendStyle)), enabled: on))
    entries.append(.toggle(id: 630, section: .animations, key: .textReveal, symbol: "text.bubble.fill", tint: .green, title: s("Ayu.Effects.TextReveal"), subtitle: s("Ayu.Effects.TextRevealInfo"), value: effects.incomingTextReveal, enabled: on))
    entries.append(.footer(id: 640, section: .animations, text: s("Ayu.Effects.AnimationsFooter")))

    entries.append(.header(id: 700, section: .interface, text: s("Ayu.Effects.InterfaceSection")))
    entries.append(.toggle(id: 710, section: .interface, key: .avatarRings, symbol: "circle.dashed", tint: .purple, title: s("Ayu.Effects.AvatarRings"), subtitle: s("Ayu.Effects.AvatarRingsInfo"), value: effects.avatarRings, enabled: on))
    entries.append(.footer(id: 720, section: .interface, text: s("Ayu.Effects.InterfaceFooter")))
    return entries
}

private func ayuEffectsPresentChoice<T: Equatable>(context: AccountContext, present: ((ViewController) -> Void)?, options: [T], current: T, title: (T) -> String, select: @escaping (T) -> Void) {
    let data = context.sharedContext.currentPresentationData.with { $0 }
    let sheet = ActionSheetController(presentationData: data)
    var items: [ActionSheetItem] = []
    for option in options {
        items.append(ActionSheetButtonItem(title: (option == current ? "✓ " : "") + title(option), color: .accent, action: { [weak sheet] in
            sheet?.dismissAnimated()
            select(option)
        }))
    }
    sheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [ActionSheetButtonItem(title: data.strings.Common_Cancel, color: .accent, action: { [weak sheet] in sheet?.dismissAnimated() })])
    ])
    present?(sheet)
}

public func ayuGramEffectsController(context: AccountContext) -> ViewController {
    var presentController: ((ViewController) -> Void)?
    let changes = Signal<Int, NoError> { subscriber in
        subscriber.putNext(0)
        let observer = NotificationCenter.default.addObserver(forName: AyuGramSettings.effectsDidChange, object: nil, queue: .main) { _ in
            subscriber.putNext(0)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    let arguments = AyuEffectsArguments(toggle: { key, value in
        AyuGramSettings.shared.updateEffects { effects in
            switch key {
            case .enabled: effects.enabled = value
            case .reactToTouch: effects.particlesReactToTouch = value
            case .aurora: effects.auroraGradient = value
            case .parallax: effects.deepParallax = value
            case .ripple: effects.backgroundRipple = value
            case .glow: effects.bubbleGlow = value
            case .glass: effects.glassBubbles = value
            case .textReveal: effects.incomingTextReveal = value
            case .avatarRings: effects.avatarRings = value
            }
        }
    }, pick: { key in
        let locale = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        let effects = AyuGramSettings.shared.effects
        switch key {
        case .particles:
            ayuEffectsPresentChoice(context: context, present: presentController, options: AyuGramEffectsSettings.Particles.allCases, current: effects.particles, title: { i18n(ayuEffectsParticlesKey($0), locale) }, select: { value in
                AyuGramSettings.shared.updateEffects { $0.particles = value }
            })
        case .deleteStyle:
            ayuEffectsPresentChoice(context: context, present: presentController, options: AyuGramEffectsSettings.DeleteStyle.allCases, current: effects.deleteStyle, title: { i18n(ayuEffectsDeleteKey($0), locale) }, select: { value in
                AyuGramSettings.shared.updateEffects { $0.deleteStyle = value }
            })
        case .sendStyle:
            ayuEffectsPresentChoice(context: context, present: presentController, options: AyuGramEffectsSettings.SendStyle.allCases, current: effects.sendStyle, title: { i18n(ayuEffectsSendKey($0), locale) }, select: { value in
                AyuGramSettings.shared.updateEffects { $0.sendStyle = value }
            })
        }
    }, slide: { key, value in
        let fraction = Double(max(0, min(100, value))) / 100.0
        let effects = AyuGramSettings.shared.effects
        switch key {
        case .density:
            if ayuEffectsPercent(effects.particleDensity) != value {
                AyuGramSettings.shared.updateEffects { $0.particleDensity = fraction }
            }
        case .speed:
            if ayuEffectsPercent(effects.particleSpeed) != value {
                AyuGramSettings.shared.updateEffects { $0.particleSpeed = fraction }
            }
        case .grain:
            if ayuEffectsPercent(effects.gradientGrain) != value {
                AyuGramSettings.shared.updateEffects { $0.gradientGrain = fraction }
            }
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, changes)
    |> deliverOnMainQueue
    |> map { data, _ -> (ItemListControllerState, (ItemListNodeState, AyuEffectsArguments)) in
        let entries = ayuEffectsEntries(data: data, effects: AyuGramSettings.shared.effects)
        let state = ItemListControllerState(presentationData: ItemListPresentationData(data), title: .text(i18n("Ayu.Effects.Title", data.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: data.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(data), entries: entries, style: .blocks, animateChanges: true)
        return (state, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    presentController = { [weak controller] next in
        controller?.present(next, in: .window(.root))
    }
    return controller
}
